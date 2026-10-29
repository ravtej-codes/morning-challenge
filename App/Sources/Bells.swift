import AlarmKit
import Foundation
import SwiftUI
import UserNotifications

struct ChallengeAlarmMetadata: AlarmMetadata {}

/// Schedules the soft bells and deadline bells (normal notifications with bell sounds)
/// and the insistent alarm (AlarmKit, rings through Sleep/Work Focus).
@MainActor
enum Bells {
    private static let ids = ["soft-bells", "deadline-bells", "lost"]
    private static let alarmKey = "alarmID"

    static func requestPermissions() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
        }
    }

    static func schedule(for m: Morning) async {
        await cancelAll()
        notify(id: "soft-bells", at: m.softBellTime, title: "Wrap up", body: "75% of your time is gone. Start moving towards \(m.activity).", sound: "soft_bells.wav")
        notify(id: "deadline-bells", at: m.deadline, title: "It's time", body: "Start \(m.activity) now, then tap “I've started”.", sound: "deadline_bells.wav")
        notify(id: "lost", at: m.failTime, title: "Challenge lost", body: "Open the app.", sound: "lost_bell.wav")
        await scheduleAlarm(at: m.alarmTime, title: "Start \(m.activity) now")
    }

    static func cancelAll() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        if let raw = UserDefaults.standard.string(forKey: alarmKey), let id = UUID(uuidString: raw) {
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
            UserDefaults.standard.removeObject(forKey: alarmKey)
        }
    }

    /// Day-one spike: an insistent alarm one minute from now, nothing logged.
    static func testAlarm() async -> String {
        await requestPermissions()
        guard AlarmManager.shared.authorizationState == .authorized else {
            return "AlarmKit not allowed — Settings → Morning → Alarms"
        }
        let ok = await scheduleAlarm(at: Date().addingTimeInterval(60), title: "Test alarm")
        return ok ? "Test alarm set for 1 minute. Lock the phone." : "AlarmKit refused to schedule"
    }

    private static func notify(id: String, at date: Date, title: String, body: String, sound: String) {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    @discardableResult
    private static func scheduleAlarm(at date: Date, title: String) async -> Bool {
        let id = UUID()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        )
        let attributes = AlarmAttributes<ChallengeAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .orange
        )
        let config = AlarmManager.AlarmConfiguration<ChallengeAlarmMetadata>(
            schedule: .fixed(date),
            attributes: attributes
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
            UserDefaults.standard.set(id.uuidString, forKey: alarmKey)
            return true
        } catch {
            return false
        }
    }
}

/// Plays bells while the app is open (iOS hides notifications from the foreground app otherwise).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
