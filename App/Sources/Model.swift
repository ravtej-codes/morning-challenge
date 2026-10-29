import Foundation

enum Activity: String, Codable, CaseIterable, Identifiable {
    case gym = "Gym — ATHLEAN-X"
    case meditation = "Meditation — Muse or guided"
    case studyBoss = "Study Boss"
    case workBoss = "Work Boss"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .gym: return "figure.strengthtraining.traditional"
        case .meditation: return "brain.head.profile"
        case .studyBoss: return "book"
        case .workBoss: return "briefcase"
        }
    }
}

/// One entry per morning. Field names match the Firestore document.
struct Morning: Codable, Identifiable, Equatable {
    var date: String                 // yyyy-MM-dd, local time
    var activity: String
    var leadMinutes: Int
    var startedAt: Date
    var deadline: Date
    var confirmedStartedAt: Date?
    var result: String?              // "won" | "lost" | nil while running
    var paid: String?                // "yes" | "not_yet" | nil
    var updatedAt: Double            // epoch ms, used to resolve conflicts

    var id: String { date }

    static let softBellFraction = 0.75
    static let alarmDelay: TimeInterval = 60        // deadline + 1 min: insistent alarm
    static let failDelay: TimeInterval = 3 * 60     // deadline + 3 min: challenge lost

    var softBellTime: Date { startedAt.addingTimeInterval(deadline.timeIntervalSince(startedAt) * Self.softBellFraction) }
    var alarmTime: Date { deadline.addingTimeInterval(Self.alarmDelay) }
    var failTime: Date { deadline.addingTimeInterval(Self.failDelay) }
    var isRunning: Bool { result == nil }
    var owesPayment: Bool { result == "lost" && paid != "yes" }

    mutating func touch() { updatedAt = Date().timeIntervalSince1970 * 1000 }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension JSONEncoder {
    static let morning: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let morning: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
