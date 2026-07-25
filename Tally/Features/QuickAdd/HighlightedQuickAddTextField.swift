import AppKit
import SwiftUI

struct QuickAddNotesField: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let focusRequestID: Int
    let onSubmit: () -> Void
    let onForwardTab: () -> Void
    let onBackwardTab: () -> Void

    func makeNSView(context: Context) -> QuickAddWrappingTextEditorView {
        let view = QuickAddWrappingTextEditorView(
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor,
            minimumHeight: 24,
            maximumHeight: 56,
            verticalInset: 3
        )
        view.textView.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: QuickAddWrappingTextEditorView, context: Context) {
        context.coordinator.parent = self
        view.onHeightChange = { height in
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = height
            }
        }

        view.update(
            attributedText: NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            ),
            placeholder: "Notes",
            selectedRange: nil
        )

        if context.coordinator.consumeFocusRequest(focusRequestID) {
            DispatchQueue.main.async {
                view.requestFocus()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickAddNotesField
        private var lastFocusRequestID = 0

        init(parent: QuickAddNotesField) {
            self.parent = parent
        }

        func consumeFocusRequest(_ focusRequestID: Int) -> Bool {
            guard focusRequestID != lastFocusRequestID else {
                return false
            }

            lastFocusRequestID = focusRequestID
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
            (textView.enclosingScrollView?.superview as? QuickAddWrappingTextEditorView)?
                .synchronizeAfterEditing()
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                collapseSelectionIfNeeded(in: textView)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onForwardTab()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                collapseSelectionIfNeeded(in: textView)
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onBackwardTab()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)),
               NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                parent.onSubmit()
                return true
            }

            return false
        }

        private func collapseSelectionIfNeeded(in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else {
                return
            }

            textView.setSelectedRange(
                NSRange(location: NSMaxRange(selectedRange), length: 0)
            )
        }
    }
}

struct HighlightedQuickAddTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRangeRequest: NSRange?
    @Binding var measuredHeight: CGFloat

    let tokens: [QuickAddToken]
    let placeholder: String
    let onSubmit: () -> Void
    let onEscape: () -> Bool
    let onForwardTab: () -> Void
    let onBackwardTab: () -> Void

    func makeNSView(context: Context) -> QuickAddWrappingTextEditorView {
        let view = QuickAddWrappingTextEditorView(
            font: .systemFont(ofSize: 20, weight: .semibold),
            textColor: .labelColor,
            minimumHeight: 28,
            maximumHeight: 76,
            verticalInset: 1
        )
        view.textView.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: QuickAddWrappingTextEditorView, context: Context) {
        context.coordinator.parent = self
        let selectionRequest = selectedRangeRequest
        let shouldRequestFocus = context.coordinator.consumeInitialFocusRequest() || selectionRequest != nil

        view.onHeightChange = { height in
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = height
            }
        }
        view.update(
            attributedText: attributedString(for: text, tokens: tokens),
            placeholder: placeholder,
            selectedRange: selectionRequest
        )

        DispatchQueue.main.async {
            if shouldRequestFocus {
                view.requestFocus()
            }

            if selectionRequest != nil {
                selectedRangeRequest = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
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
            .systemBlue
        case .list:
            .systemIndigo
        case .tag:
            .systemTeal
        case .priority:
            .systemOrange
        case .note:
            .secondaryLabelColor
        }

        return [
            .foregroundColor: color,
            .backgroundColor: color.withAlphaComponent(kind == .note ? 0.08 : 0.11)
        ]
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
            (textView.enclosingScrollView?.superview as? QuickAddWrappingTextEditorView)?
                .synchronizeAfterEditing()
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
                return parent.onEscape()
            }

            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                collapseSelectionIfNeeded(in: textView)
                parent.onForwardTab()
                return true
            }

            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                collapseSelectionIfNeeded(in: textView)
                parent.onBackwardTab()
                return true
            }

            return false
        }

        private func collapseSelectionIfNeeded(in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length > 0 else {
                return
            }

            textView.setSelectedRange(
                NSRange(location: NSMaxRange(selectedRange), length: 0)
            )
        }
    }
}

final class QuickAddWrappingTextEditorView: NSView {
    fileprivate let textView = QuickAddTitleTextView()

    private let scrollView = NSScrollView()
    private let placeholderLabel = QuickAddPlaceholderLabel(labelWithString: "")
    private let editorFont: NSFont
    private let editorTextColor: NSColor
    private let minimumHeight: CGFloat
    private let maximumHeight: CGFloat
    private let verticalInset: CGFloat
    private var lastAttributedText = NSAttributedString()
    private var lastReportedHeight: CGFloat?
    private var hasPendingFocusRequest = false
    private var shouldRevealSelection = false

    var onHeightChange: ((CGFloat) -> Void)? {
        didSet {
            needsLayout = true
        }
    }

    init(
        font: NSFont,
        textColor: NSColor,
        minimumHeight: CGFloat,
        maximumHeight: CGFloat,
        verticalInset: CGFloat
    ) {
        editorFont = font
        editorTextColor = textColor
        self.minimumHeight = minimumHeight
        self.maximumHeight = maximumHeight
        self.verticalInset = verticalInset
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        attributedText: NSAttributedString,
        placeholder: String,
        selectedRange: NSRange?
    ) {
        placeholderLabel.stringValue = placeholder
        placeholderLabel.isHidden = attributedText.length > 0

        if !lastAttributedText.isEqual(to: attributedText) {
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            textView.selectedRanges = clampedSelectedRanges(
                selectedRanges,
                textLength: attributedText.length
            )

            lastAttributedText = attributedText.copy() as? NSAttributedString ?? attributedText
            shouldRevealSelection = true
            needsLayout = true
        }

        if let selectedRange {
            textView.setSelectedRange(
                clampedSelectedRange(selectedRange, textLength: attributedText.length)
            )
            shouldRevealSelection = true
            needsLayout = true
        }
    }

    func synchronizeAfterEditing() {
        placeholderLabel.isHidden = !textView.string.isEmpty
        lastAttributedText = textView.attributedString()
        shouldRevealSelection = true
        needsLayout = true
    }

    func requestFocus() {
        hasPendingFocusRequest = true
        applyPendingFocusRequest()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingFocusRequest()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        requestFocus()
    }

    override func layout() {
        super.layout()

        let viewportWidth = max(1, scrollView.contentSize.width)
        if abs(textView.frame.width - viewportWidth) > 0.5 {
            textView.setFrameSize(
                NSSize(width: viewportWidth, height: textView.frame.height)
            )
        }

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager
        else {
            return
        }

        textContainer.containerSize = NSSize(
            width: viewportWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let laidOutHeight = ceil(layoutManager.usedRect(for: textContainer).height)
            + verticalInset * 2
        let preferredHeight = min(max(laidOutHeight, minimumHeight), maximumHeight)
        let documentHeight = max(laidOutHeight, scrollView.contentSize.height)

        textView.minSize = NSSize(width: viewportWidth, height: minimumHeight)
        textView.maxSize = NSSize(width: viewportWidth, height: CGFloat.greatestFiniteMagnitude)
        if abs(textView.frame.height - documentHeight) > 0.5 {
            textView.setFrameSize(
                NSSize(width: viewportWidth, height: documentHeight)
            )
        }

        updateScrollPosition(contentHeight: laidOutHeight)
        reportHeightIfNeeded(preferredHeight)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = editorFont
        textView.textColor = editorTextColor
        textView.insertionPointColor = .labelColor
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor
        ]
        textView.typingAttributes = [
            .font: editorFont,
            .foregroundColor: editorTextColor
        ]
        textView.textContainerInset = NSSize(width: 0, height: verticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = NSSize(
            width: max(1, bounds.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: minimumHeight)
        textView.maxSize = NSSize(
            width: max(1, bounds.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: max(1, bounds.width), height: minimumHeight)
        )
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = editorFont
        placeholderLabel.textColor = .placeholderTextColor

        addSubview(scrollView)
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: maximumHeight),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            placeholderLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: verticalInset
            )
        ])
    }

    private func updateScrollPosition(contentHeight: CGFloat) {
        guard contentHeight > maximumHeight else {
            if scrollView.contentView.bounds.origin != .zero {
                scrollView.contentView.scroll(to: .zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            shouldRevealSelection = false
            return
        }

        guard shouldRevealSelection else {
            return
        }

        shouldRevealSelection = false
        textView.scrollRangeToVisible(textView.selectedRange())
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

    private func reportHeightIfNeeded(_ height: CGFloat) {
        guard onHeightChange != nil,
              lastReportedHeight.map({ abs($0 - height) > 0.5 }) ?? true
        else {
            return
        }

        lastReportedHeight = height
        DispatchQueue.main.async { [weak self] in
            self?.onHeightChange?(height)
        }
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

fileprivate final class QuickAddTitleTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resignFirstResponder() -> Bool {
        collapseSelectionIfNeeded()
        return super.resignFirstResponder()
    }

    private func collapseSelectionIfNeeded() {
        let range = selectedRange()
        guard range.length > 0 else {
            return
        }

        setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }
}

private final class QuickAddPlaceholderLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
