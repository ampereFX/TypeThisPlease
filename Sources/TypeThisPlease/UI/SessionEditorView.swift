import AppKit
import SwiftUI

struct SessionEditorView: NSViewRepresentable {
    let segments: [EditorSegment]
    let onReplace: (NSRange, String, [RenderedEditorSegment]) -> Void
    let onFocusChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReplace: onReplace, onFocusChanged: onFocusChanged)
    }

    func makeNSView(context: Context) -> NSScrollView {
        DebugLog.log("makeNSView begin", category: "editor")
        let textStorage = NSTextStorage()
        let layoutManager = SegmentLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = FocusAwareTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.focusHandler = context.coordinator.handleFocusChanged(_:)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textContainer?.lineFragmentPadding = 4

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.update(segments: segments)
        DebugLog.log("makeNSView end", category: "editor")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        DebugLog.log("updateNSView segments=\(segments.count)", category: "editor")
        context.coordinator.update(segments: segments)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let onReplace: (NSRange, String, [RenderedEditorSegment]) -> Void
        private let onFocusChanged: (Bool) -> Void
        private(set) var renderedSegments: [RenderedEditorSegment] = []
        weak var textView: NSTextView?
        private var isApplyingProgrammaticUpdate = false
        private var pendingSelectionRange: NSRange?

        init(
            onReplace: @escaping (NSRange, String, [RenderedEditorSegment]) -> Void,
            onFocusChanged: @escaping (Bool) -> Void
        ) {
            self.onReplace = onReplace
            self.onFocusChanged = onFocusChanged
        }

        func update(segments: [EditorSegment]) {
            guard let textView else { return }
            DebugLog.log("Coordinator.update begin segments=\(segments.count)", category: "editor")
            let selectedRange = pendingSelectionRange ?? textView.selectedRange()
            isApplyingProgrammaticUpdate = true
            let rendered = Self.makeAttributedString(from: segments)
            renderedSegments = rendered.segments
            textView.textStorage?.setAttributedString(rendered.text)
            let upperBound = rendered.text.length
            let clampedRange = NSRange(
                location: min(selectedRange.location, upperBound),
                length: min(selectedRange.length, max(0, upperBound - min(selectedRange.location, upperBound)))
            )
            textView.setSelectedRange(clampedRange)
            isApplyingProgrammaticUpdate = false
            pendingSelectionRange = nil
            DebugLog.log("Coordinator.update end rendered=\(renderedSegments.count) length=\(rendered.text.length)", category: "editor")
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isApplyingProgrammaticUpdate else { return true }
            let replacement = replacementString ?? ""
            pendingSelectionRange = NSRange(location: affectedCharRange.location + (replacement as NSString).length, length: 0)
            onReplace(affectedCharRange, replacement, renderedSegments)
            return false
        }

        func handleFocusChanged(_ isFocused: Bool) {
            onFocusChanged(isFocused)
        }

        private static func makeAttributedString(from segments: [EditorSegment]) -> (text: NSAttributedString, segments: [RenderedEditorSegment]) {
            DebugLog.log("makeAttributedString begin segments=\(segments.count)", category: "editor")
            let attributed = NSMutableAttributedString()
            var rendered: [RenderedEditorSegment] = []
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 6

            for segment in segments {
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: segment.isEditable ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 16, weight: segment.isEditable ? .medium : .semibold),
                    .sessionSegmentStyle: SegmentVisualStyle(kind: segment.kind),
                    .paragraphStyle: paragraphStyle
                ]
                let location = attributed.length
                attributed.append(NSAttributedString(string: segment.text, attributes: attributes))
                rendered.append(
                    RenderedEditorSegment(
                        id: segment.id,
                        kind: segment.kind,
                        range: NSRange(location: location, length: (segment.text as NSString).length),
                        text: segment.text
                    )
                )
            }

            if attributed.length == 0 {
                attributed.append(
                    NSAttributedString(
                        string: "",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                )
            }

            DebugLog.log("makeAttributedString end rendered=\(rendered.count) length=\(attributed.length)", category: "editor")
            return (attributed, rendered)
        }
    }
}

private final class FocusAwareTextView: NSTextView {
    var focusHandler: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            focusHandler?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            focusHandler?(false)
        }
        return accepted
    }
}

private final class SegmentVisualStyle: NSObject {
    let fillColor: NSColor
    let strokeColor: NSColor

    init(kind: EditorSegmentKind) {
        switch kind {
        case .transcript:
            fillColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
            strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.34)
        case .manual:
            fillColor = NSColor.white.withAlphaComponent(0.08)
            strokeColor = NSColor.white.withAlphaComponent(0.2)
        case .transcribing:
            fillColor = NSColor.systemOrange.withAlphaComponent(0.14)
            strokeColor = NSColor.systemOrange.withAlphaComponent(0.34)
        case .recording:
            fillColor = NSColor.systemRed.withAlphaComponent(0.14)
            strokeColor = NSColor.systemRed.withAlphaComponent(0.34)
        }
    }
}

private final class SegmentLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.sessionSegmentStyle, in: characterRange, options: []) { value, range, _ in
            guard let style = value as? SegmentVisualStyle else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            self.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                var highlightRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                highlightRect = highlightRect.insetBy(dx: -2, dy: -1)
                let path = NSBezierPath(roundedRect: highlightRect, xRadius: 10, yRadius: 10)
                style.fillColor.setFill()
                path.fill()
                style.strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
}

private extension NSAttributedString.Key {
    static let sessionSegmentStyle = NSAttributedString.Key("TypeThisPleaseSessionSegmentStyle")
}
