import AppKit
import SwiftUI

struct HighlightedQuickAddTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRangeRequest: NSRange?

    let tokens: [QuickAddToken]
    let placeholder: String
    let onSubmit: () -> Void
    let onEscape: (NSRange) -> Bool

    func makeNSView(context: Context) -> HighlightedQuickAddTextFieldView {
        let view = HighlightedQuickAddTextFieldView()
        view.textView.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HighlightedQuickAddTextFieldView, context: Context) {
        context.coordinator.parent = self
        let selectionRequest = selectedRangeRequest
        let shouldRequestFocus = context.coordinator.consumeInitialFocusRequest() || selectionRequest != nil

        nsView.update(
            text: text,
            tokens: tokens,
            placeholder: placeholder,
            selectedRange: selectionRequest
        )

        DispatchQueue.main.async {
            if shouldRequestFocus {
                nsView.requestFocus()
            }

            if selectionRequest != nil {
                selectedRangeRequest = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedQuickAddTextField
        private var shouldRequestInitialFocus = true

        init(parent: HighlightedQuickAddTextField) {
            self.parent = parent
        }

        func consumeInitialFocusRequest() -> Bool {
            defer { shouldRequestInitialFocus = false }
            return shouldRequestInitialFocus
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                return parent.onEscape(textView.selectedRange())
            }

            return false
        }
    }
}

final class HighlightedQuickAddTextFieldView: NSView {
    let textView = NSTextView()

    private let scrollView = NSScrollView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    private var lastText = ""
    private var lastTokens: [QuickAddToken] = []
    private var hasPendingFocusRequest = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(
        text: String,
        tokens: [QuickAddToken],
        placeholder: String,
        selectedRange: NSRange?
    ) {
        placeholderLabel.stringValue = placeholder
        placeholderLabel.isHidden = !text.isEmpty

        if text != lastText || tokens != lastTokens {
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedString(for: text, tokens: tokens))
            textView.selectedRanges = clampedSelectedRanges(selectedRanges, textLength: (text as NSString).length)
            textView.scrollRangeToVisible(textView.selectedRange())

            lastText = text
            lastTokens = tokens
        }

        if let selectedRange {
            textView.setSelectedRange(clampedSelectedRange(selectedRange, textLength: (text as NSString).length))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    func requestFocus() {
        hasPendingFocusRequest = true
        applyPendingFocusRequest()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocusRequest()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 20, weight: .semibold)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byClipping
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = NSRect(origin: .zero, size: NSSize(width: bounds.width, height: 25))
        textView.autoresizingMask = [.height]
        scrollView.documentView = textView

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        placeholderLabel.textColor = .placeholderTextColor

        addSubview(scrollView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -1)
        ])
    }

    private func applyPendingFocusRequest() {
        guard hasPendingFocusRequest, let window else {
            return
        }

        hasPendingFocusRequest = false

        if window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    private func attributedString(for text: String, tokens: [QuickAddToken]) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let attributedString = NSMutableAttributedString(string: text)

        attributedString.addAttributes([
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ], range: fullRange)

        for token in tokens where NSMaxRange(token.range) <= fullRange.length {
            attributedString.addAttributes(attributes(for: token.kind), range: token.range)
        }

        return attributedString
    }

    private func attributes(for kind: QuickAddToken.Kind) -> [NSAttributedString.Key: Any] {
        let color: NSColor = switch kind {
        case .date, .time:
            .systemGreen
        case .list:
            .systemPurple
        case .tag:
            .systemOrange
        case .priority:
            .systemRed
        case .note:
            .systemBlue
        }

        return [
            .foregroundColor: color,
            .backgroundColor: color.withAlphaComponent(0.16)
        ]
    }

    private func clampedSelectedRanges(_ ranges: [NSValue], textLength: Int) -> [NSValue] {
        ranges.map { value in
            NSValue(range: clampedSelectedRange(value.rangeValue, textLength: textLength))
        }
    }

    private func clampedSelectedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = min(max(range.location, 0), textLength)
        let maxLength = textLength - location
        return NSRange(location: location, length: min(max(range.length, 0), maxLength))
    }
}
