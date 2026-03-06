import AppKit
import ApplicationServices
import Foundation

struct OutputDeliveryResult: Equatable {
    let copiedToClipboard: Bool
    let pastedIntoFrontmostApp: Bool
    let usedFallback: Bool

    var message: String {
        if pastedIntoFrontmostApp {
            return "Transcript copied and pasted."
        }
        if copiedToClipboard {
            return usedFallback ? "Transcript copied. Auto-paste needs Accessibility permission." : "Transcript copied."
        }
        return "Transcript not delivered."
    }
}

@MainActor
final class OutputService {
    func deliver(text: String, action: OutputAction) -> OutputDeliveryResult {
        guard !text.isEmpty else {
            return OutputDeliveryResult(copiedToClipboard: false, pastedIntoFrontmostApp: false, usedFallback: false)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)

        switch action {
        case .copy:
            return OutputDeliveryResult(copiedToClipboard: copied, pastedIntoFrontmostApp: false, usedFallback: false)
        case .copyAndPaste:
            let pasted = copied && pasteClipboardContents()
            return OutputDeliveryResult(copiedToClipboard: copied, pastedIntoFrontmostApp: pasted, usedFallback: copied && !pasted)
        }
    }

    private func pasteClipboardContents() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return true
    }
}
