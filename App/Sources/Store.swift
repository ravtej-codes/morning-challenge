import Foundation
import SwiftUI

/// The morning log, kept as a JSON file on the phone and mirrored to GCP.
/// Streak and the 12-month view are always calculated from the log.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var mornings: [Morning] = []
    @Published private(set) var lastBackup: Date?
    @Published private(set) var backupError: String?

    private var pending: Set<String> = []
    private let fileURL: URL
    private let backup = BackupClient()

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mornings.json")
        load()
    }

    // MARK: - Derived

    var current: Morning? { mornings.last(where: { $0.isRunning }) }
    var today: Morning? { mornings.first(where: { $0.date == Morning.dayKey(Date()) }) }
    var unpaid: Morning? { mornings.last(where: { $0.owesPayment }) }

    var streak: Int {
        mornings.sorted { $0.date < $1.date }.reduce(0) { n, m in
            switch m.result {
            case "won": return n + 1
            case "lost": return 0
            default: return n
            }
        }
    }

    /// Twelve months starting with the month of the first morning (or this month if none).
    /// Each value is the share of that month's days that were won; nil = month not reached yet.
    var months: [(label: String, fill: Double?)] {
        let cal = Calendar.current
        let firstDate = mornings.map(\.startedAt).min() ?? Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: firstDate))!
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let won = Set(mornings.filter { $0.result == "won" }.map(\.date))
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return (0..<12).map { i in
            let month = cal.date(byAdding: .month, value: i, to: start)!
            let label = fmt.string(from: month)
            if month > thisMonth { return (label, nil) }
            let days = cal.range(of: .day, in: .month, for: month)!.count
            let prefix = Morning.dayKey(month).prefix(7)
            let count = won.filter { $0.hasPrefix(prefix) }.count
            return (label, Double(count) / Double(days))
        }
    }

    // MARK: - Challenge lifecycle

    func start(activity: Activity, leadMinutes: Int) {
        let now = Date()
        var m = Morning(date: Morning.dayKey(now), activity: activity.rawValue, leadMinutes: leadMinutes,
                        startedAt: now, deadline: now.addingTimeInterval(TimeInterval(leadMinutes * 60)),
                        confirmedStartedAt: nil, result: nil, paid: nil, updatedAt: 0)
        m.touch()
        upsert(m)
    }

    func confirmStarted() {
        guard var m = current else { return }
        m.confirmedStartedAt = Date()
        m.result = "won"
        m.touch()
        upsert(m)
    }

    /// Marks a running challenge lost once the fail time has passed. Returns true if it changed.
    @discardableResult
    func evaluate(now: Date = Date()) -> Bool {
        guard var m = current, now >= m.failTime else { return false }
        m.result = "lost"
        m.touch()
        upsert(m)
        return true
    }

    // MARK: - Extra sessions (after the morning is done; never logged, never synced)

    /// Kept only so a running extra session survives the app being closed; cleared when it ends.
    @Published private(set) var extra: Morning? = Store.loadExtra() {
        didSet { UserDefaults.standard.set(extra.flatMap { try? JSONEncoder.morning.encode($0) }, forKey: Self.extraKey) }
    }
    private static let extraKey = "extraSession"

    private static func loadExtra() -> Morning? {
        UserDefaults.standard.data(forKey: extraKey).flatMap { try? JSONDecoder.morning.decode(Morning.self, from: $0) }
    }

    func startExtra(activity: Activity, leadMinutes: Int) {
        let now = Date()
        extra = Morning(date: Morning.dayKey(now), activity: activity.rawValue, leadMinutes: leadMinutes,
                        startedAt: now, deadline: now.addingTimeInterval(TimeInterval(leadMinutes * 60)),
                        confirmedStartedAt: nil, result: nil, paid: nil, updatedAt: 0)
    }

    func endExtra() { extra = nil }

    /// Ends a running extra session once its fail time has passed. Returns true if it was missed.
    @discardableResult
    func evaluateExtra(now: Date = Date()) -> Bool {
        guard let m = extra, now >= m.failTime else { return false }
        extra = nil
        return true
    }

    func setPaid(_ value: String) {
        guard var m = unpaid else { return }
        m.paid = value
        m.touch()
        upsert(m)
    }

    // MARK: - Persistence + sync

    private func upsert(_ m: Morning) {
        if let i = mornings.firstIndex(where: { $0.date == m.date }) {
            mornings[i] = m
        } else {
            mornings.append(m)
            mornings.sort { $0.date < $1.date }
        }
        pending.insert(m.date)
        save()
        Task { await sync() }
    }

    private struct Saved: Codable {
        var mornings: [Morning]
        var pending: [String]
        var lastBackup: Date?
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder.morning.decode(Saved.self, from: data) else { return }
        mornings = saved.mornings.sorted { $0.date < $1.date }
        pending = Set(saved.pending)
        lastBackup = saved.lastBackup
    }

    private func save() {
        let saved = Saved(mornings: mornings, pending: Array(pending), lastBackup: lastBackup)
        if let data = try? JSONEncoder.morning.encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Upload pending changes; on an empty phone, restore everything from GCP first.
    func sync() async {
        guard backup.isConfigured else {
            backupError = "Backup token not set"
            return
        }
        do {
            if mornings.isEmpty {
                let remote = try await backup.fetchAll()
                if !remote.isEmpty {
                    mornings = remote.sorted { $0.date < $1.date }
                    save()
                }
            }
            for date in pending.sorted() {
                guard let m = mornings.first(where: { $0.date == date }) else {
                    pending.remove(date)
                    continue
                }
                if let newer = try await backup.put(m) {
                    // GCP holds a later edit of this morning; keep that one.
                    if let i = mornings.firstIndex(where: { $0.date == date }) { mornings[i] = newer }
                }
                pending.remove(date)
            }
            lastBackup = Date()
            backupError = nil
        } catch {
            backupError = error.localizedDescription
        }
        save()
    }
}
