import AppKit
import SwiftUI

@MainActor
final class TextEditSession: NSObject, ObservableObject, NSTextViewDelegate {
    @Published var hasChanges = false
    weak var textView: NSTextView?

    func textDidChange(_ notification: Notification) {
        // No full-string conversion, equality check, or SwiftUI binding per key.
        if !hasChanges { hasChanges = true }
    }
}

struct FullTextEditor: NSViewRepresentable {
    let entryID: UUID
    let store: ClipboardStore
    let session: TextEditSession

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = FocusedTextView(frame: .zero)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.allowsNonContiguousLayout = true
        // The original payload is fetched once, only after the user chooses Edit.
        textView.string = store.entry(id: entryID)?.text ?? ""
        textView.allowsUndo = true
        textView.delegate = session
        session.textView = textView
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: ()) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.delegate = nil
        textView.undoManager?.removeAllActions()
        textView.string = ""
    }
}

private final class FocusedTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        undoManager?.levelsOfUndo = 20
    }
}
