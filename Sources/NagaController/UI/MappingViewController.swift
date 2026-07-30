import Cocoa
import UniformTypeIdentifiers
import QuartzCore

/// Top-left-origin stack for scroll documents, so the editor opens scrolled
/// to its header instead of the AppKit default bottom-left origin.
private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

/// Device-first mapping editor. The sidebar is the effective chain itself:
/// devices own their profiles, one profile per device is active, and the grid
/// on the right always shows one explicit (device × profile) pair — display,
/// intercept judgment and edits all target that same pair.
final class MappingViewController: NSViewController {

    // MARK: - Sidebar model

    private final class SidebarNode: NSObject {
        enum Kind {
            case devicesGroup
            case archivedGroup
            case unmountedGroup
            case device(String)
            case profile(deviceKey: String, name: String)
            case addProfile(deviceKey: String)
            case unmountedProfile(String)
        }
        let kind: Kind
        var children: [SidebarNode]
        init(kind: Kind, children: [SidebarNode] = []) {
            self.kind = kind
            self.children = children
        }
    }

    private var sidebarRoots: [SidebarNode] = []
    private var isReloadingSidebar = false

    /// The explicit editing pair. `selectedProfileName == nil` means the
    /// device row is selected and the grid follows the device's active
    /// profile.
    private var selectedDeviceKey: String?
    private var selectedProfileName: String?

    // MARK: - Views

    private let outlineView = NSOutlineView()
    private let sidebarScroll = NSScrollView()
    private let sidebarContainer = NSStackView()
    private let sidebarToggleButton = NSButton()
    private let compactProfilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let headerLabel: NSTextField = {
        let l = NSTextField(labelWithString: L10n.text("按键映射"))
        l.font = Typography.windowTitle
        return l
    }()
    private let autosaveLabel: NSTextField = {
        let l = NSTextField(labelWithString: L10n.text("✓ 更改已自动保存"))
        l.font = Typography.bodySecondary
        l.textColor = DesignSystem.Colors.textSecondary
        return l
    }()

    private let contextHeaderStack = NSStackView()
    private let contextTitleLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = Typography.windowTitle
        l.lineBreakMode = .byTruncatingTail
        l.focusRingType = .exterior
        (l.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        return l
    }()
    private let contextTransportLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = Typography.windowTitle
        l.textColor = DesignSystem.Colors.textSecondary
        return l
    }()
    private var detailsPopover: NSPopover?
    /// Editable text fields report no intrinsic width, so the device-context
    /// title gets an explicit measured width; inactive in other contexts.
    private var contextTitleWidthConstraint: NSLayoutConstraint?
    private let contextStatusLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = Typography.bodySecondary
        l.textColor = DesignSystem.Colors.textSecondary
        l.lineBreakMode = .byTruncatingTail
        return l
    }()
    private var contextButtonsRow = NSStackView()
    private let ownershipLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = Typography.bodySecondary
        l.textColor = DesignSystem.Colors.textSecondary
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private var grid: NSGridView?
    private var sideKeysGridStack: NSStackView!
    private var sideKeysSection: ThemeSectionView!
    private var dpiSection: ThemeSectionView!
    private var scrollSection: ThemeSectionView!
    private var dpiRowContainer: NSStackView!
    private var scrollRowContainer: NSStackView!
    private var customGroupsStack: NSStackView!
    private var customGroupSections: [String: ThemeSectionView] = [:]
    private var customGroupGrids: [String: NSStackView] = [:]
    /// Present standard side-key indices last laid out, so a device with some
    /// keys removed reflows instead of leaving gaps.
    private var shownSideKeyIndices: [Int] = Array(1...12)
    /// Custom-source indices currently shown as cards, so a device switch can
    /// tear down the previous device's custom cards.
    private var shownCustomIndices: [Int] = []
    private var rightScrollView: NSScrollView?
    private var containerMinWidthConstraint: NSLayoutConstraint!
    /// Current side-key column count; 0 until the first relayout.
    private var sideKeysColumns = 0
    /// Cross-card equal-width constraints (present, visible cards only).
    private var cardWidthEqualizers: [NSLayoutConstraint] = []
    /// Signature (columns + present indices) last laid out, to skip redundant
    /// rebuilds.
    private var lastLayoutSignature = ""
    private var rowViews: [Int: NSView] = [:]
    private var titleLabels: [Int: NSTextField] = [:]
    private var sectionViews: [Int: ThemeSectionView] = [:]
    private var descLabels: [Int: NSTextField] = [:]
    private var sourceLabels: [Int: NSTextField] = [:]
    private var interceptToggles: [Int: NSSwitch] = [:]
    private var modifierSwapViews: [Int: ThemeToggleView] = [:]
    private var editButtons: [Int: NSButton] = [:]
    private var clearButtons: [Int: NSButton] = [:]
    private var container: NSStackView!
    private var inputStateObserver: NSObjectProtocol?
    private var permissionObserver: NSObjectProtocol?
    private var configObservers: [NSObjectProtocol] = []
    private var refreshQueued = false
    private struct ContextEditTarget {
        let deviceKey: String
        let profileName: String?
    }
    private var contextEditTarget: ContextEditTarget?

    private static let sidebarCollapsedDefaultsKey = "MappingSidebarCollapsed"

    deinit {
        if let inputStateObserver { NotificationCenter.default.removeObserver(inputStateObserver) }
        if let permissionObserver { NotificationCenter.default.removeObserver(permissionObserver) }
        configObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Layout

    override func loadView() {
        self.view = NSView()
        self.view.translatesAutoresizingMaskIntoConstraints = false

        let background = UIStyle.makeBackground(material: .windowBackground)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // ── Top bar ──
        let topBar = NSStackView()
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 8
        topBar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 6, right: 16)

        sidebarToggleButton.bezelStyle = .texturedRounded
        sidebarToggleButton.image = UIStyle.symbol("sidebar.left", size: 14, weight: .medium)
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleSidebar)
        sidebarToggleButton.toolTip = L10n.text("显示/隐藏设备与配置列表")

        compactProfilePopup.target = self
        compactProfilePopup.action = #selector(compactProfileChanged(_:))
        compactProfilePopup.toolTip = L10n.text("切换此设备当前启用的配置")

        let tutorialButton = ThemeButton(title: L10n.text("帮助中心"), target: self, action: #selector(tutorialTapped))
        tutorialButton.toolTip = L10n.text("打开帮助中心")
        tutorialButton.buttonType = .normal

        autosaveLabel.toolTip = L10n.text("所有更改都会立即保存，无需手动操作")

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        topBar.addArrangedSubview(sidebarToggleButton)
        topBar.addArrangedSubview(headerLabel)
        topBar.addArrangedSubview(compactProfilePopup)
        topBar.addArrangedSubview(spacer)
        topBar.addArrangedSubview(autosaveLabel)
        topBar.addArrangedSubview(tutorialButton)

        // ── Sidebar ──
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.rowSizeStyle = .medium
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 12
        // Breathing room between rows so devices and profiles don't read as a
        // cramped block.
        outlineView.intercellSpacing = NSSize(width: 0, height: 6)
        outlineView.autoresizesOutlineColumn = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        let sidebarMenu = NSMenu()
        sidebarMenu.delegate = self
        outlineView.menu = sidebarMenu

        sidebarScroll.documentView = outlineView
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.drawsBackground = false
        outlineView.backgroundColor = .clear

        let importButton = ThemeButton(title: L10n.text("导入..."), target: self, action: #selector(importProfilesTapped))
        importButton.buttonType = .normal
        let exportAllButton = ThemeButton(title: L10n.text("导出全部..."), target: self, action: #selector(exportAllProfilesTapped))
        exportAllButton.buttonType = .normal
        let sidebarFooter = NSStackView(views: [importButton, exportAllButton])
        sidebarFooter.orientation = .horizontal
        sidebarFooter.spacing = 6
        sidebarFooter.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)

        sidebarContainer.orientation = .vertical
        sidebarContainer.spacing = 0
        sidebarContainer.addArrangedSubview(sidebarScroll)
        sidebarContainer.addArrangedSubview(sidebarFooter)
        sidebarContainer.widthAnchor.constraint(equalToConstant: 224).isActive = true
        sidebarScroll.widthAnchor.constraint(equalTo: sidebarContainer.widthAnchor).isActive = true

        // ── Right pane: context header + ownership bar + card grid ──
        contextButtonsRow.orientation = .horizontal
        contextButtonsRow.spacing = 8

        contextTitleLabel.target = self
        contextTitleLabel.action = #selector(deviceNameEdited(_:))
        contextTitleLabel.delegate = self
        contextTitleWidthConstraint = contextTitleLabel.widthAnchor.constraint(equalToConstant: 200)
        // The title must hug its text so the transport suffix and status sit
        // right beside it; the trailing spacer absorbs the rest.
        contextTitleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contextTransportLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        contextStatusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let contextSpacer = NSView()
        contextSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        contextSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let contextTitleRow = NSStackView(views: [contextTitleLabel, contextTransportLabel, contextStatusLabel, contextSpacer])
        contextTitleRow.orientation = .horizontal
        contextTitleRow.alignment = .firstBaseline
        contextTitleRow.spacing = 10
        contextTitleRow.setCustomSpacing(2, after: contextTitleLabel)

        contextHeaderStack.orientation = .vertical
        contextHeaderStack.alignment = .leading
        contextHeaderStack.spacing = 8
        contextHeaderStack.addArrangedSubview(contextTitleRow)
        contextHeaderStack.addArrangedSubview(contextButtonsRow)
        contextTitleRow.widthAnchor.constraint(equalTo: contextHeaderStack.widthAnchor).isActive = true

        // Cards are created once; row stacks are rebuilt around them when the
        // column count changes (3 wide / 2 narrow), so a narrow window
        // reflows instead of scrolling sideways.
        sideKeysGridStack = NSStackView()
        sideKeysGridStack.orientation = .vertical
        sideKeysGridStack.spacing = 12
        sideKeysGridStack.alignment = .centerX
        sideKeysGridStack.distribution = .fill
        for index in 1...12 {
            let card = makeCard(for: index)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true
            rowViews[index] = card
        }

        dpiRowContainer = NSStackView()
        dpiRowContainer.orientation = .horizontal
        dpiRowContainer.spacing = 12
        dpiRowContainer.distribution = .fill
        for index in [13, 14] {
            let card = makeCard(for: index)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true
            rowViews[index] = card
            dpiRowContainer.addArrangedSubview(card)
        }
        scrollRowContainer = NSStackView()
        scrollRowContainer.orientation = .horizontal
        scrollRowContainer.spacing = 12
        scrollRowContainer.distribution = .fill
        for index in [15, 16] {
            let card = makeCard(for: index)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true
            rowViews[index] = card
            scrollRowContainer.addArrangedSubview(card)
        }

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .centerX
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let sideKeysSection = ThemeSectionView(title: L10n.text("侧键 1–12"))
        self.sideKeysSection = sideKeysSection
        sideKeysSection.contentStack.addArrangedSubview(sideKeysGridStack)
        contentStack.addArrangedSubview(sideKeysSection)
        sideKeysSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        setupEditableSection(sideKeysSection, tag: 0)

        let dpiSection = ThemeSectionView(title: L10n.text("DPI ±"))
        self.dpiSection = dpiSection
        dpiSection.contentStack.addArrangedSubview(dpiRowContainer)
        contentStack.addArrangedSubview(dpiSection)
        setupEditableSection(dpiSection, tag: 1)

        let scrollSection = ThemeSectionView(title: L10n.text("滚轮左右键"))
        self.scrollSection = scrollSection
        scrollSection.contentStack.addArrangedSubview(scrollRowContainer)
        contentStack.addArrangedSubview(scrollSection)
        setupEditableSection(scrollSection, tag: 2)

        // Custom sources (added in the hardware sheet for other button counts)
        // get their own section, shown only when the device has any.
        customGroupsStack = NSStackView()
        customGroupsStack.orientation = .vertical
        customGroupsStack.spacing = 20
        customGroupsStack.alignment = .centerX
        contentStack.addArrangedSubview(customGroupsStack)
        customGroupsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        // All input groups share one ordered stack. The three legacy section
        // views are reused, but can now appear before, between or after custom
        // groups according to the device-owned group order.
        for section in [sideKeysSection, dpiSection, scrollSection] {
            section.removeFromSuperview()
            customGroupsStack.addArrangedSubview(section)
        }

        dpiSection.widthAnchor.constraint(equalTo: sideKeysSection.widthAnchor).isActive = true
        scrollSection.widthAnchor.constraint(equalTo: sideKeysSection.widthAnchor).isActive = true

        container = FlippedStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        container.addArrangedSubview(contextHeaderStack)
        container.addArrangedSubview(ownershipLabel)
        let separator = NSBox()
        separator.boxType = .separator
        separator.titlePosition = .noTitle
        container.addArrangedSubview(separator)
        container.addArrangedSubview(contentStack)
        container.addArrangedSubview(UIStyle.makeFooter(L10n.text("先在设备上读取板载键值，再为配置设置 Mac 自定义键值，之后即可开启拦截。所有更改自动保存。")))
        contextHeaderStack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true
        contentStack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -32).isActive = true

        rightScrollView = NSScrollView()
        let rightScroll = rightScrollView!
        rightScroll.hasVerticalScroller = true
        rightScroll.hasHorizontalScroller = true
        rightScroll.autohidesScrollers = true
        rightScroll.drawsBackground = false
        rightScroll.documentView = container
        container.translatesAutoresizingMaskIntoConstraints = false
        containerMinWidthConstraint = container.widthAnchor.constraint(greaterThanOrEqualToConstant: 940)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: rightScroll.contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: rightScroll.contentView.topAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: rightScroll.contentView.widthAnchor),
            containerMinWidthConstraint
        ])

        let sidebarSeparator = NSBox()
        sidebarSeparator.boxType = .separator
        sidebarSeparator.titlePosition = .noTitle

        let body = NSStackView(views: [sidebarContainer, sidebarSeparator, rightScroll])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = 0
        sidebarSeparator.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        sidebarContainer.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        rightScroll.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        // The scroller must claim all width the sidebar leaves over —
        // without this pin a small container minimum lets the whole right
        // pane shrink and strands empty space beside it.
        rightScroll.trailingAnchor.constraint(equalTo: body.trailingAnchor).isActive = true

        let root = NSStackView(views: [topBar, body])
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topBar.widthAnchor.constraint(equalTo: root.widthAnchor),
            body.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        // Grid is laid out by the first refreshRows(); nothing to pre-build.

        applyInitialSidebarState()
        ensureValidSelection()
        reloadSidebar()
        refreshRows()

        inputStateObserver = NotificationCenter.default.addObserver(
            forName: InputCoordinator.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
        permissionObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.scheduleRefresh() }
        for name in [
            ConfigManager.presentationDidChangeNotification,
            ConfigManager.profileStructureDidChangeNotification,
            ConfigManager.runtimeRoutingDidChangeNotification
        ] {
            configObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in self?.scheduleRefresh() })
        }
        configObservers.append(NotificationCenter.default.addObserver(
            forName: ConfigManager.saveStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateAutosaveState() })
        updateAutosaveState()
    }

    private func updateAutosaveState() {
        if let error = ConfigManager.shared.lastProfileSaveError {
            autosaveLabel.stringValue = L10n.text("⚠ 更改未保存")
            autosaveLabel.textColor = UIStyle.warningColor
            autosaveLabel.toolTip = error
        } else {
            autosaveLabel.stringValue = L10n.text("✓ 更改已自动保存")
            autosaveLabel.textColor = DesignSystem.Colors.textSecondary
            autosaveLabel.toolTip = nil
        }
    }

    // MARK: - Responsive side-key grid

    /// Rebuild the side-key rows around the existing cards for the given
    /// column count and present index set. Cards are created exactly once;
    /// only the row containers and the cross-card equal-width constraints are
    /// rebuilt, so card state (editing, toggles) survives a reflow. A device
    /// with some standard keys removed reflows the remaining ones with no gaps.
    /// Rebuild the whole card grid for the current device and column count.
    /// Side keys reflow into `columns`-wide rows (padded so fillEqually keeps a
    /// uniform width); DPI/wheel/custom cards match that width via equalizer
    /// constraints tied to the first present side card. Only PRESENT, visible
    /// cards get constraints, so removing keys never leaves a hidden card tied
    /// to a visible width (which made Auto Layout diverge).
    private func rebuildGrid() {
        let present = ConfigManager.shared.sourceIndices(forDeviceKey: selectedDeviceKey)
        let presentSet = Set(present)
        let groups = ConfigManager.shared.inputGroups(forDeviceKey: selectedDeviceKey)
        let columns = currentColumns()
        func indices(_ id: String) -> [Int] {
            groups.first(where: { $0.id == id })?.sourceIndices.filter { presentSet.contains($0) } ?? []
        }
        let sideIndices = indices(DeviceInputGroup.sideID)
        let dpiIndices = indices(DeviceInputGroup.dpiID)
        let scrollIndices = indices(DeviceInputGroup.scrollID)
        let customIndices = groups.filter { !$0.isBuiltIn }.flatMap(\.sourceIndices).filter { presentSet.contains($0) }

        let signature = "\(columns)|\(groups)"
        guard signature != lastLayoutSignature else { return }
        lastLayoutSignature = signature
        sideKeysColumns = columns
        shownSideKeyIndices = sideIndices

        NSLayoutConstraint.deactivate(cardWidthEqualizers)
        cardWidthEqualizers = []

        // Side keys: padded fillEqually rows pinned to the grid width.
        for row in sideKeysGridStack.arrangedSubviews {
            (row as? NSStackView)?.arrangedSubviews.forEach { $0.removeFromSuperview() }
            row.removeFromSuperview()
        }
        for chunkStart in stride(from: 0, to: sideIndices.count, by: columns) {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 12
            rowStack.distribution = .fillEqually
            let slice = sideIndices[chunkStart..<min(chunkStart + columns, sideIndices.count)]
            for index in slice { if let card = rowViews[index] { rowStack.addArrangedSubview(card) } }
            for _ in slice.count..<columns {
                let filler = NSView(); filler.translatesAutoresizingMaskIntoConstraints = false
                rowStack.addArrangedSubview(filler)
            }
            sideKeysGridStack.addArrangedSubview(rowStack)
            rowStack.widthAnchor.constraint(equalTo: sideKeysGridStack.widthAnchor).isActive = true
        }

        for view in dpiRowContainer.arrangedSubviews { view.removeFromSuperview() }
        for index in dpiIndices { if let card = rowViews[index] { dpiRowContainer.addArrangedSubview(card) } }
        for view in scrollRowContainer.arrangedSubviews { view.removeFromSuperview() }
        for index in scrollIndices { if let card = rowViews[index] { scrollRowContainer.addArrangedSubview(card) } }

        // Section visibility.
        sideKeysSection.isHidden = sideIndices.isEmpty
        for i in [13, 14, 15, 16] { rowViews[i]?.isHidden = !presentSet.contains(i) }
        dpiSection.isHidden = dpiIndices.isEmpty
        scrollSection.isHidden = scrollIndices.isEmpty
        for i in shownCustomIndices { rowViews[i]?.isHidden = !presentSet.contains(i) }

        // DPI/wheel/custom cards match the first present side card's width.
        // With no side keys the extra sections size to their own content.
        if let referenceIndex = sideIndices.first, let reference = rowViews[referenceIndex] {
            for index in dpiIndices + scrollIndices + customIndices {
                guard let card = rowViews[index] else { continue }
                cardWidthEqualizers.append(card.widthAnchor.constraint(equalTo: reference.widthAnchor))
            }
            NSLayoutConstraint.activate(cardWidthEqualizers)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateResponsiveLayout()
    }

    /// Narrow windows reflow to 2 columns instead of scrolling sideways; the
    /// container's minimum width follows so 640pt fits without a horizontal
    /// scroller.
    private func updateResponsiveLayout() {
        guard let rightScrollView else { return }
        let width = rightScrollView.frame.width
        guard width > 0 else { return }
        // 860 keeps the default 1120pt window on 3 columns even with the
        // 224pt sidebar open; anything narrower reflows to 2.
        let columns = width < 860 ? 2 : 3
        guard columns != sideKeysColumns else { return }
        containerMinWidthConstraint.constant = columns == 3 ? 860 : 620
        // Reflow every section to the new column count in one pass.
        refreshCustomSources()
        rebuildGrid()
    }

    /// Column count for the current right-pane width (2 when narrow, else 3).
    private func currentColumns() -> Int {
        guard let width = rightScrollView?.frame.width, width > 0 else {
            return sideKeysColumns == 0 ? 3 : sideKeysColumns
        }
        return width < 860 ? 2 : 3
    }

    /// Notification bursts (every write posts) collapse into one refresh per
    /// runloop turn so the sidebar and 16 cards rebuild once, not five times.
    private func scheduleRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.ensureValidSelection()
            self.reloadSidebar()
            self.refreshRows()
        }
    }

    // MARK: - Selection state

    /// Deep-link entry: the status-bar popover's device rows land here.
    func select(deviceKey: String) {
        selectedDeviceKey = deviceKey
        selectedProfileName = nil
        ConfigManager.shared.setEditingDevice(key: deviceKey)
        if isViewLoaded { scheduleRefresh() }
    }

    private func knownDeviceKeys() -> [String] {
        ConfigManager.shared.knownDeviceKeys()
    }

    private func ensureValidSelection() {
        let known = knownDeviceKeys()
        // A selection may become invalid because the device was archived —
        // treat an archived selection as needing a fresh active fallback.
        let selectionArchived = selectedDeviceKey.map { ConfigManager.shared.isDeviceArchived($0) } ?? false
        if selectedDeviceKey == nil || !known.contains(selectedDeviceKey ?? "") || selectionArchived {
            let active = known.filter { !ConfigManager.shared.isDeviceArchived($0) }
            let recent = HIDListener.shared.lastInputDeviceKey
            selectedDeviceKey = (recent.map { active.contains($0) ? $0 : nil } ?? nil)
                ?? active.first
                ?? known.first
            selectedProfileName = nil
        }
        if let deviceKey = selectedDeviceKey, let profile = selectedProfileName,
           !ConfigManager.shared.profileNames(forDeviceKey: deviceKey).contains(profile) {
            selectedProfileName = nil
        }
        ConfigManager.shared.setEditingDevice(key: selectedDeviceKey)
    }

    /// The one profile the grid displays and edits.
    private func displayedProfileName() -> String? {
        if let profile = selectedProfileName { return profile }
        if let deviceKey = selectedDeviceKey {
            return ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey)
        }
        return nil
    }

    private func activeProfileName() -> String? {
        selectedDeviceKey.flatMap { ConfigManager.shared.effectiveProfileName(forDeviceKey: $0) }
    }

    // MARK: - Sidebar data

    private func deviceNode(_ deviceKey: String) -> SidebarNode {
        var children: [SidebarNode] = ConfigManager.shared.profileNames(forDeviceKey: deviceKey).map {
            SidebarNode(kind: .profile(deviceKey: deviceKey, name: $0))
        }
        children.append(SidebarNode(kind: .addProfile(deviceKey: deviceKey)))
        return SidebarNode(kind: .device(deviceKey), children: children)
    }

    private func rebuildSidebarTree() {
        let archived = Set(ConfigManager.shared.archivedDeviceKeys())
        let activeNodes = knownDeviceKeys().filter { !archived.contains($0) }.map(deviceNode)
        var roots: [SidebarNode] = [SidebarNode(kind: .devicesGroup, children: activeNodes)]
        if !archived.isEmpty {
            roots.append(SidebarNode(
                kind: .archivedGroup,
                children: archived.sorted().map(deviceNode)
            ))
        }
        let unmounted = ConfigManager.shared.unmountedProfileNames()
        if !unmounted.isEmpty {
            roots.append(SidebarNode(
                kind: .unmountedGroup,
                children: unmounted.map { SidebarNode(kind: .unmountedProfile($0)) }
            ))
        }
        sidebarRoots = roots
    }

    private func reloadSidebar() {
        isReloadingSidebar = true
        defer { isReloadingSidebar = false }
        rebuildSidebarTree()
        outlineView.reloadData()
        // Device profiles stay collapsed by default; only the top-level device
        // group and the currently selected device expand, so the sidebar opens
        // compact. The archived and unmounted groups also start collapsed.
        for root in sidebarRoots where isGroupKind(root.kind) {
            if case .devicesGroup = root.kind {
                outlineView.expandItem(root)
                if let selectedDeviceKey {
                    for child in root.children {
                        if case .device(let key) = child.kind, key == selectedDeviceKey {
                            outlineView.expandItem(child)
                        }
                    }
                }
            }
        }
        restoreSidebarSelection()
        reloadCompactProfilePopup()
    }

    private func isGroupKind(_ kind: SidebarNode.Kind) -> Bool {
        switch kind {
        case .devicesGroup, .archivedGroup, .unmountedGroup: return true
        default: return false
        }
    }

    private func restoreSidebarSelection() {
        var targetRow = -1
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? SidebarNode else { continue }
            switch node.kind {
            case .device(let key):
                if selectedProfileName == nil && key == selectedDeviceKey { targetRow = row }
            case .profile(let deviceKey, let name):
                if deviceKey == selectedDeviceKey && name == selectedProfileName { targetRow = row }
            default:
                break
            }
            if targetRow >= 0 { break }
        }
        if targetRow >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        } else {
            outlineView.deselectAll(nil)
        }
    }

    // MARK: - Compact profile switcher (sidebar collapsed)

    private func reloadCompactProfilePopup() {
        compactProfilePopup.removeAllItems()
        guard sidebarContainer.isHidden, let deviceKey = selectedDeviceKey else {
            compactProfilePopup.isHidden = true
            return
        }
        let names = ConfigManager.shared.profileNames(forDeviceKey: deviceKey)
        guard !names.isEmpty else {
            compactProfilePopup.isHidden = true
            return
        }
        compactProfilePopup.isHidden = false
        let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey)
        let deviceName = ConfigManager.shared.deviceDisplayName(forKey: deviceKey)
        for name in names {
            let item = NSMenuItem(title: L10n.format("%@ ▸ 配置「%@」", deviceName, name), action: nil, keyEquivalent: "")
            item.representedObject = name
            compactProfilePopup.menu?.addItem(item)
            if name == active { compactProfilePopup.select(item) }
        }
    }

    @objc private func compactProfileChanged(_ sender: NSPopUpButton) {
        guard let deviceKey = selectedDeviceKey,
              let name = sender.selectedItem?.representedObject as? String else { return }
        // One-step switching: picking a profile in the compact popup activates
        // it on the device — the single-device fast path.
        ConfigManager.shared.setActiveProfile(name, forDeviceKey: deviceKey)
        selectedProfileName = nil
        scheduleRefresh()
    }

    // MARK: - Sidebar visibility

    private func applyInitialSidebarState() {
        let defaults = UserDefaults.standard
        let collapsed: Bool
        if defaults.object(forKey: Self.sidebarCollapsedDefaultsKey) != nil {
            collapsed = defaults.bool(forKey: Self.sidebarCollapsedDefaultsKey)
        } else {
            // Single-device users start with the simple one-line form; the
            // sidebar exists for the moment a second device or profile shows.
            collapsed = knownDeviceKeys().count <= 1
        }
        sidebarContainer.isHidden = collapsed
    }

    @objc private func toggleSidebar() {
        sidebarContainer.isHidden.toggle()
        UserDefaults.standard.set(sidebarContainer.isHidden, forKey: Self.sidebarCollapsedDefaultsKey)
        reloadCompactProfilePopup()
    }

    // MARK: - Context header + ownership bar

    private func refreshContextHeader() {
        let titleIsEditing = contextTitleLabel.currentEditor() != nil
        contextButtonsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !titleIsEditing {
            contextTitleLabel.isEditable = false
            contextTitleLabel.isBordered = false
            contextTitleLabel.drawsBackground = false
            contextTitleLabel.toolTip = nil
            contextTitleWidthConstraint?.isActive = false
        }
        contextTransportLabel.stringValue = ""
        guard let deviceKey = selectedDeviceKey else {
            contextTitleLabel.stringValue = L10n.text("未检测到设备")
            contextStatusLabel.stringValue = L10n.text("连接鼠标后会自动出现在这里")
            ownershipLabel.stringValue = ""
            return
        }
        let deviceName = ConfigManager.shared.deviceDisplayName(forKey: deviceKey)
        let table = ConfigManager.shared.hardwareMapping(forConfigKey: deviceKey)
        let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey)

        if let profile = selectedProfileName {
            // Profile context: the title is the profile name, editable inline
            // to rename it.
            if !titleIsEditing {
                contextTitleLabel.isEditable = true
                contextTitleLabel.stringValue = profile
                contextTitleLabel.placeholderString = profile
                contextTitleLabel.toolTip = L10n.text("点击可重命名配置")
            }
            let measured = (contextTitleLabel.stringValue.isEmpty ? profile : contextTitleLabel.stringValue) as NSString
            let width = measured.size(withAttributes: [.font: Typography.windowTitle]).width
            contextTitleWidthConstraint?.constant = max(120, ceil(width) + 20)
            contextTitleWidthConstraint?.isActive = true
            let users = ConfigManager.shared.deviceKeysUsing(profile: profile)
                .map { ConfigManager.shared.deviceDisplayName(forKey: $0) }
            contextStatusLabel.stringValue = users.isEmpty
                ? L10n.text("未被任何设备使用")
                : L10n.format("使用此配置的设备（%d）：%@", users.count, users.joined(separator: "、"))
            if profile == active {
                let badge = NSTextField(labelWithString: L10n.text("✓ 此设备启用中"))
                badge.font = Typography.bodySecondary
                badge.textColor = DesignSystem.Colors.accentText
                contextButtonsRow.addArrangedSubview(badge)
            } else {
                let activate = ThemeButton(title: L10n.format("在「%@」启用此配置", deviceName), target: self, action: #selector(activateSelectedProfileTapped))
                activate.buttonType = .primary
                contextButtonsRow.addArrangedSubview(activate)
                let hintText = active.map { L10n.format("此设备当前启用「%@」，下方改动保存但暂不生效", $0) }
                    ?? L10n.text("此设备当前未启用配置，下方改动保存但暂不生效")
                let hint = NSTextField(labelWithString: hintText)
                hint.font = Typography.bodySecondary
                hint.textColor = UIStyle.warningColor
                contextButtonsRow.addArrangedSubview(hint)
            }
        } else {
            // Device context: the title is the user's editable custom name;
            // the original product name lives in the placeholder and the
            // details panel, so a rename never hides identity facts.
            if !titleIsEditing {
                contextTitleLabel.isEditable = true
                contextTitleLabel.stringValue = ConfigManager.shared.deviceBaseName(forKey: deviceKey)
                contextTitleLabel.placeholderString = ConfigManager.shared.deviceOriginalName(forKey: deviceKey)
                contextTitleLabel.toolTip = L10n.text("点击自定义设备名，清空恢复原始名称")
            }
            let measured = (contextTitleLabel.stringValue.isEmpty
                ? (contextTitleLabel.placeholderString ?? "")
                : contextTitleLabel.stringValue) as NSString
            let width = measured.size(withAttributes: [.font: Typography.windowTitle]).width
            contextTitleWidthConstraint?.constant = max(120, ceil(width) + 20)
            contextTitleWidthConstraint?.isActive = true
            if let transport = ConfigManager.shared.deviceTransportDisplayLabel(forKey: deviceKey) {
                contextTransportLabel.stringValue = " · \(transport)"
            }
            if table.isEmpty {
                contextStatusLabel.stringValue = active == nil
                    ? L10n.text("⚠ 板载键值未录入 · 未启用配置")
                    : L10n.text("⚠ 板载键值未录入 — 先读取板载键值")
            } else {
                contextStatusLabel.stringValue = active.map {
                    L10n.format("板载键值已录入 %d 键 · 启用配置「%@」", table.count, $0)
                } ?? L10n.format("板载键值已录入 %d 键 · 未启用配置", table.count)
            }
            let readButton = ThemeButton(title: L10n.text("读取板载键值..."), target: self, action: #selector(hardwareDefinitionTapped))
            readButton.buttonType = table.isEmpty ? .primary : .normal
            readButton.toolTip = L10n.text("读取侧键 1–12、DPI± 和滚轮左右键当前的板载输出")
            contextButtonsRow.addArrangedSubview(readButton)
            let detailsButton = ThemeButton(title: L10n.text("设备详情..."), target: self, action: #selector(deviceDetailsTapped(_:)))
            detailsButton.buttonType = .normal
            detailsButton.toolTip = L10n.text("查看原始设备名与全部识别信息")
            contextButtonsRow.addArrangedSubview(detailsButton)
            // Recovery path: offer another device's learned table only while
            // this one is empty.
            if table.isEmpty {
                let sources = ConfigManager.shared.getDeviceConfigurations().filter { key, value in
                    key != deviceKey && !(value.hardwareMapping?.isEmpty ?? true)
                }
                if !sources.isEmpty {
                    let copyPopup = NSPopUpButton(frame: .zero, pullsDown: true)
                    copyPopup.target = self
                    copyPopup.action = #selector(copyMappingSelected(_:))
                    copyPopup.menu?.addItem(NSMenuItem(title: L10n.text("复制板载键值表自..."), action: nil, keyEquivalent: ""))
                    for (key, value) in sources.sorted(by: { $0.key < $1.key }) {
                        let item = NSMenuItem(title: value.displayName ?? key, action: nil, keyEquivalent: "")
                        item.representedObject = key
                        copyPopup.menu?.addItem(item)
                    }
                    contextButtonsRow.addArrangedSubview(copyPopup)
                }
            }
        }

        if let profile = displayedProfileName() {
            ownershipLabel.stringValue = L10n.format("动作：配置「%@」 · 键名/板载键值/拦截：设备「%@」", profile, deviceName)
        } else {
            ownershipLabel.stringValue = ""
        }
    }

    // MARK: - Cards

    private func makeCard(for index: Int) -> NSView {
        let card = ThemeCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let v = NSStackView()
        v.orientation = .vertical
        v.spacing = 5
        v.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        let title = NSTextField(string: displayName(for: index))
        title.font = Typography.cardTitle
        title.textColor = DesignSystem.Colors.textPrimary
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .exterior
        title.placeholderString = InputSourceCatalog.mappingName(for: index)
        title.toolTip = L10n.text("点击可自定义键名，清空恢复默认（键名属于设备）")
        title.tag = index
        title.target = self
        title.action = #selector(buttonNameEdited(_:))
        (title.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        titleLabels[index] = title

        titleRow.addArrangedSubview(title)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let modifierSwap = ThemeToggleView(title: L10n.text("⌘ ⇄ Control"))
        modifierSwap.switchControl.controlSize = .mini
        modifierSwap.switchControl.target = self
        modifierSwap.switchControl.action = #selector(modifierSwapToggled(_:))
        modifierSwap.switchControl.tag = index
        modifierSwap.label.font = Typography.bodySecondary
        modifierSwap.toolTip = L10n.text("关闭普通映射拦截时，将此板载快捷键中的 ⌘ 与 Control 互换")
        modifierSwap.setContentHuggingPriority(.required, for: .horizontal)
        modifierSwap.isHidden = true
        modifierSwapViews[index] = modifierSwap
        titleRow.addArrangedSubview(modifierSwap)

        let intercept = ThemeToggleView(title: L10n.text("拦截板载键值"))
        intercept.switchControl.target = self
        intercept.switchControl.action = #selector(interceptToggled(_:))
        intercept.switchControl.tag = index
        intercept.toolTip = L10n.text("开启：拦截板载键值并执行 Mac 自定义键值；关闭：板载键值直接通过。设备未启用配置时始终直通")
        intercept.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        interceptToggles[index] = intercept.switchControl
        let interceptRow = NSStackView(views: [intercept, NSView()])
        interceptRow.orientation = .horizontal
        interceptRow.alignment = .centerY

        let desc = NSTextField(labelWithString: "")
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 2
        desc.textColor = DesignSystem.Colors.textPrimary
        desc.font = Typography.mappingValue
        descLabels[index] = desc

        let source = NSTextField(labelWithString: "")
        source.font = Typography.bodyNormal
        source.textColor = DesignSystem.Colors.textSecondary
        source.lineBreakMode = .byWordWrapping
        source.maximumNumberOfLines = 2
        sourceLabels[index] = source

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let edit = ThemeButton(title: L10n.text("编辑..."), target: self, action: #selector(editTapped(_:)))
        edit.image = UIStyle.symbol("pencil", size: 13, weight: .regular)
        edit.imagePosition = .imageLeading
        edit.toolTip = L10n.format("编辑按键 %d 的映射", index)
        edit.tag = index
        edit.buttonType = .primary
        editButtons[index] = edit

        let clear = ThemeButton(title: L10n.text("清除"), target: self, action: #selector(clearTapped(_:)))
        clear.image = UIStyle.symbol("trash", size: 13, weight: .regular)
        clear.imagePosition = .imageLeading
        clear.toolTip = L10n.format("清除按键 %d 的映射", index)
        clear.tag = index
        clear.buttonType = .normal
        clearButtons[index] = clear

        buttonRow.addArrangedSubview(edit)
        buttonRow.addArrangedSubview(clear)

        v.addArrangedSubview(titleRow)
        v.addArrangedSubview(desc)
        v.addArrangedSubview(source)
        v.addArrangedSubview(interceptRow)
        v.addArrangedSubview(buttonRow)

        card.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            v.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            v.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            v.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])

        return card
    }

    // MARK: - Editable section titles (per device)

    private static let sectionStoreKeys = ["side", "dpi", "scroll"]

    private func sectionDefaultTitle(_ tag: Int) -> String {
        [L10n.text("侧键 1–12"), L10n.text("DPI ±"), L10n.text("滚轮左右键")][tag]
    }

    private func setupEditableSection(_ section: ThemeSectionView, tag: Int) {
        section.makeTitleEditable(
            placeholder: sectionDefaultTitle(tag),
            tag: tag,
            tooltip: L10n.text("点击可自定义分组标题，清空恢复默认（标题属于设备）"),
            target: self,
            action: #selector(sectionTitleEdited(_:))
        )
        sectionViews[tag] = section
        refreshSectionTitles()
    }

    private func refreshSectionTitles() {
        for (tag, section) in sectionViews where !section.isTitleBeingEdited {
            section.titleText = resolvedSectionTitle(tag)
        }
    }

    private func resolvedSectionTitle(_ tag: Int) -> String {
        let id = Self.sectionStoreKeys[tag]
        guard let group = ConfigManager.shared.inputGroups(forDeviceKey: selectedDeviceKey)
            .first(where: { $0.id == id }) else { return sectionDefaultTitle(tag) }
        return ConfigManager.shared.inputGroupTitle(group)
    }

    @objc private func sectionTitleEdited(_ sender: NSTextField) {
        guard let deviceKey = selectedDeviceKey else { return }
        ConfigManager.shared.renameInputGroup(
            Self.sectionStoreKeys[sender.tag],
            title: sender.stringValue,
            forDeviceKey: deviceKey
        )
        sender.stringValue = resolvedSectionTitle(sender.tag)
    }

    @objc private func buttonNameEdited(_ sender: NSTextField) {
        guard let deviceKey = selectedDeviceKey else { return }
        ConfigManager.shared.setCustomName(sender.stringValue, forDeviceKey: deviceKey, index: sender.tag)
        scheduleRefresh()
    }

    private func displayName(for index: Int) -> String {
        ConfigManager.shared.buttonDisplayName(forDeviceKey: selectedDeviceKey, index: index)
    }

    // MARK: - Grid refresh

    /// Sync the custom-sources section to the selected device: build cards for
    /// its custom indices, tear down any that are gone, hide the section when
    /// there are none. Reuses the same responsive column count as the side keys.
    private func refreshCustomSources() {
        let groups = ConfigManager.shared.inputGroups(forDeviceKey: selectedDeviceKey)
        let indices = groups.flatMap(\.sourceIndices).filter { $0 >= 17 }
        // Drop cards for indices no longer present on this device.
        for old in shownCustomIndices where !indices.contains(old) && old >= 17 {
            rowViews[old]?.removeFromSuperview()
            rowViews[old] = nil
            titleLabels[old] = nil; descLabels[old] = nil
            sourceLabels[old] = nil; interceptToggles[old] = nil
            modifierSwapViews[old] = nil
            editButtons[old] = nil; clearButtons[old] = nil
        }
        for index in indices where rowViews[index] == nil {
            let card = makeCard(for: index)
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 142).isActive = true
            rowViews[index] = card
        }
        shownCustomIndices = indices
        let columns = currentColumns()
        for view in customGroupsStack.arrangedSubviews { view.removeFromSuperview() }
        customGroupSections.removeAll()
        customGroupGrids.removeAll()
        for group in groups {
            if group.isBuiltIn {
                let section: ThemeSectionView?
                switch group.id {
                case DeviceInputGroup.sideID: section = sideKeysSection
                case DeviceInputGroup.dpiID: section = dpiSection
                case DeviceInputGroup.scrollID: section = scrollSection
                default: section = nil
                }
                if let section { customGroupsStack.addArrangedSubview(section) }
                continue
            }
            guard !group.sourceIndices.isEmpty else { continue }
            let grid = NSStackView()
            grid.orientation = .vertical
            grid.spacing = 12
            grid.alignment = .centerX
            let section = ThemeSectionView(title: ConfigManager.shared.inputGroupTitle(group))
            section.contentStack.addArrangedSubview(grid)
            customGroupsStack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: customGroupsStack.widthAnchor).isActive = true
            customGroupSections[group.id] = section
            customGroupGrids[group.id] = grid
            let groupIndices = group.sourceIndices
            for chunkStart in stride(from: 0, to: groupIndices.count, by: columns) {
                let rowStack = NSStackView()
                rowStack.orientation = .horizontal
                rowStack.spacing = 12
                rowStack.distribution = .fillEqually
                let slice = groupIndices[chunkStart..<min(chunkStart + columns, groupIndices.count)]
                for index in slice { if let card = rowViews[index] { rowStack.addArrangedSubview(card) } }
                for _ in slice.count..<columns {
                    let filler = NSView(); filler.translatesAutoresizingMaskIntoConstraints = false
                    rowStack.addArrangedSubview(filler)
                }
                grid.addArrangedSubview(rowStack)
                rowStack.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
            }
        }
        customGroupsStack.isHidden = groups.allSatisfy(\.sourceIndices.isEmpty)
        // Force the equalizer to re-run for the changed custom set.
        lastLayoutSignature = ""
    }

    private func refreshRows() {
        refreshContextHeader()
        refreshSectionTitles()
        refreshCustomSources()
        rebuildGrid()

        let displayProfile = displayedProfileName()
        let displayMapping = displayProfile.map { ConfigManager.shared.mappingForProfile(named: $0) } ?? [:]
        let activeProfile = activeProfileName()
        let activeMapping = activeProfile.map { ConfigManager.shared.mappingForProfile(named: $0) } ?? [:]
        let viewingActive = displayProfile != nil && displayProfile == activeProfile
        let hardware = selectedDeviceKey.map { ConfigManager.shared.hardwareMapping(forConfigKey: $0) } ?? [:]
        let usableSources = ConfigManager.shared.usableRuntimeSourceIndices()
        let runtimeActive = InputCoordinator.shared.state == .active

        for i in Array(InputSourceCatalog.supportedIndices) + shownCustomIndices {
            let routeIndex = ConfigManager.shared.signalCanonicalSourceIndex(
                forDeviceKey: selectedDeviceKey,
                index: i
            )
            if let field = titleLabels[i], field.currentEditor() == nil {
                field.stringValue = displayName(for: i)
            }
            descLabels[i]?.stringValue = actionDescription(displayMapping[routeIndex])
            let canEditAction = displayProfile != nil
            editButtons[i]?.isEnabled = canEditAction
            clearButtons[i]?.isEnabled = canEditAction && displayMapping[routeIndex] != nil
            if !canEditAction {
                editButtons[i]?.toolTip = L10n.text("请先为此设备添加或挂载配置")
                clearButtons[i]?.toolTip = L10n.text("请先为此设备添加或挂载配置")
            } else {
                editButtons[i]?.toolTip = L10n.format("编辑按键 %d 的映射", i)
                clearButtons[i]?.toolTip = L10n.format("清除按键 %d 的映射", i)
            }
            if let key = hardware[String(i)] {
                let intercepted = key.isIntercepted
                if let swapView = modifierSwapViews[i] {
                    swapView.isHidden = !key.hasCommandOrControlModifier
                    swapView.state = key.isCommandControlSwapEnabled ? .on : .off
                    swapView.isEnabled = key.hasCommandOrControlModifier
                    swapView.toolTip = intercepted
                        ? L10n.text("普通映射拦截已开启，当前由 Mac 动作接管；关闭拦截后互换生效")
                        : L10n.text("将此板载快捷键中的 ⌘ 与 Control 互换")
                }
                let activeHasValue = activeMapping[routeIndex] != nil
                // Status line reports runtime truth — what the device's
                // ACTIVE profile makes this key do right now.
                let runtimeEffective = intercepted && activeHasValue && runtimeActive && usableSources.contains(i)
                let runtimeTransforming = key.usesCommandControlTransform
                    && runtimeActive
                    && usableSources.contains(i)
                // Interception is device-level and no longer needs a Mac custom
                // value: without one it blocks (suppresses) the onboard key.
                interceptToggles[i]?.state = intercepted ? .on : .off
                interceptToggles[i]?.isEnabled = true
                descLabels[i]?.textColor = viewingActive
                    ? (runtimeEffective ? DesignSystem.Colors.accentText : DesignSystem.Colors.textDisabled)
                    : (displayMapping[routeIndex] != nil ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textDisabled)
                let runtimeIntercepting = intercepted && runtimeActive && usableSources.contains(i)
                if runtimeTransforming {
                    sourceLabels[i]?.stringValue = L10n.format("板载键值：%@ · ⌘/Control 已互换", key.displayString)
                } else if activeProfile == nil {
                    sourceLabels[i]?.stringValue = L10n.format("板载键值：%@ · 板载键值直通", key.displayString)
                } else if intercepted && activeHasValue {
                    sourceLabels[i]?.stringValue = runtimeIntercepting
                        ? L10n.format("板载键值：%@ · 已拦截", key.displayString)
                        : L10n.format("板载键值：%@ · 等待运行条件", key.displayString)
                } else if intercepted {
                    // Only claim the key is blocked when the runtime is actually
                    // intercepting it; otherwise it still passes through.
                    sourceLabels[i]?.stringValue = runtimeIntercepting
                        ? L10n.format("板载键值：%@ · 已屏蔽（无动作）", key.displayString)
                        : L10n.format("板载键值：%@ · 等待运行条件", key.displayString)
                } else {
                    sourceLabels[i]?.stringValue = L10n.format("板载键值：%@ · 板载键值直通", key.displayString)
                }
                if routeIndex != i, let current = sourceLabels[i]?.stringValue {
                    sourceLabels[i]?.stringValue = current + L10n.format(" · 与%@共享映射", displayName(for: routeIndex))
                }
                sourceLabels[i]?.textColor = runtimeTransforming
                    ? DesignSystem.Colors.textSecondary
                    : activeProfile == nil
                    ? DesignSystem.Colors.textSecondary
                    : runtimeEffective
                    ? DesignSystem.Colors.textSecondary
                    : (intercepted || activeHasValue ? DesignSystem.Colors.textTertiary : UIStyle.warningColor)
            } else {
                modifierSwapViews[i]?.isHidden = true
                interceptToggles[i]?.state = .off
                interceptToggles[i]?.isEnabled = false
                descLabels[i]?.textColor = displayMapping[routeIndex] != nil
                    ? DesignSystem.Colors.textPrimary
                    : DesignSystem.Colors.textDisabled
                sourceLabels[i]?.stringValue = L10n.text("板载键值：尚未录入 — 点击这里读取")
                sourceLabels[i]?.textColor = DesignSystem.Colors.textTertiary
                if let label = sourceLabels[i], label.gestureRecognizers.isEmpty {
                    let click = NSClickGestureRecognizer(target: self, action: #selector(hardwareDefinitionTapped))
                    label.addGestureRecognizer(click)
                }
            }
        }
        reloadCompactProfilePopup()
    }

    private func actionDescription(_ action: ActionType?) -> String {
        guard let action = action else { return L10n.text("(未分配)") }
        switch action {
        case .keySequence(let keys, let d):
            let ks = keys.map { $0.formattedShortcut() }.joined(separator: ", ")
            return d ?? L10n.format("按键序列: %@", ks)
        case .application(let path, let d):
            return d ?? L10n.format("打开应用: %@", path)
        case .systemCommand(let cmd, let d):
            return d ?? L10n.format("命令: %@", cmd)
        case .textSnippet(let text, let d):
            let preview = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            let truncated = preview.count > 40 ? String(preview.prefix(37)) + "…" : preview
            return d ?? L10n.format("输入文本: %@", truncated)
        case .macro(_, let d):
            return d ?? L10n.text("宏")
        case .profileSwitch(let p, let d):
            return d ?? L10n.format("切换此设备配置: %@", p)
        case .mouseClick(let btn, let d):
            if let d = d, !d.isEmpty { return d }
            switch btn {
            case 0: return L10n.text("左键点击")
            case 1: return L10n.text("右键点击")
            case 2: return L10n.text("中键点击")
            case 3: return L10n.text("前进")
            case 4: return L10n.text("后退")
            default: return L10n.format("鼠标按键 %d", btn)
            }
        case .systemAction(let identifier, let d):
            return d ?? SystemActionDefinition.definition(for: identifier)?.name ?? L10n.text("系统动作")
        case .openTarget(let target, let d):
            return d ?? L10n.format("打开: %@", target)
        case .scrollControl(let role, let d):
            return d ?? role.displayName
        }
    }

    // MARK: - Card actions

    @objc private func editTapped(_ sender: NSButton) {
        guard let profile = displayedProfileName() else { return }
        let idx = ConfigManager.shared.signalCanonicalSourceIndex(
            forDeviceKey: selectedDeviceKey,
            index: sender.tag
        )
        let editor = ActionEditorViewController(
            buttonIndex: idx,
            profileName: profile,
            deviceKey: selectedDeviceKey
        ) { [weak self] action in
            if let action = action {
                ConfigManager.shared.setAction(forButton: idx, action: action, inProfile: profile)
                ConfigManager.shared.saveUserProfiles()
            }
            self?.scheduleRefresh()
        }
        presentAsSheet(editor)
    }

    @objc private func clearTapped(_ sender: NSButton) {
        guard let profile = displayedProfileName() else { return }
        let index = ConfigManager.shared.signalCanonicalSourceIndex(
            forDeviceKey: selectedDeviceKey,
            index: sender.tag
        )
        ConfigManager.shared.setAction(forButton: index, action: nil, inProfile: profile)
        ConfigManager.shared.saveUserProfiles()
        scheduleRefresh()
    }

    @objc private func hardwareDefinitionTapped() {
        let controller = HardwareDefinitionViewController()
        controller.onComplete = { [weak self] in self?.scheduleRefresh() }
        presentAsSheet(controller)
    }

    @objc private func tutorialTapped() {
        TutorialWindowController.shared.show()
    }

    @objc private func interceptToggled(_ sender: NSSwitch) {
        // Interception is device-level and no longer requires a Mac custom
        // value — without one it simply blocks the onboard key.
        guard let deviceKey = selectedDeviceKey,
              ConfigManager.shared.hardwareMapping(forConfigKey: ConfigManager.shared.configKey(forDeviceKey: deviceKey))[String(sender.tag)] != nil else {
            scheduleRefresh()
            return
        }
        ConfigManager.shared.setSignalInterceptEnabled(
            sender.state == .on,
            forDeviceKey: deviceKey,
            index: sender.tag
        )
        scheduleRefresh()
    }

    @objc private func modifierSwapToggled(_ sender: NSSwitch) {
        guard let deviceKey = selectedDeviceKey,
              let key = ConfigManager.shared
                .hardwareMapping(forConfigKey: ConfigManager.shared.configKey(forDeviceKey: deviceKey))[String(sender.tag)],
              key.hasCommandOrControlModifier else {
            scheduleRefresh()
            return
        }
        ConfigManager.shared.setSignalCommandControlSwapEnabled(
            sender.state == .on,
            forDeviceKey: deviceKey,
            index: sender.tag
        )
        scheduleRefresh()
    }

    @objc private func activateSelectedProfileTapped() {
        guard let deviceKey = selectedDeviceKey, let profile = selectedProfileName else { return }
        ConfigManager.shared.setActiveProfile(profile, forDeviceKey: deviceKey)
        scheduleRefresh()
    }

    @objc private func renameDeviceTapped() {
        guard let deviceKey = selectedDeviceKey else { return }
        let current = ConfigManager.shared.deviceBaseName(forKey: deviceKey)
        guard let name = promptForText(
            title: L10n.text("重命名设备"),
            message: L10n.text("输入此设备的自定义名称（清空则恢复原始名称）："),
            defaultValue: current
        ) else { return }
        // The original product name is never overwritten — the rename lives
        // in customDisplayName and clearing it restores the original.
        ConfigManager.shared.setCustomDeviceName(name, forDeviceKey: deviceKey)
        scheduleRefresh()
    }

    /// Inline commit from the editable context title — renames the profile in
    /// profile context, or the device in device context.
    @objc private func deviceNameEdited(_ sender: NSTextField) {
        guard let target = contextEditTarget
            ?? selectedDeviceKey.map({ ContextEditTarget(deviceKey: $0, profileName: selectedProfileName) }) else { return }
        contextEditTarget = nil
        if let profile = target.profileName {
            let newName = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if newName == profile {
                scheduleRefresh()
            } else if !newName.isEmpty, ConfigManager.shared.renameProfile(from: profile, to: newName) {
                if selectedDeviceKey == target.deviceKey, selectedProfileName == profile {
                    selectedProfileName = newName
                }
                ConfigManager.shared.saveUserProfiles()
            } else {
                NSSound.beep()
                showInfo(L10n.text("无法重命名。新名称可能无效或已存在。"))
                scheduleRefresh()
            }
            return
        }
        ConfigManager.shared.setCustomDeviceName(sender.stringValue, forDeviceKey: target.deviceKey)
    }

    @objc private func deviceDetailsTapped(_ sender: NSButton) {
        guard let deviceKey = selectedDeviceKey else { return }
        detailsPopover?.close()
        let facts = ConfigManager.shared.deviceIdentityFacts(forKey: deviceKey)
        let grid = NSGridView(views: facts.map { fact in
            let key = NSTextField(labelWithString: fact.label)
            key.font = Typography.bodySecondary
            key.textColor = DesignSystem.Colors.textSecondary
            let value = NSTextField(labelWithString: fact.value)
            value.font = Typography.bodyNormal
            value.isSelectable = true
            value.lineBreakMode = .byCharWrapping
            value.maximumNumberOfLines = 3
            value.preferredMaxLayoutWidth = 250
            return [key, value]
        })
        grid.columnSpacing = 14
        grid.rowSpacing = 7
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        let editRule = ThemeButton(
            title: L10n.text("身份识别规则..."),
            target: self,
            action: #selector(editIdentityRuleTapped(_:))
        )
        let stack = NSStackView(views: [grid, editRule])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 12
        let content = NSView()
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        let controller = NSViewController()
        controller.view = content
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        detailsPopover = popover
    }

    @objc private func editIdentityRuleTapped(_ sender: NSButton) {
        guard let deviceKey = selectedDeviceKey else { return }
        detailsPopover?.close()
        let editor = DeviceIdentityRuleViewController(deviceKey: deviceKey)
        editor.onSaved = { [weak self] in self?.scheduleRefresh() }
        presentAsSheet(editor)
    }

    @objc private func copyMappingSelected(_ sender: NSPopUpButton) {
        guard let deviceKey = selectedDeviceKey,
              let source = sender.selectedItem?.representedObject as? String else { return }
        ConfigManager.shared.copyHardwareMapping(fromConfigKey: source, toDeviceKey: deviceKey)
        scheduleRefresh()
    }

    // MARK: - Profile management (sidebar context menu + add row)

    private func promptNewProfile(underDeviceKey deviceKey: String, basedOn base: String?) {
        let title = base == nil ? L10n.text("新建配置文件") : L10n.text("复制配置文件")
        let defaultValue = base.map { L10n.format("%@ 副本", $0) } ?? ""
        guard let name = promptForText(title: title, message: L10n.text("输入配置文件的名称："), defaultValue: defaultValue),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let created = ConfigManager.shared.createProfile(name: name, underDeviceKey: deviceKey, basedOn: base) {
            selectedDeviceKey = deviceKey
            selectedProfileName = created
            scheduleRefresh()
        } else {
            showInfo(L10n.text("无法创建配置文件。名称可能为空。"))
        }
    }

    private func showAddProfileMenu(for deviceKey: String, at row: Int) {
        let menu = NSMenu()
        let newItem = NSMenuItem(title: L10n.text("新建空白配置..."), action: #selector(addProfileMenuNew(_:)), keyEquivalent: "")
        newItem.target = self
        newItem.representedObject = deviceKey
        menu.addItem(newItem)
        if let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey) {
            let duplicateItem = NSMenuItem(title: L10n.format("复制「%@」...", active), action: #selector(addProfileMenuDuplicate(_:)), keyEquivalent: "")
            duplicateItem.target = self
            duplicateItem.representedObject = deviceKey
            menu.addItem(duplicateItem)
        }
        // Sharing pulls in a profile another device already owns.
        let mounted = Set(ConfigManager.shared.profileNames(forDeviceKey: deviceKey))
        let candidates = ConfigManager.shared.availableProfiles().filter { !mounted.contains($0) }
        if !candidates.isEmpty {
            let shareRoot = NSMenuItem(title: L10n.text("共用现有配置"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for name in candidates {
                let users = ConfigManager.shared.deviceKeysUsing(profile: name)
                    .map { ConfigManager.shared.deviceDisplayName(forKey: $0) }
                let title = users.isEmpty
                    ? name
                    : L10n.format("%@（来自 %@）", name, users.joined(separator: "、"))
                let item = NSMenuItem(title: title, action: #selector(addProfileMenuShare(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [deviceKey, name]
                submenu.addItem(item)
            }
            shareRoot.submenu = submenu
            menu.addItem(shareRoot)
        }
        let rowRect = outlineView.rect(ofRow: row)
        menu.popUp(positioning: nil, at: NSPoint(x: rowRect.minX + 16, y: rowRect.maxY), in: outlineView)
    }

    @objc private func addProfileMenuNew(_ sender: NSMenuItem) {
        guard let deviceKey = sender.representedObject as? String else { return }
        promptNewProfile(underDeviceKey: deviceKey, basedOn: nil)
    }

    @objc private func addProfileMenuDuplicate(_ sender: NSMenuItem) {
        guard let deviceKey = sender.representedObject as? String else { return }
        promptNewProfile(underDeviceKey: deviceKey, basedOn: ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey))
    }

    @objc private func addProfileMenuShare(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        ConfigManager.shared.shareProfile(payload[1], withDeviceKey: payload[0], activate: false)
        selectedDeviceKey = payload[0]
        selectedProfileName = payload[1]
        scheduleRefresh()
    }

    @objc private func importProfilesTapped() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.canChooseFiles = true
        p.allowedContentTypes = [.json]
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                // Warn before overwriting profiles that already exist, so an
                // import can't silently replace the one in use.
                let conflicts = try ConfigManager.shared.conflictingProfileNames(in: url)
                if !conflicts.isEmpty {
                    let ok = self.confirmImport(
                        L10n.text("导入将覆盖同名配置"),
                        message: L10n.format("以下配置已存在，导入会覆盖它们：%@。是否继续？", conflicts.joined(separator: "、"))
                    )
                    guard ok else { return }
                }
                try ConfigManager.shared.importProfiles(from: url, merge: true)
                ConfigManager.shared.saveUserProfiles()
                self.scheduleRefresh()
            } catch {
                self.showInfo(L10n.format("导入失败: %@", error.localizedDescription))
            }
        }
    }

    private func confirmImport(_ title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("覆盖导入"))
        alert.addButton(withTitle: L10n.text("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func exportAllProfilesTapped() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "V-Mouse鼠标映射-profiles.json"
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                try ConfigManager.shared.exportAllProfiles(to: url)
            } catch {
                self.showInfo(L10n.format("导出失败: %@", error.localizedDescription))
            }
        }
    }

    // MARK: - Context-menu actions (profile rows)

    @objc private func menuActivateProfile(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        ConfigManager.shared.setActiveProfile(payload[1], forDeviceKey: payload[0])
        scheduleRefresh()
    }

    @objc private func menuRenameProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        guard let newName = promptForText(title: L10n.text("重命名配置文件"), message: L10n.format("输入配置文件 ‘%@’ 的新名称:", name), defaultValue: name) else { return }
        if ConfigManager.shared.renameProfile(from: name, to: newName) {
            if selectedProfileName == name { selectedProfileName = newName.trimmingCharacters(in: .whitespacesAndNewlines) }
            ConfigManager.shared.saveUserProfiles()
            scheduleRefresh()
        } else {
            showInfo(L10n.text("无法重命名。新名称可能无效或已存在。"))
        }
    }

    @objc private func menuDuplicateProfile(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        promptNewProfile(underDeviceKey: payload[0], basedOn: payload[1])
    }

    @objc private func menuExportProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "\(name).json"
        p.beginSheetModal(for: view.window!) { resp in
            guard resp == .OK, let url = p.url else { return }
            do {
                try ConfigManager.shared.exportProfile(named: name, to: url)
            } catch {
                self.showInfo(L10n.format("导出失败: %@", error.localizedDescription))
            }
        }
    }

    @objc private func menuShareProfile(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        ConfigManager.shared.shareProfile(payload[1], withDeviceKey: payload[0], activate: false)
        scheduleRefresh()
    }

    @objc private func menuUnmountProfile(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        ConfigManager.shared.removeProfile(payload[1], fromDeviceKey: payload[0])
        if selectedProfileName == payload[1] { selectedProfileName = nil }
        scheduleRefresh()
    }

    @objc private func menuDeleteProfile(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let users = ConfigManager.shared.deviceKeysUsing(profile: name)
            .map { ConfigManager.shared.deviceDisplayName(forKey: $0) }
        let message = users.isEmpty
            ? L10n.format("确定要删除 ‘%@’ 吗？此操作无法撤销。", name)
            : L10n.format("‘%@’ 正被以下设备使用：%@。删除后，有其他配置的设备会切换配置；没有其他配置的设备将变为未启用配置。此操作无法撤销。", name, users.joined(separator: "、"))
        guard confirm(L10n.text("删除配置文件"), message: message) else { return }
        if ConfigManager.shared.deleteProfile(named: name) {
            if selectedProfileName == name { selectedProfileName = nil }
            ConfigManager.shared.saveUserProfiles()
            scheduleRefresh()
        } else {
            showInfo(L10n.text("无法删除配置文件 (它可能是最后一个配置文件)。"))
        }
    }

    @objc private func menuMountUnmounted(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? [String], payload.count == 2 else { return }
        ConfigManager.shared.shareProfile(payload[1], withDeviceKey: payload[0], activate: false)
        scheduleRefresh()
    }

    // MARK: - UI helpers

    private func promptForText(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        let tf = NSTextField(string: defaultValue)
        tf.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = tf
        alert.addButton(withTitle: L10n.text("确定"))
        alert.addButton(withTitle: L10n.text("取消"))
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return nil }
        return tf.stringValue
    }

    private func confirm(_ title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("删除"))
        alert.addButton(withTitle: L10n.text("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showInfo(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.text("信息")
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.text("确定"))
        alert.runModal()
    }
}

// MARK: - Context title editing

extension MappingViewController: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === contextTitleLabel,
              let deviceKey = selectedDeviceKey else { return }
        contextEditTarget = ContextEditTarget(deviceKey: deviceKey, profileName: selectedProfileName)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === contextTitleLabel else { return }
        // The field's action performs the commit. Clear a stale target if AppKit
        // ended editing without dispatching that action for any reason.
        DispatchQueue.main.async { [weak self] in
            if self?.contextTitleLabel.currentEditor() == nil {
                self?.contextEditTarget = nil
            }
        }
    }
}

// MARK: - NSOutlineViewDataSource

extension MappingViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return sidebarRoots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else { return sidebarRoots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return !node.children.isEmpty
    }
}

// MARK: - NSOutlineViewDelegate

extension MappingViewController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        return isGroupKind(node.kind)
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? SidebarNode else { return false }
        switch node.kind {
        case .device, .profile, .addProfile: return true
        // Unmounted profiles have no editing context on the right; selecting
        // one would highlight a row while the grid keeps the old content.
        // They stay reachable via their right-click menu (mount/export/delete).
        case .unmountedProfile, .devicesGroup, .archivedGroup, .unmountedGroup: return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        let cell = NSTableCellView()

        func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
            let l = NSTextField(labelWithString: text)
            l.font = font
            l.textColor = color
            l.lineBreakMode = .byTruncatingTail
            return l
        }

        var views: [NSView] = []
        switch node.kind {
        case .devicesGroup:
            views = [label(L10n.text("设备"), font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: DesignSystem.Colors.textTertiary)]
        case .archivedGroup:
            views = [label(L10n.text("已归档"), font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: DesignSystem.Colors.textTertiary)]
        case .unmountedGroup:
            views = [label(L10n.text("未挂载配置"), font: NSFont.systemFont(ofSize: 11, weight: .semibold), color: DesignSystem.Colors.textTertiary)]
        case .device(let deviceKey):
            let hasTable = !ConfigManager.shared.hardwareMapping(forConfigKey: deviceKey).isEmpty
            let icon = NSImageView(image: UIStyle.symbol("computermouse", size: 15, weight: .medium) ?? NSImage())
            // Un-learned devices get a yellow mouse so an unconfigured device
            // is obvious at a glance in the list.
            icon.contentTintColor = hasTable ? DesignSystem.Colors.textPrimary : UIStyle.warningColor
            // Line 1: base name (no transport suffix). Line 2: connection —
            // the transport is still part of the full name elsewhere, only
            // shown on its own line here for a calmer two-line layout.
            let baseName = label(ConfigManager.shared.deviceBaseName(forKey: deviceKey), font: NSFont.systemFont(ofSize: 13, weight: .semibold), color: DesignSystem.Colors.textPrimary)
            let nameRow = NSStackView(views: [icon, baseName])
            nameRow.orientation = .horizontal
            nameRow.spacing = 5
            var line2 = ConfigManager.shared.deviceTransportDisplayLabel(forKey: deviceKey) ?? ""
            if !hasTable {
                line2 = line2.isEmpty ? L10n.text("⚠ 板载键值未录入") : "\(line2) · " + L10n.text("⚠ 板载键值未录入")
            } else {
                let status = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey)
                    .map { L10n.format("启用：%@", $0) } ?? L10n.text("未启用配置")
                line2 = line2.isEmpty ? status : "\(line2) · \(status)"
            }
            let subtitle = label(line2, font: NSFont.systemFont(ofSize: 11), color: hasTable ? DesignSystem.Colors.textSecondary : UIStyle.warningColor)
            let v = NSStackView(views: [nameRow, subtitle])
            v.orientation = .vertical
            v.alignment = .leading
            v.spacing = 2
            views = [v]
        case .profile(let deviceKey, let name):
            let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey) == name
            let marker = label(active ? "●" : "○", font: NSFont.systemFont(ofSize: 9), color: active ? DesignSystem.Colors.accentText : DesignSystem.Colors.textTertiary)
            let title = label(name, font: NSFont.systemFont(ofSize: 13, weight: active ? .medium : .regular), color: active ? DesignSystem.Colors.accentText : DesignSystem.Colors.textPrimary)
            var rowItems: [NSView] = [marker, title]
            if ConfigManager.shared.deviceKeysUsing(profile: name).count > 1 {
                let shared = label("⇄", font: NSFont.systemFont(ofSize: 11), color: DesignSystem.Colors.textTertiary)
                shared.toolTip = L10n.text("此配置被多台设备共用，修改会同步到所有设备")
                rowItems.append(shared)
            }
            let stack = NSStackView(views: rowItems)
            stack.orientation = .horizontal
            stack.spacing = 6
            stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 12)
            // A soft rounded background makes each profile read as its own
            // chip and spaces the list out visually.
            let chip = NSView()
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 7
            chip.layer?.backgroundColor = (active
                ? DesignSystem.Colors.accentText.withAlphaComponent(0.12)
                : DesignSystem.Colors.textPrimary.withAlphaComponent(0.05)).cgColor
            stack.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor),
                stack.topAnchor.constraint(equalTo: chip.topAnchor),
                stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor)
            ])
            views = [chip]
        case .addProfile:
            views = [label(L10n.text("+ 添加配置"), font: NSFont.systemFont(ofSize: 12), color: DesignSystem.Colors.accentText)]
        case .unmountedProfile(let name):
            views = [label(name, font: NSFont.systemFont(ofSize: 13), color: DesignSystem.Colors.textSecondary)]
        }

        guard let content = views.first else { return cell }
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            content.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            content.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? SidebarNode else { return 26 }
        switch node.kind {
        case .device: return 40
        case .profile: return 30
        case .devicesGroup, .archivedGroup, .unmountedGroup: return 22
        default: return 26
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingSidebar else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }
        switch node.kind {
        case .device(let deviceKey):
            selectedDeviceKey = deviceKey
            selectedProfileName = nil
            ConfigManager.shared.setEditingDevice(key: deviceKey)
            refreshRows()
        case .profile(let deviceKey, let name):
            selectedDeviceKey = deviceKey
            selectedProfileName = name
            ConfigManager.shared.setEditingDevice(key: deviceKey)
            refreshRows()
        case .addProfile(let deviceKey):
            // Not a real destination: pop the creation menu and restore the
            // previous selection.
            isReloadingSidebar = true
            restoreSidebarSelection()
            isReloadingSidebar = false
            showAddProfileMenu(for: deviceKey, at: row)
        case .unmountedProfile:
            break
        case .devicesGroup, .archivedGroup, .unmountedGroup:
            break
        }
    }
}

// MARK: - Sidebar context menu

extension MappingViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? SidebarNode else { return }

        func add(_ title: String, _ action: Selector, _ payload: Any?, red: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = payload
            if red { item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed]) }
            menu.addItem(item)
        }

        switch node.kind {
        case .device(let deviceKey):
            selectedDeviceKey = deviceKey
            add(L10n.text("读取板载键值..."), #selector(menuReadHardware(_:)), deviceKey)
            add(L10n.text("重命名设备..."), #selector(menuRenameDevice(_:)), deviceKey)
            menu.addItem(.separator())
            if ConfigManager.shared.isDeviceArchived(deviceKey) {
                add(L10n.text("取消归档"), #selector(menuUnarchiveDevice(_:)), deviceKey)
            } else {
                add(L10n.text("归档设备"), #selector(menuArchiveDevice(_:)), deviceKey)
            }
        case .profile(let deviceKey, let name):
            let active = ConfigManager.shared.effectiveProfileName(forDeviceKey: deviceKey) == name
            if !active {
                add(L10n.text("在此设备启用"), #selector(menuActivateProfile(_:)), [deviceKey, name])
                menu.addItem(.separator())
            }
            add(L10n.text("重命名..."), #selector(menuRenameProfile(_:)), name)
            add(L10n.text("复制..."), #selector(menuDuplicateProfile(_:)), [deviceKey, name])
            add(L10n.text("导出..."), #selector(menuExportProfile(_:)), name)
            let others = knownDeviceKeys().filter { key in
                key != deviceKey && !ConfigManager.shared.profileNames(forDeviceKey: key).contains(name)
            }
            if !others.isEmpty {
                let shareRoot = NSMenuItem(title: L10n.text("共用给其他设备"), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for key in others {
                    let item = NSMenuItem(title: ConfigManager.shared.deviceDisplayName(forKey: key), action: #selector(menuShareProfile(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = [key, name]
                    submenu.addItem(item)
                }
                shareRoot.submenu = submenu
                menu.addItem(shareRoot)
            }
            menu.addItem(.separator())
            add(L10n.text("从此设备移除"), #selector(menuUnmountProfile(_:)), [deviceKey, name])
            add(L10n.text("删除..."), #selector(menuDeleteProfile(_:)), name, red: true)
        case .unmountedProfile(let name):
            let devices = knownDeviceKeys()
            if !devices.isEmpty {
                let mountRoot = NSMenuItem(title: L10n.text("挂载到设备"), action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for key in devices {
                    let item = NSMenuItem(title: ConfigManager.shared.deviceDisplayName(forKey: key), action: #selector(menuMountUnmounted(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = [key, name]
                    submenu.addItem(item)
                }
                mountRoot.submenu = submenu
                menu.addItem(mountRoot)
            }
            add(L10n.text("导出..."), #selector(menuExportProfile(_:)), name)
            add(L10n.text("删除..."), #selector(menuDeleteProfile(_:)), name, red: true)
        default:
            break
        }
    }

    @objc private func menuArchiveDevice(_ sender: NSMenuItem) {
        guard let deviceKey = sender.representedObject as? String else { return }
        ConfigManager.shared.setDeviceArchived(true, forDeviceKey: deviceKey)
        // Move selection off the now-archived device so the grid follows an
        // active one.
        if selectedDeviceKey == deviceKey {
            selectedDeviceKey = nil
            selectedProfileName = nil
        }
        scheduleRefresh()
    }

    @objc private func menuUnarchiveDevice(_ sender: NSMenuItem) {
        guard let deviceKey = sender.representedObject as? String else { return }
        ConfigManager.shared.setDeviceArchived(false, forDeviceKey: deviceKey)
        scheduleRefresh()
    }

    @objc private func menuReadHardware(_ sender: NSMenuItem) {
        if let deviceKey = sender.representedObject as? String {
            selectedDeviceKey = deviceKey
            selectedProfileName = nil
            ConfigManager.shared.setEditingDevice(key: deviceKey)
        }
        hardwareDefinitionTapped()
    }

    @objc private func menuRenameDevice(_ sender: NSMenuItem) {
        if let deviceKey = sender.representedObject as? String {
            selectedDeviceKey = deviceKey
        }
        renameDeviceTapped()
    }
}
