import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey

    func makeNSView(context: Context) -> HotKeyRecorderControl {
        let control = HotKeyRecorderControl()
        control.onHotKeyChanged = { recordedHotKey in
            context.coordinator.onChange(recordedHotKey)
        }
        control.hotKey = hotKey
        return control
    }

    func updateNSView(_ nsView: HotKeyRecorderControl, context: Context) {
        nsView.hotKey = hotKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: { hotKey = $0 })
    }

    final class Coordinator {
        let onChange: (HotKey) -> Void

        init(onChange: @escaping (HotKey) -> Void) {
            self.onChange = onChange
        }
    }
}

final class HotKeyRecorderControl: NSControl {
    var hotKey: HotKey = .defaultRecording {
        didSet { needsDisplay = true }
    }

    var onHotKeyChanged: ((HotKey) -> Void)?

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }
        guard let hotKey = HotKey(event: event) else {
            NSSound.beep()
            return
        }
        self.hotKey = hotKey
        onHotKeyChanged?(hotKey)
        isRecording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.windowBackgroundColor).setFill()
        background.fill()

        let title = isRecording ? "Press shortcut…" : hotKey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        title.draw(at: point, withAttributes: attributes)
    }
}
