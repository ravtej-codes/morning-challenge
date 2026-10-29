import SwiftUI
import UserNotifications

@main
struct MorningChallengeApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Keep the screen awake on every screen while the app is in front.
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
            if phase == .active {
                Task {
                    await Bells.requestPermissions()
                    await store.sync()
                }
            }
        }
    }
}

enum Screen: Equatable {
    case home, setup, countdown, won, lost, payCheck, settings
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @State private var screen: Screen = .home

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch screen {
            case .home: HomeView(screen: $screen)
            case .setup: SetupView(screen: $screen)
            case .countdown: CountdownView(screen: $screen)
            case .won: WonView(screen: $screen)
            case .lost: LostView(screen: $screen)
            case .payCheck: PayCheckView(screen: $screen)
            case .settings: SettingsView(screen: $screen)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            route()
        }
    }

    /// Decide where to land when the app comes to the front.
    private func route() {
        let justLost = store.evaluate()
        if justLost { Task { await Bells.cancelAll() } }
        if store.current != nil {
            screen = .countdown
        } else if justLost {
            screen = .lost
        } else if store.unpaid != nil {
            screen = .payCheck
        } else if screen == .countdown || screen == .payCheck {
            screen = .home
        }
    }
}
