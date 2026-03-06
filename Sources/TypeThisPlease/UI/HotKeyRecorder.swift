import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    let hotKey: HotKey?
    let onHotKeyChanged: (HotKey?) -> Bool
    let onCaptureChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderControl {
        let control = HotKeyRecorderControl()
        control.onHotKeyChanged = { recordedHotKey in
            context.coordinator.onChange(recordedHotKey)
        }
        control.onCaptureChanged = { isCapturing in
            context.coordinator.onCaptureChanged(isCapturing)
        }
        control.hotKey = hotKey
        return control
    }

    func updateNSView(_ nsView: HotKeyRecorderControl, context: Context) {
        nsView.hotKey = hotKey
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onHotKeyChanged, onCaptureChanged: onCaptureChanged)
    }

    final class Coordinator {
        let onChange: (HotKey?) -> Bool
        let onCaptureChanged: (Bool) -> Void

        init(onChange: @escaping (HotKey?) -> Bool, onCaptureChanged: @escaping (Bool) -> Void) {
            self.onChange = onChange
            self.onCaptureChanged = onCaptureChanged
        }
    }
}

final class HotKeyRecorderControl: NSControl {
    private static weak var activeRecorder: HotKeyRecorderControl?

    var hotKey: HotKey? {
        didSet { needsDisplay = true }
    }

    var onHotKeyChanged: ((HotKey?) -> Bool)?
    var onCaptureChanged: ((Bool) -> Void)?

    private var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            needsDisplay = true
            onCaptureChanged?(isRecording)
        }
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
        if Self.activeRecorder !== self {
            Self.activeRecorder?.stopRecording()
            Self.activeRecorder = self
        }
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            hotKey = nil
            _ = onHotKeyChanged?(nil)
            stopRecording()
            return
        }
        guard let hotKey = HotKey(event: event) else {
            NSSound.beep()
            return
        }
        guard onHotKeyChanged?(hotKey) ?? false else {
            stopRecording()
            return
        }
        self.hotKey = hotKey
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.windowBackgroundColor).setFill()
        background.fill()

        let title = isRecording ? "Press shortcut…" : (hotKey?.displayString ?? "Not set")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        title.draw(at: point, withAttributes: attributes)
    }

    private func stopRecording() {
        isRecording = false
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
    }
}
