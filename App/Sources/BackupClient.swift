import Foundation
import Security

/// Talks to the Cloud Run backup service. The token lives in the Keychain, never in the code.
struct BackupClient {
    static let baseURL = URL(string: "https://morning-api-1017056000874.asia-south1.run.app")!

    var isConfigured: Bool { Keychain.token != nil }

    enum BackupError: LocalizedError {
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .http(401): return "Backup token rejected"
            case .http(let code): return "Backup server error \(code)"
            }
        }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue(Keychain.token, forHTTPHeaderField: "X-Token")
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    func fetchAll() async throws -> [Morning] {
        let (data, resp) = try await URLSession.shared.data(for: request("mornings"))
        try check(resp, allow: [])
        return try JSONDecoder.morning.decode([Morning].self, from: data)
    }

    /// Returns the server's copy if it was newer (HTTP 409), otherwise nil.
    func put(_ m: Morning) async throws -> Morning? {
        let body = try JSONEncoder.morning.encode(m)
        let (data, resp) = try await URLSession.shared.data(for: request("mornings/\(m.date)", method: "PUT", body: body))
        try check(resp, allow: [409])
        if (resp as? HTTPURLResponse)?.statusCode == 409 {
            return try JSONDecoder.morning.decode(Morning.self, from: data)
        }
        return nil
    }

    func ping() async -> String {
        do {
            let (_, resp) = try await URLSession.shared.data(for: request("mornings"))
            try check(resp, allow: [])
            return "Connected ✓"
        } catch {
            return error.localizedDescription
        }
    }

    private func check(_ resp: URLResponse, allow: Set<Int>) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) && !allow.contains(code) { throw BackupError.http(code) }
    }
}

enum Keychain {
    private static let account = "backup-token"

    static var token: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
                  let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
            SecItemDelete(q as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = q
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
