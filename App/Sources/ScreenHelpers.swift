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
                tap.delegate = self
                window.addGestureRecognizer(tap)
                windows.append(ObjectIdentifier(window))
            }
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        g.view?.endEditing(true)
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
    func swipeBack(_ action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global).onEnded { v in
                if v.startLocation.x < 40, v.translation.width > 80, abs(v.translation.height) < 100 {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    action()
                }
            }
        )
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
    }
}
