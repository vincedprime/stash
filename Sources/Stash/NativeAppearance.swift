import AppKit
import SwiftUI

/// Keep text surfaces independent of other windows. Native glass belongs on
/// controls above this opaque, appearance-adaptive foundation.
struct StashPanelBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

struct StashToolbarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        } else {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

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
