import Cocoa

final class TutorialWindowController: ThemedWindowController {
    static let shared = TutorialWindowController()

    private init() {
        let window = NSWindow(contentViewController: TutorialViewController())
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = "\(AppIdentity.productName) — \(L10n.text("帮助中心"))"
        window.setContentSize(NSSize(width: 820, height: 700))
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setFrameAutosaveName("NagaController.HelpCenterWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func makeContentViewController() -> NSViewController {
        let selectedTopicID = (window?.contentViewController as? TutorialViewController)?.selectedTopicID
        return TutorialViewController(initialTopicID: selectedTopicID)
    }
    override func makeTitle() -> String { "\(AppIdentity.productName) — \(L10n.text("帮助中心"))" }
}

private enum HelpAction: Equatable {
    case accessibility
    case inputMonitoring
    case mapping
    case scroll
}

private struct HelpTopic {
    let id: String
    let title: String
    let symbol: String
    let intro: String
    let bullets: [String]
    let note: String?
    let actions: [HelpAction]
}

private struct HelpCopy {
    let subtitle: String
    let statusTitle: String
    let granted: String
    let missing: String
    let connected: String
    let disconnected: String
    let running: String
    let stopped: String
    let actionTitles: [String]
    let topics: [HelpTopic]

    static func current() -> HelpCopy {
        switch L10n.language {
        case .chineseSimplified: return chinese
        case .english: return english
        case .japanese: return japanese
        case .korean: return korean
        case .german: return german
        }
    }

    private static let chinese = HelpCopy(
        subtitle: "macOS 鼠标按键二次映射工具：了解用途、完成设置并快速排查问题。",
        statusTitle: "当前运行条件",
        granted: "已授权", missing: "未授权", connected: "已连接", disconnected: "未连接", running: "运行中", stopped: "未运行",
        actionTitles: ["打开辅助功能设置", "打开输入监控设置", "打开按键自定义", "打开滚轮设置"],
        topics: [
            HelpTopic(id: "overview", title: "软件概览", symbol: "sparkles", intro: "V-Mouse鼠标映射读取鼠标当前输出的板载键值，并在 macOS 软件层将其再次映射为键盘、鼠标、系统或工作流动作，同时提供独立的滚轮增强。", bullets: ["这是软件层面的鼠标按键二次映射，只读取输入，不改写鼠标固件或板载内存。", "按键可映射为单键、组合快捷键、鼠标操作、系统功能、打开应用或文件、执行命令、输入文本和切换配置等 Mac 动作。", "按键二次映射与滚轮增强相互独立；开启“连接外接鼠标时停用内置触控板”后，仅在 V-Mouse 运行且外接鼠标存在时停用内置触控板。关闭主面板后软件仍驻留菜单栏；选择“退出”会恢复触控板并停止软件。", "设备默认按 VID/PID 归入同一设备族；指定设备族可启用增强识别，且所有已启用条件必须同时匹配。Naga 有专用适配，其他标准 HID 设备可手动选择和学习。"], note: "二次映射路径：鼠标发送板载键值 → V-Mouse鼠标映射识别输入 → 根据设置直通、屏蔽或执行 Mac 动作。", actions: []),
            HelpTopic(id: "quickstart", title: "快速开始", symbol: "figure.walk", intro: "按顺序完成权限、读取、设置和启用，能避免按键无响应或板载输入意外直通。", bullets: ["在隐私与安全性中开启“辅助功能”和“输入监控”。", "进入按键自定义，在左侧选中设备并读取板载键值，再为该设备启用的配置设置 Mac 动作。", "确认动作后开启“拦截板载输入”，最后打开按键自定义总开关。"], note: "Mac 动作变为蓝色，表示权限、设备、总开关、板载输入、拦截和执行结果均已就绪。", actions: [.accessibility, .inputMonitoring, .mapping]),
            HelpTopic(id: "mapping", title: "按键自定义", symbol: "slider.horizontal.3", intro: "每个可识别的鼠标来源由“板载键值”“Mac 动作”和“拦截板载输入”三部分组成；板载键值与键名属于设备，动作属于该设备启用的配置。", bullets: ["板载键值是鼠标当前发送给电脑的原始结果。", "Mac 动作是您在软件中设置、希望 macOS 最终执行的结果。", "关闭拦截时板载输入直通；开启后板载输入被阻止，并执行 Mac 动作。"], note: "读取后即可开启拦截：设置了 Mac 动作就执行它，未设置则仅屏蔽该键。板载值包含 ⌘ 或 Control 时，卡片右上角可在关闭普通拦截的情况下互换这两个修饰键。读取界面的默认分组与自定义分组都可改名、排序，并可在清空后删除；可在任意分组读取新输入，自动命名为“自定义键 1、2…”，之后可改名或移动分组。", actions: [.mapping]),
            HelpTopic(id: "values", title: "Mac 动作", symbol: "keyboard", intro: "动作不限于单个键，可以覆盖常用的 Mac 输入、系统和自动化操作。", bullets: ["键盘与组合键：单键、修饰键、快捷键和按键序列。", "鼠标与系统：点击、前进后退、媒体、窗口、截图和系统功能。", "工作流：输入文本、打开应用或文件、执行命令、切换配置文件。"], note: "命令和打开目标依赖外部路径与系统环境；蓝色代表输入链路已生效，不保证外部目标永远可用。", actions: [.mapping]),
            HelpTopic(id: "scroll", title: "滚轮增强", symbol: "computermouse", intro: "滚轮增强只处理鼠标滚轮事件，触控板的原生滚动阶段和惯性保持不变。", bullets: ["可分别设置平滑、垂直/水平轴、方向、步长和速度。", "可设置按住时加速、纵向转横向或临时关闭平滑。", "滚轮增强不依赖按键自定义总开关，但需要辅助功能权限。"], note: "“恢复默认设置”会把本页参数恢复为应用预设值；点击“保存并应用”后才会写入当前配置并生效。", actions: [.scroll]),
            HelpTopic(id: "scenarios", title: "使用场景", symbol: "briefcase", intro: "把高频、难按或需要组合操作的 Mac 功能放到拇指侧键，可以减少键盘往返。", bullets: ["办公与浏览：复制粘贴、切换标签页、前进后退、调节音量。", "设计与开发：撤销重做、截图、运行命令、打开固定项目或工具。", "多任务：切换应用、窗口和配置文件，为不同工作建立独立布局。"], note: nil, actions: []),
            HelpTopic(id: "profiles", title: "配置文件", symbol: "folder.badge.gearshape", intro: "配置文件分配给设备并保存 Mac 动作；设备最多启用一个配置，也可以处于“未启用配置”状态，没有全局配置。", bullets: ["在左侧设备下新建、复制、重命名或删除配置；“从此设备移除”只取消分配，不删除配置，即使它是该设备的最后一个配置也可以移除。", "移除最后一个配置后，该设备不执行 Mac 动作，也不进行普通拦截；板载输入默认直通。只有用户明确开启的设备级“⌘ ⇄ Control”互换仍会生效。配置保留在“未分配配置”中，可重新分配。", "同一配置可被多台设备共用，修改会同步；导入前请检查命令、路径和应用，切换配置不会写入鼠标。"], note: nil, actions: [.mapping]),
            HelpTopic(id: "permissions", title: "权限与安全", symbol: "lock.shield", intro: "辅助功能用于发送与处理 Mac 输入；输入监控用于识别键盘式板载值和精确关联鼠标来源。", bullets: ["所有转换均在本机完成，软件不会自动修改系统权限。", "更新后若权限失效，请在系统设置中删除旧版 V-Mouse 条目，再添加并启用当前应用。", "软件不接管物理左右键，也不会写入鼠标板载固件或内存。"], note: "命令动作可以运行您填写的本地命令，只应使用自己理解并信任的内容。", actions: [.accessibility, .inputMonitoring]),
            HelpTopic(id: "troubleshooting", title: "故障排查", symbol: "wrench.and.screwdriver", intro: "先根据状态判断是权限、设备、读取、设置还是运行开关问题。", bullets: ["读不到按键：确认鼠标受支持，并在 20 秒内连续按三次；默认 DPI± 可能要先在 Windows 中改成普通板载键值。", "按键无效果：确认 Mac 动作设在该设备当前启用的配置中、拦截已开启、总开关运行，以及两项权限已授权。", "部分按键同时失效：不同物理键可能发送相同板载信号；重新为其中一个键设置不同板载值后再读取。"], note: "仍有问题时，先关闭拦截让板载输入直通，再逐项重新读取和启用。", actions: [.mapping])
        ]
    )

    private static let english = HelpCopy(
        subtitle: "A macOS mouse-button remapping tool: understand it, complete setup, and diagnose problems quickly.", statusTitle: "Current requirements",
        granted: "Allowed", missing: "Not allowed", connected: "Connected", disconnected: "Disconnected", running: "Running", stopped: "Not running",
        actionTitles: ["Open Accessibility Settings", "Open Input Monitoring Settings", "Open Button Customization", "Open Scroll Settings"],
        topics: [
            HelpTopic(id: "overview", title: "Overview", symbol: "sparkles", intro: "V-Mouse鼠标映射 reads the onboard values your mouse already sends and remaps them in macOS to keyboard, mouse, system, or workflow actions, with independent scroll enhancement.", bullets: ["This is a second, software-level mapping: the app reads input but never rewrites mouse firmware or onboard memory.", "Buttons can run keys, shortcuts, mouse actions, system features, apps or files, commands, text, and profile switches.", "Button remapping and scroll enhancement are independent. When “Disable Built-in Trackpad When External Mouse Is Connected” is enabled, the trackpad is disabled only while V-Mouse is running and an external mouse is present. Closing the panel leaves the menu-bar app running; Quit restores the trackpad and stops the app.", "Devices are grouped by VID/PID by default. Enhanced identity can be enabled per family, and every enabled condition must match. Naga has a dedicated adapter; other standard-HID devices can be selected and learned manually."], note: "Second-mapping flow: mouse sends an onboard value → V-Mouse鼠标映射 identifies it → pass it through, suppress it, or run the configured Mac action.", actions: []),
            HelpTopic(id: "quickstart", title: "Quick Start", symbol: "figure.walk", intro: "Complete permissions, learning, assignment, and activation in order to avoid missing output.", bullets: ["Allow Accessibility and Input Monitoring in Privacy & Security.", "Open Button Customization, select the device in the sidebar, learn the onboard input, then assign a Mac action in its active profile.", "After assigning an action, enable Block Onboard Input and turn on the master switch."], note: "A blue Mac action means the permissions, device, master switch, source, blocking, and output are ready.", actions: [.accessibility, .inputMonitoring, .mapping]),
            HelpTopic(id: "mapping", title: "Button Customization", symbol: "slider.horizontal.3", intro: "Each mouse source consists of an Onboard Value, a Mac Action, and Block Onboard Input. Onboard values and key names belong to the device; actions belong to the device's active profile.", bullets: ["The onboard value is what the mouse currently sends to the computer.", "The Mac action is what you configure macOS to perform.", "With blocking off, the onboard input passes through. With it on, the Mac action runs instead."], note: "After learning, blocking can run the Mac action or suppress an unassigned key. When an onboard value contains ⌘ or Control, the card's top-right switch can swap those modifiers while normal interception is off. Built-in and custom groups can be renamed, reordered, and deleted once empty. Learn a new input in any group; it is named Custom Key 1, 2… and can later be renamed or moved.", actions: [.mapping]),
            HelpTopic(id: "values", title: "Mac Actions", symbol: "keyboard", intro: "An action can contain more than one key and can cover common Mac input, system, and workflow operations.", bullets: ["Keyboard: keys, modifiers, shortcuts, and sequences.", "Mouse and system: clicks, navigation, media, windows, screenshots, and system functions.", "Workflow: text, apps or files, commands, and profile switching."], note: "Blue means the input path is active; it cannot guarantee that an external file, app, or command remains available.", actions: [.mapping]),
            HelpTopic(id: "scroll", title: "Scroll Enhancement", symbol: "computermouse", intro: "Scroll enhancement handles mouse-wheel events only and preserves native trackpad phases and momentum.", bullets: ["Adjust smoothing, axes, direction, step, and speed independently.", "Hold shortcuts can accelerate, convert vertical to horizontal, or suspend smoothing.", "It is independent of button mapping but requires Accessibility."], note: "Restore Defaults resets this page to the app presets. The values are not committed until you choose Save & Apply.", actions: [.scroll]),
            HelpTopic(id: "scenarios", title: "Use Cases", symbol: "briefcase", intro: "Move frequent, awkward, or multi-key Mac tasks to thumb buttons to reduce keyboard travel.", bullets: ["Office and web: copy/paste, tabs, navigation, and volume.", "Design and development: undo/redo, screenshots, commands, and project launchers.", "Multitasking: switch apps, windows, and profiles for different workflows."], note: nil, actions: []),
            HelpTopic(id: "profiles", title: "Profiles", symbol: "folder.badge.gearshape", intro: "Profiles are assigned to devices and store Mac actions. A device can run at most one active profile or intentionally have no active profile; there is no global profile.", bullets: ["Create, duplicate, rename, or delete profiles in the sidebar. Remove from This Device only removes the assignment and remains available for the device's last profile.", "After the last profile is removed, the device runs no Mac actions or normal interception, and onboard input passes through by default. Only a device-level ⌘ ⇄ Control swap explicitly enabled by the user remains active. The profile stays under Unassigned Profiles and can be assigned again.", "A profile can be shared by several devices and edits apply to all of them. Review commands and paths before import; profile switching never writes to mouse memory."], note: nil, actions: [.mapping]),
            HelpTopic(id: "permissions", title: "Permissions & Safety", symbol: "lock.shield", intro: "Accessibility processes and sends Mac input; Input Monitoring recognizes keyboard-like onboard values and correlates the mouse source.", bullets: ["All conversion is local and the app never changes permissions automatically.", "If permissions stop working after an update, remove the old V-Mouse entry in System Settings, then add and enable the current app.", "Physical left/right buttons are excluded, and mouse firmware or memory is never written."], note: "Command actions run local commands you provide. Use only content you understand and trust.", actions: [.accessibility, .inputMonitoring]),
            HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", intro: "Use the status first to separate permission, device, learning, assignment, and activation problems.", bullets: ["Cannot learn: press three times within 20 seconds. Default DPI± may first need a normal onboard value assigned in Windows.", "No output: verify the custom value exists in the device's active profile, plus interception, the master switch, the device, and both permissions.", "Several buttons fail together: they may send the same onboard signal; assign one a different value and learn again."], note: "When in doubt, turn interception off to restore pass-through, then re-enable items one at a time.", actions: [.mapping])
        ]
    )

    private static let japanese = HelpCopy(
        subtitle: "macOS向けマウスボタン再割り当てツールの用途、初期設定、問題の確認方法をまとめています。", statusTitle: "現在の実行条件", granted: "許可済み", missing: "未許可", connected: "接続済み", disconnected: "未接続", running: "実行中", stopped: "停止中",
        actionTitles: ["アクセシビリティ設定を開く", "入力監視設定を開く", "ボタンカスタマイズを開く", "スクロール設定を開く"],
        topics: localizedTopics(
            titles: ["概要", "クイックスタート", "ボタンカスタマイズ", "Macアクション", "スクロール拡張", "使用例", "プロファイル", "権限と安全性", "トラブルシューティング"],
            intros: ["V-Mouse鼠标映射は、マウスが送信するオンボード値を読み取り、macOS上でもう一度キー、マウス、システム、ワークフローの各アクションへ割り当てます。マウスホイールも個別に調整できます。", "権限、読み取り、割り当て、有効化の順で設定します。", "各入力はオンボード値、Macアクション、オンボード入力の遮断で構成され、アクションはデバイスで有効なプロファイルに保存されます。", "単一キーだけでなくMacの入力、システム操作、ワークフローを実行できます。", "マウスホイールだけを処理し、トラックパッドの慣性は維持します。", "よく使う複合操作を親指ボタンに割り当てられます。", "プロファイルはデバイスに割り当てられ、最大1つを有効にするか、有効なプロファイルなしにできます。", "アクセシビリティは入力処理、入力監視はオンボード信号の識別に使用します。", "状態表示から権限、デバイス、読み取り、割り当て、有効化を順に確認します。"],
            bullets: [
                ["macOS内だけで動作し、マウスのオンボードメモリを書き換えません。", "ボタンとスクロール機能は独立しています。", "「外付けマウス接続時に内蔵トラックパッドを無効にする」をオンにすると、V-Mouseの実行中かつ外付けマウス接続中だけ無効になります。パネルを閉じてもメニューバーで動作し、V-Mouseを終了するとトラックパッドを復元します。", "既定ではVID/PIDでデバイス族を識別します。族ごとに拡張識別を有効化でき、有効な条件はすべて一致する必要があります。Nagaは専用対応済みです。"],
                ["アクセシビリティと入力監視を許可します。", "サイドバーでデバイスを選び、オンボード値を読み取り、有効なプロファイルにMacアクションを設定します。", "アクションを設定してから遮断と全体スイッチを有効にします。"],
                ["オンボード値はマウスが現在送信する値です。", "MacアクションはmacOSで実行する内容です。", "遮断がオフならそのまま通し、オンならMacアクションを実行します。"],
                ["キー、修飾キー、ショートカット、シーケンス。", "マウス、メディア、ウインドウ、スクリーンショット。", "テキスト、アプリ、ファイル、コマンド、プロファイル。"],
                ["平滑化、軸、方向、ステップ、速度を調整できます。", "押している間だけ加速や横スクロールに変更できます。", "ボタン設定とは独立していますがアクセシビリティが必要です。"],
                ["コピー、貼り付け、タブ、音量。", "取り消し、スクリーンショット、コマンド、ツール起動。", "アプリ、ウインドウ、プロファイル切替。"],
                ["作成、複製、名前変更、削除ができます。「このデバイスから外す」は最後の1つにも使え、プロファイル自体は削除しません。", "最後のプロファイルを外すと、Macアクションと通常の遮断は停止し、オンボード入力は既定で直通します。ユーザーが明示的に有効にしたデバイス単位の「⌘ ⇄ Control」入れ替えだけは引き続き動作します。未割り当て一覧から再設定できます。", "1つのプロファイルを複数デバイスで共用できます。読み込み前にコマンドやパスを確認してください。"],
                ["処理はすべてローカルで行われます。", "更新後は古い権限項目を削除して現在のアプリを追加します。", "物理左右ボタンとマウスファームウェアは変更しません。"],
                ["20秒以内に3回押します。DPI±はWindowsで通常値に変更が必要な場合があります。", "有効なプロファイルのカスタム値、遮断、全体スイッチ、機器、両方の権限を確認します。", "同じ信号のボタンは異なるオンボード値にして再読み取りします。"]
            ],
            notes: [
                "入力の流れ：マウスボタン → オンボード値を識別 → 遮断を判定 → そのまま通すかMacアクションを実行。",
                "Macアクションが青色なら、権限、デバイス、全体スイッチ、入力元、遮断、出力が準備済みです。",
                "読み取り後はMacアクションの実行または未割り当てキーの完全な遮断ができます。オンボード値に⌘またはControlが含まれる場合、通常の遮断がオフのときにカード右上で両者を入れ替えられます。標準・カスタムの全グループは名前変更、並べ替え、空にして削除できます。",
                "青色は入力経路が有効なことを示しますが、外部のファイル、アプリ、コマンドの存在は保証しません。",
                "「デフォルト設定に戻す」は、このページをアプリの初期値に戻します。「保存して適用」を選ぶまで現在の設定には反映されません。", nil, nil,
                "コマンド操作は入力したローカルコマンドを実行します。内容を理解し信頼できる場合だけ使用してください。",
                "不明な場合は遮断をオフにして直通を戻し、一項目ずつ読み取って再有効化します。"
            ]
        )
    )

    private static let korean = HelpCopy(
        subtitle: "macOS 마우스 버튼 재매핑 도구의 용도, 초기 설정과 문제 해결 방법을 안내합니다.", statusTitle: "현재 실행 조건", granted: "허용됨", missing: "허용 안 됨", connected: "연결됨", disconnected: "연결 안 됨", running: "실행 중", stopped: "실행 안 됨",
        actionTitles: ["손쉬운 사용 설정 열기", "입력 모니터링 설정 열기", "버튼 사용자 지정 열기", "스크롤 설정 열기"],
        topics: localizedTopics(
            titles: ["소프트웨어 개요", "빠른 시작", "버튼 사용자 지정", "Mac 동작", "스크롤 향상", "사용 사례", "프로필", "권한 및 안전", "문제 해결"],
            intros: ["V-Mouse鼠标映射 앱은 마우스가 보내는 온보드 값을 읽어 macOS에서 키보드, 마우스, 시스템 또는 작업 흐름 동작으로 다시 매핑하며 휠 스크롤도 별도로 향상합니다.", "권한, 입력 학습, 동작 지정, 활성화 순서로 완료하세요.", "각 입력은 온보드 값, Mac 동작, 온보드 입력 차단으로 구성되며 동작은 기기의 활성 프로필에 저장됩니다.", "단일 키뿐 아니라 Mac 입력, 시스템 기능과 작업 흐름을 실행할 수 있습니다.", "마우스 휠만 처리하며 트랙패드 관성은 유지합니다.", "자주 쓰는 복합 작업을 엄지 버튼에 배치할 수 있습니다.", "프로필은 기기에 할당되며 최대 하나를 활성화하거나 활성 프로필 없이 둘 수 있습니다.", "손쉬운 사용은 입력 처리에, 입력 모니터링은 온보드 신호 식별에 사용됩니다.", "상태에서 권한, 기기, 입력 학습, 동작 지정과 활성화를 차례로 확인하세요."],
            bullets: [
                ["macOS에서만 처리하며 마우스 온보드 메모리를 쓰지 않습니다.", "버튼과 스크롤 기능은 서로 독립적입니다.", "‘외장 마우스 연결 시 내장 트랙패드 비활성화’를 켜면 V-Mouse가 실행 중이고 외장 마우스가 연결된 동안에만 비활성화됩니다. 패널을 닫아도 메뉴 막대에서 계속 실행되며 V-Mouse를 종료하면 트랙패드가 복원됩니다.", "기본적으로 VID/PID로 장치군을 식별합니다. 장치군별 강화 식별을 켤 수 있으며 활성화된 모든 조건이 일치해야 합니다. Naga는 전용 지원됩니다."],
                ["손쉬운 사용과 입력 모니터링을 허용합니다.", "사이드바에서 기기를 선택해 온보드 값을 읽고 활성 프로필에 Mac 동작을 지정합니다.", "동작을 지정한 뒤 차단과 전체 스위치를 켭니다."],
                ["온보드 값은 마우스가 현재 보내는 값입니다.", "Mac 동작은 macOS가 실행할 내용입니다.", "차단이 꺼지면 그대로 전달하고 켜지면 Mac 동작을 실행합니다."],
                ["키, 보조 키, 단축키와 키 순서.", "마우스, 미디어, 창, 스크린샷과 시스템 기능.", "텍스트, 앱, 파일, 명령과 프로필 전환."],
                ["스무딩, 축, 방향, 단계와 속도를 조절합니다.", "길게 누르는 동안 가속, 가로 스크롤 전환, 스무딩 일시 중지를 사용할 수 있습니다.", "버튼 설정과 독립적이지만 손쉬운 사용 권한이 필요합니다."],
                ["복사/붙여넣기, 탭, 탐색과 음량.", "실행 취소, 스크린샷, 명령과 도구 열기.", "앱, 창과 프로필 전환."],
                ["만들기, 복제, 이름 변경, 삭제가 가능합니다. ‘이 기기에서 제거’는 마지막 프로필에도 사용할 수 있으며 프로필 자체는 삭제하지 않습니다.", "마지막 프로필을 제거하면 Mac 동작과 일반 차단이 중지되고 온보드 입력은 기본적으로 그대로 전달됩니다. 사용자가 명시적으로 켠 기기별 ‘⌘ ⇄ Control’ 전환만 계속 작동합니다. 할당되지 않은 프로필 목록에서 다시 할당할 수 있습니다.", "한 프로필을 여러 기기가 공유할 수 있습니다. 가져오기 전에 명령과 경로를 확인하세요."],
                ["모든 변환은 로컬에서 처리됩니다.", "업데이트 후 오래된 권한 항목을 지우고 현재 앱을 추가하세요.", "물리 왼쪽/오른쪽 버튼과 펌웨어는 변경하지 않습니다."],
                ["20초 안에 세 번 누르세요. DPI±는 Windows에서 일반 값으로 바꿔야 할 수 있습니다.", "활성 프로필의 사용자 지정 값, 차단, 전체 스위치, 장치와 두 권한을 확인하세요.", "같은 신호를 보내는 버튼은 다른 온보드 값으로 바꾸고 다시 읽으세요."]
            ],
            notes: [
                "입력 흐름: 마우스 버튼 → 온보드 값 식별 → 차단 결정 → 그대로 전달하거나 Mac 동작 실행.",
                "Mac 동작이 파란색이면 권한, 기기, 전체 스위치, 입력, 차단과 출력이 준비된 상태입니다.",
                "학습 후 사용자 지정 값을 실행하거나 미할당 키를 완전히 차단할 수 있습니다. 온보드 값에 ⌘ 또는 Control이 있으면 일반 차단이 꺼진 상태에서 카드 오른쪽 위 스위치로 두 보조 키를 바꿀 수 있습니다. 기본 및 사용자 지정 그룹은 이름 변경, 순서 변경, 비운 뒤 삭제할 수 있습니다.",
                "파란색은 입력 경로가 활성화되었음을 뜻하지만 외부 파일, 앱 또는 명령의 상태를 보장하지는 않습니다.",
                "‘기본 설정 복원’은 이 페이지를 앱의 초기값으로 되돌립니다. ‘저장 및 적용’을 선택해야 현재 설정에 반영됩니다.", nil, nil,
                "명령 동작은 입력한 로컬 명령을 실행합니다. 이해하고 신뢰하는 내용만 사용하세요.",
                "확신할 수 없으면 차단을 끄고 온보드 값을 통과시킨 뒤 항목을 하나씩 다시 읽고 활성화하세요."
            ]
        )
    )

    private static let german = HelpCopy(
        subtitle: "Zweck, Einrichtung und Fehlersuche des macOS-Werkzeugs zur Neubelegung von Maustasten.", statusTitle: "Aktuelle Voraussetzungen", granted: "Erlaubt", missing: "Nicht erlaubt", connected: "Verbunden", disconnected: "Nicht verbunden", running: "Aktiv", stopped: "Nicht aktiv",
        actionTitles: ["Bedienungshilfen öffnen", "Eingabeüberwachung öffnen", "Tastenanpassung öffnen", "Scroll-Einstellungen öffnen"],
        topics: localizedTopics(
            titles: ["Überblick", "Schnellstart", "Tastenanpassung", "Mac-Aktionen", "Scroll-Verbesserung", "Anwendungsfälle", "Profile", "Berechtigungen & Sicherheit", "Fehlerbehebung"],
            intros: ["V-Mouse鼠标映射 liest die von der Maus gesendeten Onboard-Werte und belegt sie unter macOS ein zweites Mal mit Tastatur-, Maus-, System- oder Arbeitsablaufaktionen. Das Mausrad lässt sich unabhängig davon verbessern.", "Berechtigungen, Anlernen, Zuweisen und Aktivieren nacheinander abschließen.", "Jede Eingabe besteht aus Onboard-Wert, Mac-Aktion und Blockierung der Onboard-Eingabe; Aktionen werden im aktiven Profil des Geräts gespeichert.", "Nicht nur einzelne Tasten, sondern auch Mac-, System- und Arbeitsablaufaktionen sind möglich.", "Nur das Mausrad wird verarbeitet; die Trackpad-Trägheit bleibt erhalten.", "Häufige oder umständliche Aktionen lassen sich auf Daumentasten legen.", "Profile werden Geräten zugewiesen; höchstens eines ist aktiv, ein Gerät kann auch kein aktives Profil haben.", "Bedienungshilfen verarbeiten Eingaben; Eingabeüberwachung erkennt Onboard-Signale.", "Anhand des Status Berechtigungen, Gerät, Anlernen, Zuweisung und Aktivierung prüfen."],
            bullets: [
                ["Die Verarbeitung erfolgt nur in macOS; der Onboard-Speicher bleibt unverändert.", "Tasten und Scrollen sind unabhängig.", "Ist „Integriertes Trackpad bei externer Maus deaktivieren“ eingeschaltet, bleibt das Trackpad nur während der Ausführung von V-Mouse und bei angeschlossener externer Maus deaktiviert. Nach dem Schließen des Fensters läuft die Menüleisten-App weiter; beim Beenden von V-Mouse wird das Trackpad wieder aktiviert.", "Standardmäßig identifiziert VID/PID eine Gerätefamilie. Erweiterte Erkennung ist je Familie möglich; alle aktivierten Bedingungen müssen passen. Naga wird speziell unterstützt."],
                ["Bedienungshilfen und Eingabeüberwachung erlauben.", "Gerät in der Seitenleiste auswählen, Onboard-Wert anlernen und im aktiven Profil eine Mac-Aktion zuweisen.", "Danach Blockierung und Hauptschalter aktivieren."],
                ["Der Onboard-Wert ist das aktuelle Maussignal.", "Die Mac-Aktion ist die in der App festgelegte Ausgabe.", "Ohne Blockierung wird die Eingabe durchgelassen; mit Blockierung wird die Mac-Aktion ausgeführt."],
                ["Tasten, Modifikatoren, Kurzbefehle und Sequenzen.", "Maus, Medien, Fenster, Bildschirmfotos und Systemfunktionen.", "Text, Apps, Dateien, Befehle und Profilwechsel."],
                ["Glättung, Achsen, Richtung, Schritt und Tempo einstellen.", "Halten kann beschleunigen, horizontal scrollen oder Glättung aussetzen.", "Unabhängig von Tasten, aber mit Bedienungshilfen-Berechtigung."],
                ["Kopieren, Einfügen, Tabs, Navigation und Lautstärke.", "Rückgängig, Bildschirmfotos, Befehle und Werkzeuge.", "Apps, Fenster und Profile wechseln."],
                ["Profile erstellen, kopieren, umbenennen und löschen. „Von diesem Gerät entfernen“ gilt auch für das letzte Profil und löscht das Profil selbst nicht.", "Nach Entfernen des letzten Profils gibt es keine Mac-Aktion und kein normales Abfangen; Onboard-Eingaben werden standardmäßig durchgeleitet. Nur ein ausdrücklich aktivierter, gerätebezogener Tausch „⌘ ⇄ Control“ bleibt wirksam. Nicht zugewiesene Profile lassen sich erneut zuordnen.", "Ein Profil kann von mehreren Geräten gemeinsam genutzt werden. Vor dem Import Befehle und Pfade prüfen."],
                ["Alle Umwandlungen erfolgen lokal.", "Nach Updates alte Berechtigungseinträge entfernen und die aktuelle App hinzufügen.", "Physische Links-/Rechtstasten und Firmware bleiben unverändert."],
                ["Innerhalb von 20 Sekunden dreimal drücken; DPI± muss eventuell unter Windows normal belegt werden.", "Benutzerwert im aktiven Profil, Abfangen, Hauptschalter, Gerät und beide Berechtigungen prüfen.", "Bei gleichen Signalen einen anderen Onboard-Wert zuweisen und neu anlernen."]
            ],
            notes: [
                "Eingabefluss: Maustaste → Onboard-Wert erkennen → Blockierung entscheiden → durchlassen oder Mac-Aktion ausführen.",
                "Eine blau dargestellte Mac-Aktion bedeutet, dass Berechtigungen, Gerät, Hauptschalter, Quelle, Blockierung und Ausgabe bereit sind.",
                "Nach dem Anlernen kann ein Benutzerwert ausgeführt oder eine unbelegte Taste vollständig blockiert werden. Enthält der Onboard-Wert ⌘ oder Control, tauscht der Schalter oben rechts beide Modifikatoren bei ausgeschaltetem normalem Abfangen. Standard- und eigene Gruppen lassen sich umbenennen, sortieren und nach dem Leeren löschen.",
                "Blau zeigt einen aktiven Eingabepfad, garantiert aber nicht, dass eine externe Datei, App oder ein Befehl verfügbar bleibt.",
                "„Standardeinstellungen wiederherstellen“ setzt diese Seite auf die App-Vorgaben zurück. Wirksam wird die Änderung erst mit „Sichern & Anwenden“.", nil, nil,
                "Befehlsaktionen führen die eingegebenen lokalen Befehle aus. Nur verstandene und vertrauenswürdige Inhalte verwenden.",
                "Im Zweifel das Abfangen ausschalten, die Durchleitung wiederherstellen und die Einträge einzeln neu anlernen und aktivieren."
            ]
        )
    )

    private static func localizedTopics(titles: [String], intros: [String], bullets: [[String]], notes: [String?]) -> [HelpTopic] {
        let ids = ["overview", "quickstart", "mapping", "values", "scroll", "scenarios", "profiles", "permissions", "troubleshooting"]
        let symbols = ["sparkles", "figure.walk", "slider.horizontal.3", "keyboard", "computermouse", "briefcase", "folder.badge.gearshape", "lock.shield", "wrench.and.screwdriver"]
        precondition(titles.count == ids.count && intros.count == ids.count && bullets.count == ids.count && notes.count == ids.count)
        return ids.indices.map { index in
            let actions: [HelpAction]
            switch ids[index] {
            case "quickstart": actions = [.accessibility, .inputMonitoring, .mapping]
            case "mapping", "values", "profiles", "troubleshooting": actions = [.mapping]
            case "scroll": actions = [.scroll]
            case "permissions": actions = [.accessibility, .inputMonitoring]
            default: actions = []
            }
            return HelpTopic(id: ids[index], title: titles[index], symbol: symbols[index], intro: intros[index], bullets: bullets[index], note: notes[index], actions: actions)
        }
    }
}

func helpContentValidationFailures() -> [String] {
    let expectedIDs = ["overview", "quickstart", "mapping", "values", "scroll", "scenarios", "profiles", "permissions", "troubleshooting"]
    let expectedNotePresence = [true, true, true, true, true, false, false, true, true]
    let expectedActions: [[HelpAction]] = [
        [], [.accessibility, .inputMonitoring, .mapping], [.mapping], [.mapping],
        [.scroll], [], [.mapping], [.accessibility, .inputMonitoring], [.mapping]
    ]
    let expectedBulletCounts = [4, 3, 3, 3, 3, 3, 3, 3, 3]
    var failures: [String] = []
    for language in AppLanguage.allCases {
        let copy = L10n.withTemporaryLanguage(language) { HelpCopy.current() }
        let ids = copy.topics.map(\.id)
        if ids != expectedIDs || Set(ids).count != expectedIDs.count {
            failures.append("\(language.rawValue): invalid topic identifiers")
        }
        if copy.subtitle.isEmpty || copy.actionTitles.count != 4 || copy.actionTitles.contains(where: \.isEmpty) {
            failures.append("\(language.rawValue): incomplete help chrome")
        }
        if copy.topics.contains(where: { $0.title.isEmpty || $0.intro.isEmpty || $0.bullets.count < 3 || $0.bullets.contains(where: \.isEmpty) }) {
            failures.append("\(language.rawValue): incomplete help topic content")
        }
        if copy.topics.map({ $0.bullets.count }) != expectedBulletCounts {
            failures.append("\(language.rawValue): inconsistent help bullet schema")
        }
        if copy.topics.map({ $0.note != nil }) != expectedNotePresence {
            failures.append("\(language.rawValue): inconsistent help note schema")
        }
        if copy.topics.map(\.actions) != expectedActions {
            failures.append("\(language.rawValue): inconsistent help action schema")
        }
        let searchableText = ([copy.subtitle] + copy.actionTitles + copy.topics.flatMap { topic in
            [topic.title, topic.intro] + topic.bullets + [topic.note].compactMap { $0 }
        }).joined(separator: "\n")
        let forbiddenTerms: [String]
        switch language {
        case .chineseSimplified:
            forbiddenTerms = ["Mac 自定义键值", "未挂载配置"]
        case .english:
            forbiddenTerms = ["Mac custom value", "Mac Custom Value", "Unmounted Profiles", "unmounts a profile"]
        case .japanese:
            forbiddenTerms = ["録入", "Macカスタム値", "デバイス未報告", "Appleグラス"]
        case .korean:
            forbiddenTerms = ["Mac 사용자 지정 값", "미연결 목록", "공용할", "부드럽게 중지"]
        case .german:
            forbiddenTerms = ["Mac-Benutzerwert", "Nicht eingehängte Profile", "Apple-Glas"]
        }
        if forbiddenTerms.contains(where: searchableText.contains) {
            failures.append("\(language.rawValue): contains retired or unnatural terminology")
        }
    }
    return failures
}

private final class FlippedHelpStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class TutorialViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var copy: HelpCopy
    private var selectedIndex: Int
    private let tableView = NSTableView()
    private let topicPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let sidebarScroll = NSScrollView()
    private let detailScroll = NSScrollView()
    private let detailStack = FlippedHelpStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var inputObserver: NSObjectProtocol?
    private var deviceObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var compactLayout: Bool?

    var selectedTopicID: String { copy.topics[selectedIndex].id }

    init(initialTopicID: String? = nil) {
        let copy = HelpCopy.current()
        self.copy = copy
        if let initialTopicID, let index = copy.topics.firstIndex(where: { $0.id == initialTopicID }) {
            selectedIndex = index
        } else {
            let requested = Int(ProcessInfo.processInfo.environment["NAGA_UI_HELP_TOPIC_INDEX"] ?? "") ?? 0
            selectedIndex = min(max(requested, 0), max(0, copy.topics.count - 1))
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        [inputObserver, deviceObserver, activeObserver].compactMap { $0 }.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    override func loadView() {
        let root = NSView()
        view = root
        let background = UIStyle.makeBackground(material: .windowBackground)
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        let title = NSTextField(labelWithString: L10n.text("帮助中心"))
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: copy.subtitle)
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabelColor
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let version = NSTextField(labelWithString: "v\(shortVersion) (\(buildNumber))")
        version.font = .systemFont(ofSize: 11, weight: .medium)
        version.textColor = .tertiaryLabelColor
        version.setAccessibilityLabel(L10n.format("V-Mouse鼠标映射 版本 %@，构建 %@", shortVersion, buildNumber))
        let headerText = NSStackView(views: [title, subtitle, version])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 4

        topicPopup.addItems(withTitles: copy.topics.map(\.title))
        topicPopup.target = self
        topicPopup.action = #selector(popupChanged)
        topicPopup.isHidden = true
        topicPopup.setAccessibilityLabel(L10n.text("帮助主题"))

        let header = NSStackView(views: [headerText, NSView(), topicPopup])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HelpTopic"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .regular
        tableView.setAccessibilityLabel(L10n.text("帮助主题"))
        sidebarScroll.documentView = tableView
        sidebarScroll.hasVerticalScroller = true
        sidebarScroll.autohidesScrollers = true
        sidebarScroll.drawsBackground = false
        sidebarScroll.widthAnchor.constraint(equalToConstant: 205).isActive = true

        detailStack.orientation = .vertical
        detailStack.alignment = .leading
        detailStack.spacing = 14
        detailStack.edgeInsets = NSEdgeInsets(top: 4, left: 18, bottom: 24, right: 18)
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.documentView = detailStack
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.drawsBackground = false
        detailStack.leadingAnchor.constraint(equalTo: detailScroll.contentView.leadingAnchor).isActive = true
        detailStack.trailingAnchor.constraint(equalTo: detailScroll.contentView.trailingAnchor).isActive = true
        detailStack.topAnchor.constraint(equalTo: detailScroll.contentView.topAnchor).isActive = true
        detailStack.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor).isActive = true

        let body = NSStackView(views: [sidebarScroll, detailScroll])
        body.orientation = .horizontal
        body.alignment = .top
        body.spacing = 12
        detailScroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detailScroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let layout = NSStackView(views: [header, body])
        layout.orientation = .vertical
        layout.spacing = 14
        layout.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        root.addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            background.topAnchor.constraint(equalTo: root.topAnchor),
            background.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            layout.topAnchor.constraint(equalTo: root.topAnchor),
            layout.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.widthAnchor.constraint(equalTo: layout.widthAnchor, constant: -40),
            body.widthAnchor.constraint(equalTo: layout.widthAnchor, constant: -40),
            body.heightAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        renderSelectedTopic()
        installObservers()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let compact = view.bounds.width < 700
        if compactLayout != compact {
            let hadLayout = compactLayout != nil
            compactLayout = compact
            sidebarScroll.isHidden = compact
            topicPopup.isHidden = !compact
            if hadLayout { renderSelectedTopic() }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { copy.topics.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let topic = copy.topics[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: UIStyle.symbol(topic.symbol, size: 15, weight: .medium) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        let label = NSTextField(labelWithString: topic.title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        cell.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        cell.textField = label
        cell.toolTip = topic.title
        cell.setAccessibilityLabel(topic.title)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0 else { return }
        selectTopic(tableView.selectedRow)
    }

    @objc private func popupChanged() { selectTopic(topicPopup.indexOfSelectedItem) }

    private func selectTopic(_ index: Int) {
        guard copy.topics.indices.contains(index) else { return }
        selectedIndex = index
        topicPopup.selectItem(at: index)
        if tableView.selectedRow != index {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        renderSelectedTopic()
    }

    private func renderSelectedTopic() {
        detailStack.arrangedSubviews.forEach { detailStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let topic = copy.topics[selectedIndex]
        let heading = NSTextField(labelWithString: topic.title)
        heading.font = .systemFont(ofSize: 23, weight: .semibold)
        heading.setAccessibilityLabel(topic.title)
        detailStack.addArrangedSubview(heading)

        let intro = bodyLabel(topic.intro, font: .systemFont(ofSize: 15))
        detailStack.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -36).isActive = true

        if topic.id == "quickstart" || topic.id == "permissions" {
            let statusCard = UIStyle.makeCard()
            let statusStack = NSStackView()
            statusStack.orientation = .vertical
            statusStack.alignment = .leading
            statusStack.spacing = 7
            let statusTitle = NSTextField(labelWithString: copy.statusTitle)
            statusTitle.font = .systemFont(ofSize: 14, weight: .semibold)
            statusStack.addArrangedSubview(statusTitle)
            statusStack.addArrangedSubview(statusLabel)
            statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            statusCard.addSubview(statusStack)
            statusStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 14),
                statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -14),
                statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 12),
                statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -12)
            ])
            detailStack.addArrangedSubview(statusCard)
            statusCard.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -36).isActive = true
            refreshStatus()
        }

        for (offset, bullet) in topic.bullets.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 10
            let number = NSTextField(labelWithString: "\(offset + 1)")
            number.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
            number.alignment = .center
            number.textColor = .controlAccentColor
            number.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let text = bodyLabel(bullet, font: .systemFont(ofSize: 14))
            row.addArrangedSubview(number)
            row.addArrangedSubview(text)
            detailStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -36).isActive = true
        }

        if let note = topic.note {
            let noteCard = UIStyle.makeCard()
            noteCard.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
            let label = bodyLabel(note, font: .systemFont(ofSize: 13, weight: .medium))
            noteCard.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: noteCard.leadingAnchor, constant: 13),
                label.trailingAnchor.constraint(equalTo: noteCard.trailingAnchor, constant: -13),
                label.topAnchor.constraint(equalTo: noteCard.topAnchor, constant: 11),
                label.bottomAnchor.constraint(equalTo: noteCard.bottomAnchor, constant: -11)
            ])
            detailStack.addArrangedSubview(noteCard)
            noteCard.widthAnchor.constraint(equalTo: detailStack.widthAnchor, constant: -36).isActive = true
        }

        if !topic.actions.isEmpty {
            let actions = NSStackView()
            actions.orientation = .vertical
            actions.alignment = .leading
            actions.spacing = 8
            for action in topic.actions {
                let button = ThemeButton(title: actionTitle(action), target: self, action: #selector(actionTapped(_:)))
                button.tag = actionTag(action)
                // All action buttons share one style: highlighting only the
                // first read as an inconsistency, not an emphasis.
                button.buttonType = .primary
                actions.addArrangedSubview(button)
            }
            detailStack.addArrangedSubview(actions)
        }
        detailScroll.contentView.scroll(to: .zero)
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
    }

    private func bodyLabel(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func actionTag(_ action: HelpAction) -> Int {
        switch action { case .accessibility: return 0; case .inputMonitoring: return 1; case .mapping: return 2; case .scroll: return 3 }
    }

    private func actionTitle(_ action: HelpAction) -> String { copy.actionTitles[actionTag(action)] }

    @objc private func actionTapped(_ sender: NSButton) {
        switch sender.tag {
        case 0: PermissionManager.shared.openAccessibilityPreferences()
        case 1: PermissionManager.shared.openInputMonitoringPreferences()
        case 2: MappingWindowController.shared.show()
        case 3: ScrollSettingsWindowController.shared.show()
        default: break
        }
    }

    private func installObservers() {
        inputObserver = NotificationCenter.default.addObserver(forName: InputCoordinator.stateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshStatus() }
        deviceObserver = NotificationCenter.default.addObserver(forName: HIDListener.deviceStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshStatus() }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshStatus() }
    }

    private func refreshStatus() {
        let accessibility = PermissionManager.shared.hasAccessibilityPermission() ? copy.granted : copy.missing
        let monitoring = PermissionManager.shared.hasInputMonitoringPermission() ? copy.granted : copy.missing
        let device = HIDListener.shared.hasSupportedDevice ? copy.connected : copy.disconnected
        let mapping = InputCoordinator.shared.state == .active ? copy.running : copy.stopped
        statusLabel.stringValue = "\(L10n.text("辅助功能"))：\(accessibility)    \(L10n.text("输入监控"))：\(monitoring)\n\(L10n.text("输入设备"))：\(device)    \(L10n.text("按键映射"))：\(mapping)"
        statusLabel.textColor = InputCoordinator.shared.state == .active ? UIStyle.successColor : UIStyle.warningColor
    }
}
