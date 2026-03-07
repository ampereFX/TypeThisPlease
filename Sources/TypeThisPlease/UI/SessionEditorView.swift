import AppKit
import SwiftUI

struct SessionEditorView: NSViewRepresentable {
    let segments: [EditorSegment]
    let isInteractive: Bool
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
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
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
        textView.textContainerInset = NSSize(width: 24, height: 24)
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
        
        if let textView = scrollView.documentView as? NSTextView {
            textView.isSelectable = isInteractive
            textView.isEditable = isInteractive
            if !isInteractive {
                if textView.window?.firstResponder == textView {
                    textView.window?.makeFirstResponder(nil)
                }
            }
        }
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
            paragraphStyle.lineSpacing = 16
            paragraphStyle.paragraphSpacing = 16

            for (index, segment) in segments.enumerated() {
                // Add an unstyled space before the segment if needed to separate backgrounds
                if index > 0 && !segment.text.hasPrefix(" ") && !segments[index - 1].text.hasSuffix(" ") {
                    attributed.append(NSAttributedString(string: " ", attributes: [
                        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                        .paragraphStyle: paragraphStyle
                    ]))
                }

                let style = SegmentVisualStyle(kind: segment.kind, id: segment.id)
                let attributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: segment.isEditable ? NSColor.labelColor : NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 16, weight: segment.isEditable ? .medium : .semibold),
                    .sessionSegmentStyle: style,
                    .paragraphStyle: paragraphStyle
                ]
                
                let location = attributed.length
                
                let textToAppend = segment.text
                attributed.append(NSAttributedString(string: textToAppend, attributes: attributes))
                
                rendered.append(
                    RenderedEditorSegment(
                        id: segment.id,
                        kind: segment.kind,
                        range: NSRange(location: location, length: (textToAppend as NSString).length),
                        text: textToAppend
                    )
                )
            }

            if attributed.length == 0 {
                attributed.append(
                    NSAttributedString(
                        string: "",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
                            .foregroundColor: NSColor.labelColor,
                            .paragraphStyle: paragraphStyle
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

private enum SegmentVisualKind: String {
    case transcript
    case manual
    case transcribing
    case recording

    init(kind: EditorSegmentKind) {
        switch kind {
        case .transcript: self = .transcript
        case .manual: self = .manual
        case .transcribing: self = .transcribing
        case .recording: self = .recording
        }
    }

    var fillColor: NSColor {
        switch self {
        case .transcript: return NSColor.controlAccentColor.withAlphaComponent(0.14)
        case .manual: return NSColor.systemPurple.withAlphaComponent(0.14)
        case .transcribing: return NSColor.systemOrange.withAlphaComponent(0.14)
        case .recording: return NSColor.systemRed.withAlphaComponent(0.14)
        }
    }

    var strokeColor: NSColor {
        switch self {
        case .transcript: return NSColor.controlAccentColor.withAlphaComponent(0.34)
        case .manual: return NSColor.systemPurple.withAlphaComponent(0.34)
        case .transcribing: return NSColor.systemOrange.withAlphaComponent(0.34)
        case .recording: return NSColor.systemRed.withAlphaComponent(0.34)
        }
    }
}

private final class SegmentVisualStyle: NSObject {
    let kind: SegmentVisualKind
    let id: UUID

    init(kind: EditorSegmentKind, id: UUID) {
        self.kind = SegmentVisualKind(kind: kind)
        self.id = id
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SegmentVisualStyle else { return false }
        return self.id == other.id
    }

    override var hash: Int {
        return id.hashValue
    }
}

private final class SegmentLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let storage = textStorage, let textContainer = textContainers.first else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        storage.enumerateAttribute(.sessionSegmentStyle, in: characterRange, options: []) { value, range, _ in
            guard let style = value as? SegmentVisualStyle else { return }
            
            // Find the precise range of non-whitespace characters to highlight
            var startIdx = range.location
            var endIdx = NSMaxRange(range)
            let nsStr = storage.string as NSString
            
            while startIdx < endIdx {
                let char = nsStr.character(at: startIdx)
                if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(char)!) {
                    startIdx += 1
                } else {
                    break
                }
            }
            
            while endIdx > startIdx {
                let char = nsStr.character(at: endIdx - 1)
                if CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(char)!) {
                    endIdx -= 1
                } else {
                    break
                }
            }
            
            if startIdx >= endIdx { return }
            
            let trimmedRange = NSRange(location: startIdx, length: endIdx - startIdx)
            let glyphRange = self.glyphRange(forCharacterRange: trimmedRange, actualCharacterRange: nil)

            // Iterate through each line fragment individually to draw separate boxes
            var lineFragmentRects: [NSRect] = []
            
            var index = glyphRange.location
            let maxIndex = NSMaxRange(glyphRange)
            
            while index < maxIndex {
                var effectiveRange = NSRange(location: 0, length: 0)
                _ = self.lineFragmentRect(forGlyphAt: index, effectiveRange: &effectiveRange)
                
                // Find the intersection of this line fragment with our glyph range
                let intersection = NSIntersectionRange(effectiveRange, glyphRange)
                if intersection.length > 0 {
                    let boundingRect = self.boundingRect(forGlyphRange: intersection, in: textContainer)
                    lineFragmentRects.append(boundingRect)
                }
                
                index = NSMaxRange(effectiveRange)
            }

            for rect in lineFragmentRects {
                var highlightRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                
                // Add padding around the text inside the bounds
                highlightRect.origin.x -= 4
                highlightRect.size.width += 8
                highlightRect.origin.y -= 2
                highlightRect.size.height += 4
                
                let path = NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4)
                style.kind.fillColor.setFill()
                path.fill()
                style.kind.strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }
}

private extension NSAttributedString.Key {
    static let sessionSegmentStyle = NSAttributedString.Key("TypeThisPleaseSessionSegmentStyle")
}
