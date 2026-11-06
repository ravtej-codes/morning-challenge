import SwiftUI
import UIKit

/// Tap anywhere outside a text field to close the keyboard, on every screen.
/// A window-level recogniser that never cancels touches, so buttons still work.
@MainActor
final class KeyboardDismisser: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismisser()
    private var windows: [ObjectIdentifier] = []

    func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !windows.contains(ObjectIdentifier(window)) {
                let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
                tap.cancelsTouchesInView = false
                tap.delaysTouchesEnded = false   // don't hold back the tap from the button underneath
                tap.delegate = self
                window.addGestureRecognizer(tap)
                windows.append(ObjectIdentifier(window))
            }
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        // close the keyboard after the tapped button has handled its tap; closing it mid-tap
        // re-renders the screen and the button (e.g. Back) can lose the tap
        let window = g.view
        DispatchQueue.main.async { window?.endEditing(true) }
    }

    // taps inside a text field / editor keep the keyboard up (moving the cursor etc.)
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var v = touch.view
        while let view = v {
            if view is UITextView || view is UITextField { return false }
            v = view.superview
        }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

extension View {
    /// Swipe right from the left edge to go back (the app routes screens itself, so no NavigationStack gesture).
    /// A thin invisible strip on top of the left edge catches the drag; a gesture on the screen itself
    /// never fires there because the edge is empty padding, which isn't touchable in SwiftUI.
    func swipeBack(_ action: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Color.clear
                    .frame(width: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 10).onEnded { v in
                            if v.translation.width > 60, abs(v.translation.height) < abs(v.translation.width) {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                action()
                            }
                        }
                    )
                    .ignoresSafeArea()
            }
    }
}

/// Back button with a proper tap target; sits in a fixed header so it can't be pushed off screen.
struct BackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                Text("Back")
            }
            .padding(.vertical, 10)
            .padding(.trailing, 40)
            .frame(minHeight: 48)
            .contentShape(Rectangle())   // whole padded area is tappable, not just the letters
        }
        .foregroundStyle(.secondary)
    }
}
