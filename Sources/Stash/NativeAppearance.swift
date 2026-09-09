import AppKit
import SwiftUI

/// Native material for window chrome; content panes provide their own background.
struct StashPanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            StashWindowMaterial()
        }
    }
}

private struct StashWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Use Tahoe's native glass controls, with standard controls on earlier macOS.
struct StashActionStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.buttonStyle(.glass).foregroundStyle(.primary)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
