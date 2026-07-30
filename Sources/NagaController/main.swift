import Cocoa
import Darwin

if CommandLine.arguments.contains("--self-test-hid-codec") {
    let failures = HIDCodecSelfTest.run()
    if failures.isEmpty {
        print("HID codec self-test: PASS")
        exit(0)
    }
    for failure in failures { fputs("HID codec self-test: FAIL — \(failure)\n", stderr) }
    exit(1)
}

let app = NSApplication.shared
let isPopoverPreview = CommandLine.arguments.contains("--preview-popover-ui")
let isMainPreview = CommandLine.arguments.contains("--preview-main-ui")
let isHardwarePreview = CommandLine.arguments.contains("--preview-hardware-ui")
let isMappingPreview = CommandLine.arguments.contains("--preview-mapping-ui")
    || Bundle.main.bundleIdentifier == "com.example.NagaMappingPreview"
let isScrollPreview = CommandLine.arguments.contains("--preview-scroll-ui")
    || (CommandLine.arguments.first?.contains("NagaScrollPreview") ?? false)
    || Bundle.main.bundleIdentifier == "com.example.NagaScrollPreview"
let isTutorialPreview = CommandLine.arguments.contains("--preview-tutorial-ui")
let isPermissionPreview = CommandLine.arguments.contains("--preview-permission-ui")
let delegate: NSApplicationDelegate = (isPopoverPreview || isMainPreview || isHardwarePreview || isMappingPreview || isScrollPreview || isTutorialPreview || isPermissionPreview)
    ? UIPreviewAppDelegate(mode: isPermissionPreview ? .permission : (isPopoverPreview ? .popover : (isMainPreview ? .main : (isMappingPreview ? .mapping : (isScrollPreview ? .scroll : (isTutorialPreview ? .tutorial : .hardware))))))
    : AppDelegate()
app.delegate = delegate
app.run()
