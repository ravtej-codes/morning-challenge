import Foundation

struct Suggestion: Codable, Identifiable, Equatable {
    var icon: String
    var action: String
    var id: String { action }
}

/// The system prompt and its version. The live copy is on the backend, so it can change
/// without a new build and can hold personal examples this public repo must not.
struct ServedPrompt: Codable, Equatable {
    var version: Int
    var instructions: String
}

/// Asks DeepSeek for up to 3 small first actions, built only from what the user described.
/// The API key is typed into Settings and kept in the Keychain.
struct NextActionClient {
    static let url = URL(string: "https://api.deepseek.com/chat/completions")!
    private static let cacheKey = "servedPrompt"

    /// The backend's prompt, else the last one downloaded, else the built-in one.
    static func currentPrompt() async -> ServedPrompt {
        if let live = try? await BackupClient().fetchPrompt() {
            UserDefaults.standard.set(try? JSONEncoder().encode(live), forKey: cacheKey)
            return live
        }
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(ServedPrompt.self, from: data) {
            return cached
        }
        return ServedPrompt(version: 0, instructions: instructions)
    }

    /// Fallback only, and public: real personal examples go in the backend copy, never here.
    static let instructions = """
    You help a person who feels resistance to starting an activity. They describe, in their own words, \
    how they usually get started. Suggest up to 3 first actions they could commit to right now.

    Rules:
    - Use only steps the user mentioned. Never add steps from general knowledge, even common ones.
    - Each action must happen before the activity begins. Never suggest doing part of the activity itself \
    (no first set, warm-up, first page, first question, first minute of meditation).
    - Don't assume details the user hasn't decided yet (which exercise, which chapter, which equipment).
    - If a step in their description creates resistance (for example, looking at the whole plan), prefer a \
    starting point that comes before it or routes around it. You may reorder their steps.
    - Each suggestion must start from a different point in their sequence. If their description only supports \
    1 or 2 distinct starting points, return fewer. Never pad.
    - Each action: under 2 minutes, physical and observable, starts with a verb, under 12 words, plain English.

    Reply with json only, in this shape:
    {"suggestions": [{"icon": "<one emoji>", "action": "<the action>"}]}
    """

    enum Failure: LocalizedError {
        case noKey, http(Int), empty
        var errorDescription: String? {
            switch self {
            case .noKey: return "Add your DeepSeek key in Settings first."
            case .http(401): return "DeepSeek rejected the key. Check it in Settings."
            case .http(402): return "DeepSeek balance is empty."
            case .http(let code): return "DeepSeek error \(code). Try again."
            case .empty: return "No usable suggestions came back. Try again or write your own."
            }
        }
    }

    func suggest(area: String, routine: String, prompt: ServedPrompt) async throws -> [Suggestion] {
        guard let key = Keychain.deepseekKey else { throw Failure.noKey }
        var r = URLRequest(url: Self.url)
        r.httpMethod = "POST"
        r.timeoutInterval = 40
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0.3,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": prompt.instructions],
                ["role": "user", "content": "Activity: \(area)\nHow I usually get started: \(routine)"],
            ],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw Failure.http(code) }

        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        struct Payload: Decodable { let suggestions: [Suggestion] }

        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let content = reply.choices.first?.message.content,
              let json = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: json) else { throw Failure.empty }
        let list = payload.suggestions.filter { !$0.action.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !list.isEmpty else { throw Failure.empty }
        return Array(list.prefix(3))
    }
}
