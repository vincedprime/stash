import AppKit
import SwiftUI

/// Opaque system colours keep content readable over any desktop background.
struct StashPanelBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}

/// Use the same native secondary control style throughout Stash.
struct StashActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered)
    }
}
