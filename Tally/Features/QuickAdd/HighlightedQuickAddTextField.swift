import AppKit
import SwiftUI

struct HighlightedQuickAddTextField: NSViewRepresentable {
    @Binding var text: String

    let tokens: [QuickAddToken]
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> HighlightedQuickAddTextFieldView {
        let view = HighlightedQuickAddTextFieldView()
        view.textView.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: HighlightedQuickAddTextFieldView, context: Context) {
        context.coordinator.parent = self
        nsView.update(text: text, tokens: tokens, placeholder: placeholder)

        DispatchQueue.main.async {
            if nsView.window?.firstResponder !== nsView.textView {
                nsView.window?.makeFirstResponder(nsView.textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedQuickAddTextField

        init(parent: HighlightedQuickAddTextField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }

            return false
        }
    }
}

final class HighlightedQuickAddTextFieldView: NSView {
    let textView = NSTextView()

    private let placeholderLabel = NSTextField(labelWithString: "")
    private var lastText = ""
    private var lastTokens: [QuickAddToken] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func update(text: String, tokens: [QuickAddToken], placeholder: String) {
        placeholderLabel.stringValue = placeholder
        placeholderLabel.isHidden = !text.isEmpty

        guard text != lastText || tokens != lastTokens else {
            return
        }

        let selectedRanges = textView.selectedRanges
        textView.textStorage?.setAttributedString(attributedString(for: text, tokens: tokens))
        textView.selectedRanges = selectedRanges

        lastText = text
        lastTokens = tokens
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        textView.translatesAutoresizingMaskIntoConstraints = false
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
        textView.textContainer?.lineBreakMode = .byTruncatingTail
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        placeholderLabel.textColor = .placeholderTextColor

        addSubview(placeholderLabel)
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor, constant: -1)
        ])
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
        }

        return [
            .foregroundColor: color,
            .backgroundColor: color.withAlphaComponent(0.16)
        ]
    }
}

