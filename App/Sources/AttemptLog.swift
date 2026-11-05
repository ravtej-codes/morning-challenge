import Foundation

/// One go through the next-action flow, for improving the prompt later.
/// Field names match the Firestore document.
/// startedAt == nil means suggestions were shown but nothing was committed to.
struct ActionAttempt: Codable, Identifiable, Equatable {
    var id: String
    var createdAt: Date
    var area: String
    var routine: String
    var suggestions: [Suggestion]
    var promptVersion: Int?          // nil when no suggestions came back
    var action: String? = nil        // what was finally committed to
    var suggestedAction: String? = nil // the suggestion it came from, if any
    var source: String? = nil        // "suggestion" | "edited" | "own"
    var session: String? = nil       // "morning" | "extra"
    var leadMinutes: Int? = nil
    var startedAt: Date? = nil
    var deadline: Date? = nil
    var finishedAt: Date? = nil
    var outcome: String? = nil       // "done" | "missed"
    var updatedAt: Double = 0        // epoch ms, the server keeps the latest

    mutating func touch() { updatedAt = Date().timeIntervalSince1970 * 1000 }
}

/// Saves attempts on the phone and uploads them. Upload only: the server is the long-term
/// copy, and nothing here affects the morning log, the streak or payments.
@MainActor
final class AttemptLog {
    private var attempts: [ActionAttempt] = []
    private var pending: Set<String> = []
    private let fileURL: URL

    private struct Saved: Codable {
        var attempts: [ActionAttempt]
        var pending: [String]
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("attempts.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.morning.decode(Saved.self, from: data) {
            attempts = saved.attempts
            pending = Set(saved.pending)
        }
    }

    /// Suggestions came back. Returns the attempt's id so a later commit can update it.
    func recordSuggestions(area: String, routine: String, suggestions: [Suggestion], promptVersion: Int) -> String {
        let a = ActionAttempt(id: UUID().uuidString, createdAt: Date(), area: area, routine: routine,
                              suggestions: suggestions, promptVersion: promptVersion)
        put(a)
        return a.id
    }

    /// The clock started. Without an attemptID (no suggestions came back) a new attempt is created.
    func recordCommit(attemptID: String?, area: String, routine: String, action: String,
                      suggestedAction: String?, session: String, morning m: Morning) {
        var a = attempts.first(where: { $0.id == attemptID })
            ?? ActionAttempt(id: UUID().uuidString, createdAt: Date(), area: area, routine: routine,
                             suggestions: [], promptVersion: nil)
        a.action = action
        a.suggestedAction = suggestedAction
        if let suggestedAction {
            a.source = action == suggestedAction ? "suggestion" : "edited"
        } else {
            a.source = "own"
        }
        a.session = session
        a.leadMinutes = m.leadMinutes
        a.startedAt = m.startedAt
        a.deadline = m.deadline
        put(a)
    }

    /// The running session ended. Only one session can run at a time, so it's the latest open attempt.
    func finish(outcome: String, at date: Date = Date()) {
        guard var a = attempts.last(where: { $0.startedAt != nil && $0.outcome == nil }) else { return }
        a.outcome = outcome
        a.finishedAt = date
        put(a)
    }

    func upload(using backup: BackupClient) async throws {
        defer { save() }
        for id in pending.sorted() {
            guard let a = attempts.first(where: { $0.id == id }) else {
                pending.remove(id)
                continue
            }
            try await backup.put(a)
            // If it changed during the upload, leave it pending so the newer version goes up too.
            if attempts.first(where: { $0.id == id })?.updatedAt == a.updatedAt {
                pending.remove(id)
            }
        }
    }

    private func put(_ attempt: ActionAttempt) {
        var a = attempt
        a.touch()
        if let i = attempts.firstIndex(where: { $0.id == a.id }) {
            attempts[i] = a
        } else {
            attempts.append(a)
        }
        pending.insert(a.id)
        save()
    }

    private func save() {
        let saved = Saved(attempts: attempts, pending: Array(pending))
        if let data = try? JSONEncoder.morning.encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
