import Cocoa

class MacKeyboardView: NSView {
    
    // Callbacks
    var onKeySelected: ((KeyStroke) -> Void)?
    
    // State
    private var activeModifiers: Set<String> = []
    private var modifierButtons: [NSButton] = []
    
    // Define the keyboard layout
    private let layout: [[(label: String, keyName: String, width: CGFloat, isModifier: Bool)]] = [
        // Row 0: extended function keys and navigation cluster
        [("f13", "f13", 34, false), ("f14", "f14", 34, false), ("f15", "f15", 34, false), ("f16", "f16", 34, false),
         ("f17", "f17", 34, false), ("f18", "f18", 34, false), ("f19", "f19", 34, false), ("f20", "f20", 34, false),
         ("home", "home", 46, false), ("end", "end", 40, false), ("pg↑", "page up", 38, false), ("pg↓", "page down", 38, false), ("del→", "forward delete", 44, false)],
        // Row 1
        [("esc", "escape", 40, false), ("f1", "f1", 30, false), ("f2", "f2", 30, false), ("f3", "f3", 30, false), ("f4", "f4", 30, false),
         ("f5", "f5", 30, false), ("f6", "f6", 30, false), ("f7", "f7", 30, false), ("f8", "f8", 30, false),
         ("f9", "f9", 30, false), ("f10", "f10", 30, false), ("f11", "f11", 30, false), ("f12", "f12", 30, false)],
        // Row 2
        [("~", "`", 30, false), ("1", "1", 30, false), ("2", "2", 30, false), ("3", "3", 30, false), ("4", "4", 30, false),
         ("5", "5", 30, false), ("6", "6", 30, false), ("7", "7", 30, false), ("8", "8", 30, false),
         ("9", "9", 30, false), ("0", "0", 30, false), ("-", "-", 30, false), ("=", "=", 30, false), ("delete", "delete", 50, false)],
        // Row 3
        [("tab", "tab", 45, false), ("q", "q", 30, false), ("w", "w", 30, false), ("e", "e", 30, false), ("r", "r", 30, false),
         ("t", "t", 30, false), ("y", "y", 30, false), ("u", "u", 30, false), ("i", "i", 30, false),
         ("o", "o", 30, false), ("p", "p", 30, false), ("[", "[", 30, false), ("]", "]", 30, false), ("\\", "\\", 35, false)],
        // Row 4
        [("caps", "capslock", 55, false), ("a", "a", 30, false), ("s", "s", 30, false), ("d", "d", 30, false), ("f", "f", 30, false),
         ("g", "g", 30, false), ("h", "h", 30, false), ("j", "j", 30, false), ("k", "k", 30, false),
         ("l", "l", 30, false), (";", ";", 30, false), ("'", "'", 30, false), ("return", "return", 55, false)],
        // Row 5
        [("shift", "shift", 70, true), ("z", "z", 30, false), ("x", "x", 30, false), ("c", "c", 30, false), ("v", "v", 30, false),
         ("b", "b", 30, false), ("n", "n", 30, false), ("m", "m", 30, false), (",", ",", 30, false),
         (".", ".", 30, false), ("/", "/", 30, false), ("shift", "shift", 70, true)],
        // Row 6
        [("fn", "fn", 36, true), ("ctrl", "ctrl", 40, true), ("opt", "opt", 40, true), ("cmd", "cmd", 50, true), ("space", "space", 150, false),
         ("cmd", "cmd", 50, true), ("opt", "opt", 40, true), ("◀", "left arrow", 30, false),
         ("▲", "up arrow", 30, false), ("▼", "down arrow", 30, false), ("▶", "right arrow", 30, false)]
    ]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 4
        mainStack.alignment = .centerX
        
        for row in layout {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 4
            rowStack.alignment = .centerY
            
            for keyInfo in row {
                let btn = NSButton(title: keyInfo.label, target: self, action: #selector(keyTapped(_:)))
                btn.bezelStyle = .shadowlessSquare
                btn.isBordered = true
                btn.font = .systemFont(ofSize: 13)
                
                // Keep track of the key metadata
                btn.identifier = NSUserInterfaceItemIdentifier(keyInfo.keyName)
                btn.setButtonType(keyInfo.isModifier ? .pushOnPushOff : .momentaryLight)
                
                // Sizing
                btn.translatesAutoresizingMaskIntoConstraints = false
                btn.widthAnchor.constraint(equalToConstant: keyInfo.width).isActive = true
                btn.heightAnchor.constraint(equalToConstant: 30).isActive = true
                
                if keyInfo.isModifier {
                    modifierButtons.append(btn)
                }
                
                rowStack.addArrangedSubview(btn)
            }
            mainStack.addArrangedSubview(rowStack)
        }
        
        self.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainStack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            mainStack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            mainStack.topAnchor.constraint(equalTo: self.topAnchor, constant: 10),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -10),
            mainStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
            mainStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10)
        ])
    }
    
    @objc private func keyTapped(_ sender: NSButton) {
        guard let keyName = sender.identifier?.rawValue else { return }
        
        let isModifier = layout.flatMap { $0 }.first { $0.keyName == keyName }?.isModifier ?? false
        
        if isModifier {
            // Left/right buttons intentionally emit the same semantic modifier,
            // but their visual toggle state is independent. Recompute from all
            // active buttons so turning off left Shift does not clear right
            // Shift while it is still visibly on.
            activeModifiers = Set(modifierButtons.compactMap { button in
                guard button.state == .on else { return nil }
                return button.identifier?.rawValue
            })
        } else {
            // Emitting keystroke
            let modsToPass = Array(activeModifiers)
            let stroke = KeyStroke(key: keyName, modifiers: modsToPass, keyCode: KeyStroke.keyCode(for: keyName))
            onKeySelected?(stroke)
            
            // Auto reset modifiers after regular key press
            activeModifiers.removeAll()
            for mBtn in modifierButtons {
                mBtn.state = .off
            }
        }
    }
}
