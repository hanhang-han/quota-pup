// Minimal standalone adaptation of CodexBar's Codex OAuth usage path.
// Upstream attribution and MIT license: ThirdPartyNotices/CodexBar.txt.
import Foundation

struct RateWindow: Codable, Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: String?
}

enum QuotaError: Error, LocalizedError, Equatable {
    case credentialsUnavailable
    case chatGPTLoginRequired
    case loginExpired
    case invalidResponse
    case service(Int)
    case network

    var errorDescription: String? {
        switch self {
        case .credentialsUnavailable: return "请先在 Codex 登录 ChatGPT 账号"
        case .chatGPTLoginRequired: return "额度查询需要 ChatGPT 登录，API Key 不适用"
        case .loginExpired: return "登录已过期，请在 Codex 中重新登录"
        case .invalidResponse: return "暂时无法识别额度数据，稍后重试"
        case .service(let status): return "额度服务暂不可用（\(status)）"
        case .network: return "网络暂不可用，稍后自动重试"
        }
    }
}

struct CodexCredential: Equatable {
    let accessToken: String
    let accountID: String?

    static func home(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    static func load(home: URL = Self.home()) throws -> Self {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")) else {
            throw QuotaError.credentialsUnavailable
        }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> Self {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.credentialsUnavailable
        }
        if (json["auth_mode"] as? String)?.lowercased() == "apikey" {
            throw QuotaError.chatGPTLoginRequired
        }
        guard let tokens = json["tokens"] as? [String: Any],
              let access = nonempty(tokens["access_token"] ?? tokens["accessToken"]) else {
            if nonempty(json["OPENAI_API_KEY"]) != nil { throw QuotaError.chatGPTLoginRequired }
            throw QuotaError.credentialsUnavailable
        }
        let account = nonempty(tokens["account_id"] ?? tokens["accountId"])
            ?? accountClaim(nonempty(tokens["id_token"] ?? tokens["idToken"]))
            ?? accountClaim(access)
        return Self(accessToken: access, accountID: account)
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Identity hint only. The official service validates the actual bearer token.
    private static func accountClaim(_ token: String?) -> String? {
        guard let parts = token?.split(separator: "."), parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        return nonempty(auth?["chatgpt_account_id"]) ?? nonempty(claims["chatgpt_account_id"])
    }
}

enum QuotaResponse {
    private struct Response: Decodable {
        let rateLimit: Limits?
        enum CodingKeys: String, CodingKey { case rateLimit = "rate_limit", rateLimits = "rate_limits" }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rateLimit = try values.decodeIfPresent(Limits.self, forKey: .rateLimit)
                ?? values.decodeIfPresent(Limits.self, forKey: .rateLimits)
        }
    }
    private struct Limits: Decodable {
        let primary: Window?
        let secondary: Window?
        enum CodingKeys: String, CodingKey { case primary = "primary_window", secondary = "secondary_window" }
    }
    private struct Window: Decodable {
        let used: Double
        let seconds: Double
        let reset: Double?
        enum CodingKeys: String, CodingKey { case used = "used_percent", seconds = "limit_window_seconds", reset = "reset_at" }
    }

    static func parse(_ data: Data) throws -> RateWindow {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let limits = response.rateLimit else { throw QuotaError.invalidResponse }
        let windows = [limits.primary, limits.secondary].compactMap { $0 }
        // A malformed reported sibling must not make the remaining window look healthy.
        guard !windows.isEmpty, windows.allSatisfy({
            $0.used.isFinite && (0...100).contains($0.used) && $0.seconds.isFinite && $0.seconds > 0
                && $0.seconds <= 366 * 86400
                && ($0.reset == nil || ($0.reset!.isFinite && $0.reset! >= 0 && $0.reset! <= 253402300799))
        }), let selected = windows.max(by: { $0.used < $1.used }) else { throw QuotaError.invalidResponse }
        let reset = selected.reset.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) }
        return RateWindow(usedPercent: selected.used, windowMinutes: Int(ceil(selected.seconds / 60)), resetsAt: reset)
    }
}

final class OfficialUsageRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "chatgpt.com" && (url.port == nil || url.port == 443)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.allows(request.url) ? request : nil)
    }
}

final class QuotaClient {
    private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let session: URLSession
    private let loadCredential: () throws -> CodexCredential

    init(session: URLSession? = nil, loadCredential: @escaping () throws -> CodexCredential = { try CodexCredential.load() }) {
        self.loadCredential = loadCredential
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 25
            config.timeoutIntervalForResource = 30
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false
            self.session = URLSession(configuration: config, delegate: OfficialUsageRedirectPolicy(), delegateQueue: nil)
        }
    }

    deinit { session.invalidateAndCancel() }

    func fetch() async throws -> RateWindow {
        var credential = try loadCredential()
        var retriedAuthentication = false
        var retriedService = false
        while true {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("QuotaPup/0.4.0", forHTTPHeaderField: "User-Agent")
            if let account = credential.accountID { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            let data: Data
            let response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch { throw QuotaError.network }
            guard let http = response as? HTTPURLResponse else { throw QuotaError.invalidResponse }
            switch http.statusCode {
            case 200:
                return try QuotaResponse.parse(data)
            case 401:
                // Codex owns shared OAuth rotation. Only reread; never rotate or overwrite auth.json.
                guard !retriedAuthentication else { throw QuotaError.loginExpired }
                retriedAuthentication = true
                let updated = try loadCredential()
                guard updated != credential else { throw QuotaError.loginExpired }
                credential = updated
            case 500...599 where !retriedService:
                retriedService = true
                try await Task.sleep(nanoseconds: 1_000_000_000)
            default:
                throw QuotaError.service(http.statusCode)
            }
        }
    }
}
