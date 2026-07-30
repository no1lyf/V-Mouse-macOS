import Foundation
import ApplicationServices
import Carbon.HIToolbox

enum ActionType: Equatable {
    case keySequence(keys: [KeyStroke], description: String?)
    case application(path: String, description: String?)
    case systemCommand(command: String, description: String?)
    case textSnippet(text: String, description: String?)
    case macro(steps: [MacroStep], description: String?)
    case profileSwitch(profile: String, description: String?)
    case mouseClick(button: Int, description: String?)
    case systemAction(identifier: String, description: String?)
    case openTarget(target: String, description: String?)
    case scrollControl(role: ScrollControlRole, description: String?)
}

enum MacShortcutExecutionMode: Equatable {
    case trigger
    case stateful
}

struct SystemActionDefinition: Equatable {
    let identifier: String
    private let nameKey: String
    private let categoryKey: String
    let stroke: KeyStroke
    let executionMode: MacShortcutExecutionMode

    var name: String { L10n.text(nameKey) }
    var category: String { L10n.text(categoryKey) }

    init(
        identifier: String,
        name: String,
        category: String,
        stroke: KeyStroke,
        executionMode: MacShortcutExecutionMode = .trigger
    ) {
        self.identifier = identifier
        self.nameKey = name
        self.categoryKey = category
        self.stroke = stroke
        self.executionMode = executionMode
    }

    static let all: [SystemActionDefinition] = [
        // 功能键（与 Mos 的分组和顺序一致）
        shortcut("missionControl", "调度中心", "功能键", 160, ["fn"]),
        shortcut("launchpad", "启动台", "功能键", 131, ["fn"]),
        shortcut("spotlightSys", "聚焦搜索（系统）", "功能键", 177, ["fn"]),
        shortcut("dictation", "听写", "功能键", 176, ["fn"]),
        shortcut("doNotDisturb", "勿扰模式", "功能键", 178, ["fn"]),
        shortcut("showDesktop", "显示桌面", "功能键", 103, ["fn"]),
        shortcut("escapeKey", "退出键", "功能键", UInt16(kVK_Escape)),
        shortcut("moveSpaceLeft", "向左移动空间", "功能键", UInt16(kVK_LeftArrow), ["ctrl", "fn"]),
        shortcut("moveSpaceRight", "向右移动空间", "功能键", UInt16(kVK_RightArrow), ["ctrl", "fn"]),

        // 应用与窗口
        shortcut("switchApp", "切换应用", "应用与窗口", UInt16(kVK_Tab), ["cmd"]),
        shortcut("switchAppReverse", "切换应用（反向）", "应用与窗口", UInt16(kVK_Tab), ["cmd", "shift"]),
        shortcut("minimizeWindow", "最小化窗口", "应用与窗口", UInt16(kVK_ANSI_M), ["cmd"]),
        shortcut("hideApplication", "隐藏应用", "应用与窗口", UInt16(kVK_ANSI_H), ["cmd"]),
        shortcut("hideOthers", "隐藏其他", "应用与窗口", UInt16(kVK_ANSI_H), ["cmd", "alt"]),
        shortcut("nextWindow", "下一个窗口", "应用与窗口", UInt16(kVK_ANSI_Grave), ["cmd"]),
        shortcut("closeWindow", "关闭窗口", "应用与窗口", UInt16(kVK_ANSI_W), ["cmd"]),
        shortcut("closeAllWindows", "关闭所有窗口", "应用与窗口", UInt16(kVK_ANSI_W), ["cmd", "alt"]),
        shortcut("quitApp", "退出应用", "应用与窗口", UInt16(kVK_ANSI_Q), ["cmd"]),

        // 文档编辑
        shortcut("copy", "拷贝", "文档编辑", UInt16(kVK_ANSI_C), ["cmd"]),
        shortcut("paste", "粘贴", "文档编辑", UInt16(kVK_ANSI_V), ["cmd"]),
        shortcut("cut", "剪切", "文档编辑", UInt16(kVK_ANSI_X), ["cmd"]),
        shortcut("undo", "撤销", "文档编辑", UInt16(kVK_ANSI_Z), ["cmd"]),
        shortcut("redo", "重做", "文档编辑", UInt16(kVK_ANSI_Z), ["cmd", "shift"]),
        shortcut("selectAll", "全选", "文档编辑", UInt16(kVK_ANSI_A), ["cmd"]),
        shortcut("find", "查找", "文档编辑", UInt16(kVK_ANSI_F), ["cmd"]),
        shortcut("bold", "粗体", "文档编辑", UInt16(kVK_ANSI_B), ["cmd"]),
        shortcut("italic", "斜体", "文档编辑", UInt16(kVK_ANSI_I), ["cmd"]),
        shortcut("underline", "下划线", "文档编辑", UInt16(kVK_ANSI_U), ["cmd"]),

        // 访达操作
        shortcut("newFinderWindow", "新建访达窗口", "访达操作", UInt16(kVK_ANSI_N), ["cmd"]),
        shortcut("moveToTrash", "移到废纸篓", "访达操作", UInt16(kVK_Delete), ["cmd"]),
        shortcut("emptyTrash", "清倒废纸篓", "访达操作", UInt16(kVK_Delete), ["cmd", "shift"]),
        shortcut("duplicateFile", "制作副本", "访达操作", UInt16(kVK_ANSI_D), ["cmd"]),
        shortcut("getInfo", "显示简介", "访达操作", UInt16(kVK_ANSI_I), ["cmd"]),
        shortcut("newFolder", "新建文件夹", "访达操作", UInt16(kVK_ANSI_N), ["cmd", "shift"]),
        shortcut("goToFolder", "前往文件夹", "访达操作", UInt16(kVK_ANSI_G), ["cmd", "shift"]),
        shortcut("viewAsIcons", "以图标显示", "访达操作", UInt16(kVK_ANSI_1), ["cmd"]),
        shortcut("viewAsList", "以列表显示", "访达操作", UInt16(kVK_ANSI_2), ["cmd"]),
        shortcut("viewAsColumns", "以分栏显示", "访达操作", UInt16(kVK_ANSI_3), ["cmd"]),
        shortcut("viewAsGallery", "以画廊显示", "访达操作", UInt16(kVK_ANSI_4), ["cmd"]),

        // 系统功能。Control + Power invokes macOS's power dialog; it does not
        // directly execute shutdown. The former Control-Z mapping was unrelated.
        shortcut("spotlight", "聚焦搜索", "系统功能", UInt16(kVK_Space), ["cmd"]),
        shortcut("characterViewer", "表情符号与符号", "系统功能", UInt16(kVK_Space), ["ctrl", "cmd"]),
        shortcut("forceQuit", "强制退出", "系统功能", UInt16(kVK_Escape), ["cmd", "alt"]),
        shortcut("lockScreen", "锁定屏幕", "系统功能", UInt16(kVK_ANSI_Q), ["cmd", "ctrl"]),
        shortcut("logout", "登出", "系统功能", UInt16(kVK_ANSI_Q), ["cmd", "shift"]),
        shortcut("shutdownDialog", "关机对话框", "系统功能", 127, ["ctrl"]),

        // 截图
        shortcut("screenshot", "截屏", "截图", UInt16(kVK_ANSI_3), ["cmd", "shift"]),
        shortcut("screenshotSelection", "截取所选区域", "截图", UInt16(kVK_ANSI_4), ["cmd", "shift"]),
        shortcut("screenshotAndRecording", "截屏和录制选项", "截图", UInt16(kVK_ANSI_5), ["cmd", "shift"]),

        // 导航
        shortcut("navigateBack", "后退", "导航", UInt16(kVK_LeftArrow), ["cmd"]),
        shortcut("navigateForward", "前进", "导航", UInt16(kVK_RightArrow), ["cmd"]),
        shortcut("previousTab", "上一个标签页", "导航", UInt16(kVK_Tab), ["ctrl", "shift"]),
        shortcut("nextTab", "下一个标签页", "导航", UInt16(kVK_Tab), ["ctrl"]),
        shortcut("switchTabLeft", "切换到左侧标签页", "导航", UInt16(kVK_LeftArrow), ["cmd", "alt"]),
        shortcut("switchTabRight", "切换到右侧标签页", "导航", UInt16(kVK_RightArrow), ["cmd", "alt"]),

        // 修饰键：按住鼠标来源时保持，松开时由统一状态机释放。
        shortcut("modifierShift", "Shift", "修饰键", 56, executionMode: .stateful),
        shortcut("modifierOption", "Option", "修饰键", 58, executionMode: .stateful),
        shortcut("modifierControl", "Control", "修饰键", 59, executionMode: .stateful),
        shortcut("modifierCommand", "Command", "修饰键", 55, executionMode: .stateful),
        shortcut("modifierFn", "Function", "修饰键", 63, executionMode: .stateful)
    ]

    private static let categoryKeys = ["功能键", "应用与窗口", "文档编辑", "访达操作", "系统功能", "截图", "导航", "修饰键"]
    static var categories: [String] { categoryKeys.map(L10n.text) }

    private static let legacyAliases: [String: String] = [
        "appExpose": "launchpad",
        "screenshotToolbar": "screenshotAndRecording"
    ]

    static func canonicalIdentifier(_ identifier: String) -> String {
        legacyAliases[identifier] ?? identifier
    }

    static func definition(for identifier: String) -> SystemActionDefinition? {
        let identifier = canonicalIdentifier(identifier)
        return all.first { $0.identifier == identifier }
    }

    static func definitions(in category: String) -> [SystemActionDefinition] {
        all.filter { $0.category == category }
    }

    private static func shortcut(
        _ identifier: String,
        _ name: String,
        _ category: String,
        _ keyCode: UInt16,
        _ modifiers: [String] = [],
        executionMode: MacShortcutExecutionMode = .trigger
    ) -> SystemActionDefinition {
        SystemActionDefinition(
            identifier: identifier,
            name: name,
            category: category,
            stroke: KeyStroke(
                key: KeyStroke.canonicalKeyString(for: keyCode, characters: nil),
                modifiers: modifiers,
                keyCode: keyCode
            ),
            executionMode: executionMode
        )
    }
}

struct KeyStroke: Equatable, Codable {
    var key: String // canonical identifier (e.g., "c", "delete")
    var modifiers: [String] // e.g., ["cmd", "shift"]
    var keyCode: UInt16? = nil // hardware key code when known
}

extension KeyStroke {
    var displayLabel: String {
        if let code = keyCode {
            return KeyStroke.displayName(for: code, fallback: key)
        }
        return key.count == 1 ? key.uppercased() : key.capitalized
    }

    func formattedShortcut() -> String {
        if let code = keyCode ?? KeyStroke.keyCode(for: key) {
            var flags: CGEventFlags = []
            for modifier in modifiers.map({ $0.lowercased() }) {
                switch modifier {
                case "cmd", "command": flags.insert(.maskCommand)
                case "shift": flags.insert(.maskShift)
                case "alt", "option": flags.insert(.maskAlternate)
                case "ctrl", "control": flags.insert(.maskControl)
                case "fn": flags.insert(.maskSecondaryFn)
                default: break
                }
            }
            return HardwareKeyDisplay.keyboard(keyCode: Int(code), modifierFlags: flags.rawValue)
        }
        let symbols = modifiers.map { KeyStroke.modifierSymbol(for: $0) }.joined()
        return symbols + displayLabel
    }

    static func canonicalKeyString(for keyCode: UInt16?, characters: String?) -> String {
        if let code = keyCode, let primary = primaryKeyNames[code] {
            return primary
        }
        if let chars = characters, !chars.isEmpty {
            return normalizeIdentifier(chars)
        }
        return ""
    }

    static func displayName(for keyCode: UInt16, fallback: String) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }
        if fallback.count == 1 {
            return fallback.uppercased()
        }
        return fallback.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    static func displayName(for keyCode: UInt16) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        guard let canonical = primaryKeyNames[keyCode], !canonical.isEmpty else {
            return "未知键（\(keyCode)）"
        }
        return displayName(for: keyCode, fallback: canonical)
    }

    static func keyCode(for key: String) -> UInt16? {
        canonicalKeyCodes[normalizeIdentifier(key)]
    }

    static func fromCharacter(_ scalar: UnicodeScalar) -> KeyStroke? {
        switch scalar {
        case "\n":
            return KeyStroke(key: "return", modifiers: [], keyCode: UInt16(kVK_Return))
        case "\r":
            return KeyStroke(key: "return", modifiers: [], keyCode: UInt16(kVK_Return))
        case "\t":
            return KeyStroke(key: "tab", modifiers: [], keyCode: UInt16(kVK_Tab))
        case " ":
            return KeyStroke(key: "space", modifiers: [], keyCode: UInt16(kVK_Space))
        default:
            break
        }

        let char = Character(scalar)

        if char.isLetter {
            let lower = String(char).lowercased()
            guard let code = keyCode(for: lower) else { return nil }
            var mods: [String] = []
            if char.isUppercase { mods.append("shift") }
            let canonical = primaryKeyNames[code] ?? lower
            return KeyStroke(key: canonical, modifiers: mods, keyCode: code)
        }

        if let mapping = shiftedCharacterMap[char] {
            guard let code = keyCode(for: mapping.key) else { return nil }
            return KeyStroke(key: mapping.key, modifiers: mapping.modifiers, keyCode: code)
        }

        let string = String(char)
        if let code = keyCode(for: string) {
            let canonical = primaryKeyNames[code] ?? normalizeIdentifier(string)
            return KeyStroke(key: canonical, modifiers: [], keyCode: code)
        }

        return nil
    }

    private static func modifierSymbol(for modifier: String) -> String {
        modifierSymbolMap[modifier.lowercased()] ?? ""
    }

    private static func normalizeIdentifier(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let canonicalKeyCodes: [String: UInt16] = {
        var map: [String: UInt16] = [:]

        func add(_ names: [String], code: Int) {
            for name in names {
                map[name] = UInt16(code)
            }
        }

        let letters = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D),
            ("e", kVK_ANSI_E), ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H),
            ("i", kVK_ANSI_I), ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O), ("p", kVK_ANSI_P),
            ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z)
        ]
        for (name, code) in letters { add([name], code: code) }

        let digits = [
            ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9), ("0", kVK_ANSI_0)
        ]
        for (name, code) in digits { add([name], code: code) }

        add(["minus", "-"], code: kVK_ANSI_Minus)
        add(["equals", "=", "equal"], code: kVK_ANSI_Equal)
        add(["left bracket", "["], code: kVK_ANSI_LeftBracket)
        add(["right bracket", "]"], code: kVK_ANSI_RightBracket)
        add(["backslash", "\\"], code: kVK_ANSI_Backslash)
        add(["semicolon", ";"], code: kVK_ANSI_Semicolon)
        add(["quote", "'", "apostrophe"], code: kVK_ANSI_Quote)
        add(["comma", ","], code: kVK_ANSI_Comma)
        add(["period", "."], code: kVK_ANSI_Period)
        add(["slash", "/"], code: kVK_ANSI_Slash)
        add(["grave", "`", "tilde"], code: kVK_ANSI_Grave)

        add(["space"], code: kVK_Space)
        add(["return"], code: kVK_Return)
        add(["enter", "keypad enter"], code: kVK_ANSI_KeypadEnter)
        add(["tab"], code: kVK_Tab)
        add(["escape", "esc"], code: kVK_Escape)
        add(["delete", "backspace"], code: kVK_Delete)
        add(["forward delete", "fn delete", "del"], code: kVK_ForwardDelete)
        add(["caps lock", "capslock"], code: kVK_CapsLock)
        add(["help"], code: kVK_Help)
        add(["home"], code: kVK_Home)
        add(["end"], code: kVK_End)
        add(["page up"], code: kVK_PageUp)
        add(["page down"], code: kVK_PageDown)
        add(["left arrow", "left"], code: kVK_LeftArrow)
        add(["right arrow", "right"], code: kVK_RightArrow)
        add(["up arrow", "up"], code: kVK_UpArrow)
        add(["down arrow", "down"], code: kVK_DownArrow)

        add(["f1"], code: kVK_F1)
        add(["f2"], code: kVK_F2)
        add(["f3"], code: kVK_F3)
        add(["f4"], code: kVK_F4)
        add(["f5"], code: kVK_F5)
        add(["f6"], code: kVK_F6)
        add(["f7"], code: kVK_F7)
        add(["f8"], code: kVK_F8)
        add(["f9"], code: kVK_F9)
        add(["f10"], code: kVK_F10)
        add(["f11"], code: kVK_F11)
        add(["f12"], code: kVK_F12)
        add(["f13"], code: kVK_F13)
        add(["f14"], code: kVK_F14)
        add(["f15"], code: kVK_F15)
        add(["f16"], code: kVK_F16)
        add(["f17"], code: kVK_F17)
        add(["f18"], code: kVK_F18)
        add(["f19"], code: kVK_F19)
        add(["f20"], code: kVK_F20)

        add(["kp0", "keypad 0"], code: kVK_ANSI_Keypad0)
        add(["kp1", "keypad 1"], code: kVK_ANSI_Keypad1)
        add(["kp2", "keypad 2"], code: kVK_ANSI_Keypad2)
        add(["kp3", "keypad 3"], code: kVK_ANSI_Keypad3)
        add(["kp4", "keypad 4"], code: kVK_ANSI_Keypad4)
        add(["kp5", "keypad 5"], code: kVK_ANSI_Keypad5)
        add(["kp6", "keypad 6"], code: kVK_ANSI_Keypad6)
        add(["kp7", "keypad 7"], code: kVK_ANSI_Keypad7)
        add(["kp8", "keypad 8"], code: kVK_ANSI_Keypad8)
        add(["kp9", "keypad 9"], code: kVK_ANSI_Keypad9)
        add(["kp."], code: kVK_ANSI_KeypadDecimal)
        add(["kp*"], code: kVK_ANSI_KeypadMultiply)
        add(["kp+"], code: kVK_ANSI_KeypadPlus)
        add(["kp-"], code: kVK_ANSI_KeypadMinus)
        add(["kp/"], code: kVK_ANSI_KeypadDivide)
        add(["kp="], code: kVK_ANSI_KeypadEquals)

        return map
    }()

    private static let primaryKeyNames: [UInt16: String] = {
        var reverse: [UInt16: String] = [:]
        for (name, code) in canonicalKeyCodes where reverse[code] == nil {
            reverse[code] = name
        }
        return reverse
    }()

    private static let specialKeyNames: [UInt16: String] = [
        // macOS 专用系统功能键。数值与 Mos 的 SystemShortcut 定义一致，
        // 明确命名可避免菜单提示退化成“未知键（代码）”。
        160: "Mission Control",
        131: "Launchpad",
        177: "Spotlight",
        176: "Dictation",
        178: "Do Not Disturb",
        127: "Power",
        UInt16(kVK_Shift): "Shift",
        UInt16(kVK_Option): "Option",
        UInt16(kVK_Control): "Control",
        UInt16(kVK_Command): "Command",
        UInt16(kVK_Function): "Function",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_ANSI_KeypadEnter): "Enter",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Escape): "Escape",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_CapsLock): "Caps Lock",
        UInt16(kVK_Help): "Help",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20"
    ]

    private static let modifierSymbolMap: [String: String] = [
        "cmd": "⌘",
        "command": "⌘",
        "shift": "⇧",
        "alt": "⌥",
        "option": "⌥",
        "ctrl": "⌃",
        "control": "⌃",
        "fn": "fn"
    ]

    private static let shiftedCharacterMap: [Character: (key: String, modifiers: [String])] = [
        "!": ("1", ["shift"]),
        "@": ("2", ["shift"]),
        "#": ("3", ["shift"]),
        "$": ("4", ["shift"]),
        "%": ("5", ["shift"]),
        "^": ("6", ["shift"]),
        "&": ("7", ["shift"]),
        "*": ("8", ["shift"]),
        "(": ("9", ["shift"]),
        ")": ("0", ["shift"]),
        "_": ("minus", ["shift"]),
        "+": ("equal", ["shift"]),
        ":": ("semicolon", ["shift"]),
        "\"": ("quote", ["shift"]),
        "<": ("comma", ["shift"]),
        ">": ("period", ["shift"]),
        "?": ("slash", ["shift"]),
        "|": ("backslash", ["shift"]),
        "~": ("grave", ["shift"]),
        "{": ("left bracket", ["shift"]),
        "}": ("right bracket", ["shift"])
    ]
}

struct MacroStep: Equatable, Codable {
    var type: String // "key", "text", "delay"
    var keyStroke: KeyStroke? = nil
    var text: String? = nil
    var delayMs: Int? = nil
}
