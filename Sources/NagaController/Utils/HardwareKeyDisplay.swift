import ApplicationServices
import Carbon.HIToolbox

enum HardwareKeyDisplay {
    static func keyboard(keyCode: Int, modifierFlags: UInt64) -> String {
        let eventFlags = CGEventFlags(rawValue: modifierFlags)
        var prefix = ""
        if eventFlags.contains(.maskControl) { prefix += "⌃" }
        if eventFlags.contains(.maskAlternate) { prefix += "⌥" }
        if eventFlags.contains(.maskShift) { prefix += "⇧" }
        if eventFlags.contains(.maskCommand) { prefix += "⌘" }
        if eventFlags.contains(.maskSecondaryFn) { prefix += "fn+" }
        let code = UInt16(clamping: keyCode)
        let value = prefix + KeyStroke.displayName(for: code)
        guard let meaning = localizedMeaning(keyCode: code, flags: eventFlags) else { return value }
        return "\(value)（\(meaning)）"
    }

    static func system(usagePage: UInt32, usage: UInt32) -> String {
        if usagePage == 0x0c {
            let definition: (String, String)?
            switch usage {
            case 0x00b5: definition = ("Next Track", "下一曲")
            case 0x00b6: definition = ("Previous Track", "上一曲")
            case 0x00b7: definition = ("Stop", "停止播放")
            case 0x00cd: definition = ("Play/Pause", "播放/暂停")
            case 0x00e2: definition = ("Mute", "静音")
            case 0x00e9: definition = ("Volume Up", "提高音量")
            case 0x00ea: definition = ("Volume Down", "降低音量")
            case 0x0223: definition = ("Home", "主页")
            case 0x0224: definition = ("Back", "后退")
            case 0x0225: definition = ("Forward", "前进")
            default: definition = nil
            }
            if let definition { return "\(definition.0)（\(L10n.text(definition.1))）" }
        }
        if usagePage == 0x01 {
            switch usage {
            case 0x81: return "System Power（\(L10n.text("系统电源"))）"
            case 0x82: return "System Sleep（\(L10n.text("系统睡眠"))）"
            case 0x83: return "System Wake（\(L10n.text("唤醒系统"))）"
            default: break
            }
        }
        return L10n.text("系统功能键（未识别定义）")
    }

    private static func localizedMeaning(keyCode: UInt16, flags: CGEventFlags) -> String? {
        let relevant = flags.intersection([
            .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn
        ])
        let command = relevant.contains(.maskCommand)
        let shift = relevant.contains(.maskShift)
        let option = relevant.contains(.maskAlternate)
        let control = relevant.contains(.maskControl)

        if let number = functionKeyNumber(for: Int(keyCode)) {
            return L10n.format("F%d 功能键", number)
        }

        if command && !option && !control {
            switch Int(keyCode) {
            case kVK_ANSI_C where !shift: return L10n.text("复制")
            case kVK_ANSI_V where !shift: return L10n.text("粘贴")
            case kVK_ANSI_X where !shift: return L10n.text("剪切")
            case kVK_ANSI_A where !shift: return L10n.text("全选")
            case kVK_ANSI_Z where shift: return L10n.text("重做")
            case kVK_ANSI_Z: return L10n.text("撤销")
            case kVK_ANSI_Y where !shift: return L10n.text("重做，仅部分应用")
            case kVK_ANSI_S where !shift: return L10n.text("保存")
            case kVK_ANSI_F where !shift: return L10n.text("查找")
            case kVK_ANSI_P where !shift: return L10n.text("打印")
            case kVK_ANSI_N where !shift: return L10n.text("新建")
            case kVK_ANSI_O where !shift: return L10n.text("打开")
            case kVK_ANSI_W where !shift: return L10n.text("关闭窗口")
            case kVK_ANSI_Q where !shift: return L10n.text("退出应用")
            case kVK_ANSI_T where !shift: return L10n.text("新建标签页")
            case kVK_ANSI_R where !shift: return L10n.text("刷新/重新载入")
            default: break
            }
        }

        // Special keys keep the same physical meaning even with fn. Avoid
        // guessing context-dependent meanings for arbitrary modified letters.
        switch Int(keyCode) {
        case kVK_Return: return L10n.text("回车")
        case kVK_ANSI_KeypadEnter: return L10n.text("小键盘回车")
        case kVK_Delete: return L10n.text("删除")
        case kVK_ForwardDelete: return L10n.text("向前删除")
        case kVK_Escape: return L10n.text("取消/退出")
        case kVK_Tab: return L10n.text("制表/切换焦点")
        case kVK_Space: return L10n.text("空格")
        case kVK_CapsLock: return L10n.text("大写锁定")
        case kVK_Home: return L10n.text("开头")
        case kVK_End: return L10n.text("末尾")
        case kVK_PageUp: return L10n.text("向上翻页")
        case kVK_PageDown: return L10n.text("向下翻页")
        case kVK_LeftArrow: return L10n.text("左方向键")
        case kVK_RightArrow: return L10n.text("右方向键")
        case kVK_UpArrow: return L10n.text("上方向键")
        case kVK_DownArrow: return L10n.text("下方向键")
        default:
            return nil
        }
    }

    private static func functionKeyNumber(for keyCode: Int) -> Int? {
        let values = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5,
            kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
            kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
        ]
        return values.firstIndex(of: keyCode).map { $0 + 1 }
    }
}
