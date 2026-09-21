import AppKit
import SwiftUI

/// AppKit-backed text editor. SwiftUI's `TextEditor` drops keystrokes and
/// paste on macOS 26 (observed in this app's NavigationSplitView detail
/// column, with both ObservableObject and @Observable models), so we use a
/// real NSTextView — the same text machinery every native Mac app uses.
struct TextEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = scrollView.documentView as! NSTextView
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.string = text
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 8, height: 10)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            let selected = textView.selectedRange
            textView.string = text
            textView.setSelectedRange(selected)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: TextEditorView
        init(_ parent: TextEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}
