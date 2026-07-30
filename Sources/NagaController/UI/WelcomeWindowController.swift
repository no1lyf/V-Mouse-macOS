import Cocoa

final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    var onComplete: (() -> Void)?
    private var didFinish = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.delegate = self

        let content = NSView()
        
        let background = UIStyle.makeBackground(material: .popover)
        background.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(background)
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 20, bottom: 30, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        let productName = NSTextField(labelWithString: AppIdentity.productName)
        productName.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        productName.alignment = .center

        let tagline = NSTextField(labelWithString: AppIdentity.chineseTagline)
        tagline.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        tagline.textColor = .secondaryLabelColor
        tagline.alignment = .center

        // Use system language for the first button
        let systemLangCode = Locale.preferredLanguages.first ?? "en"
        let systemLangName = Locale.current.localizedString(forLanguageCode: systemLangCode) ?? systemLangCode
        
        var systemButtonText = "Use System Default Language (\(systemLangName))"
        if systemLangCode.hasPrefix("zh") {
            systemButtonText = "使用系统当前语言 \(systemLangName)"
        } else if systemLangCode.hasPrefix("ja") {
            systemButtonText = "システムの現在の言語を使用する \(systemLangName)"
        } else if systemLangCode.hasPrefix("ko") {
            systemButtonText = "시스템 현재 언어 사용 \(systemLangName)"
        } else if systemLangCode.hasPrefix("de") {
            systemButtonText = "Systemsprache verwenden \(systemLangName)"
        }
        
        let sysBtn = NSButton(title: systemButtonText, target: self, action: #selector(systemLanguageSelected))
        UIStyle.stylePrimaryButton(sysBtn)
        
        let separator = NSBox()
        separator.boxType = .separator
        
        let zhBtn = NSButton(title: "欢迎您！使用中文显示", target: self, action: #selector(zhSelected))
        let enBtn = NSButton(title: "Welcome! Display in English", target: self, action: #selector(enSelected))
        let jaBtn = NSButton(title: "ようこそ！日本語で表示", target: self, action: #selector(jaSelected))
        let koBtn = NSButton(title: "환영합니다! 한국어로 표시", target: self, action: #selector(koSelected))
        let deBtn = NSButton(title: "Willkommen! Auf Deutsch anzeigen", target: self, action: #selector(deSelected))
        
        let buttons = [zhBtn, enBtn, jaBtn, koBtn, deBtn]
        for b in buttons {
            UIStyle.styleSecondaryButton(b)
        }
        
        stack.addArrangedSubview(productName)
        stack.addArrangedSubview(tagline)
        stack.setCustomSpacing(22, after: tagline)
        stack.addArrangedSubview(sysBtn)
        stack.addArrangedSubview(separator)
        for b in buttons {
            stack.addArrangedSubview(b)
        }
        
        // Make all buttons the same width
        sysBtn.widthAnchor.constraint(equalToConstant: 300).isActive = true
        sysBtn.heightAnchor.constraint(equalToConstant: 30).isActive = true
        for b in buttons {
            b.widthAnchor.constraint(equalTo: sysBtn.widthAnchor).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        
        content.addSubview(stack)
        
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            background.topAnchor.constraint(equalTo: content.topAnchor),
            background.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        
        window.contentView = content
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Menu-bar apps run as .accessory, whose windows cannot become key.
    /// Temporarily switch to .regular so the picker gets focus, and restore
    /// the previous policy once a language is chosen.
    func show() {
        ActivationPolicyCoordinator.shared.acquire(for: self)
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func systemLanguageSelected() {
        let systemLangCode = Locale.preferredLanguages.first ?? "en"
        let mappedLang = AppLanguage.allCases.first { lang in
            systemLangCode.lowercased().hasPrefix(lang.rawValue.lowercased())
        } ?? .english
        L10n.setLanguage(mappedLang)
        finish()
    }
    
    @objc private func zhSelected() { select(.chineseSimplified) }
    @objc private func enSelected() { select(.english) }
    @objc private func jaSelected() { select(.japanese) }
    @objc private func koSelected() { select(.korean) }
    @objc private func deSelected() { select(.german) }
    
    private func select(_ lang: AppLanguage) {
        L10n.setLanguage(lang)
        finish()
    }
    
    private func finish() {
        cleanup()
        self.close()
    }

    /// Restore the activation policy and fire onComplete exactly once, whether
    /// the user picked a language or dismissed the window with the red button.
    private func cleanup() {
        guard !didFinish else { return }
        didFinish = true
        ActivationPolicyCoordinator.shared.release(for: self)
        onComplete?()
    }

    func windowWillClose(_ notification: Notification) {
        cleanup()
    }
}
