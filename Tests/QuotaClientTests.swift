import Foundation

final class StubProtocol: URLProtocol {
    static var replies: [(Int, Data)] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        guard !Self.replies.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let reply = Self.replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main struct ClientChecks {
    static var count = 0
    static let weekly = Data(#"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":604800,"reset_at":1800000000},"secondary_window":null}}"#.utf8)
    static let credential = CodexCredential(accessToken: "fixture-access", accountID: "fixture-account")

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
        count += 1
    }
    static func rejects(_ error: QuotaError, _ operation: () throws -> Void) {
        do { try operation(); fatalError("Expected \(error)") }
        catch let actual as QuotaError { check(actual == error, "Expected safe error") }
        catch { fatalError("Unexpected error type") }
    }
    static func stub(_ replies: [(Int, Data)], loader: @escaping () throws -> CodexCredential = { credential }) -> QuotaClient {
        StubProtocol.replies = replies
        StubProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return QuotaClient(session: URLSession(configuration: config), loadCredential: loader)
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let window = try await QuotaClient().fetch()
            // Only aggregate quota, never account identifiers, tokens, or raw server responses.
            print("Direct OpenAI: remaining=\(100 - window.usedPercent)% window=\(window.windowMinutes)min")
            return
        }
        let window = try QuotaResponse.parse(weekly)
        check(window.windowMinutes == 10080, "Single primary can be weekly")
        check(window.usedPercent == 12, "Correct percentage")
        let both = Data(#"{"rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":18000},"secondary_window":{"used_percent":60,"limit_window_seconds":604800}}}"#.utf8)
        let constrained = try QuotaResponse.parse(both)
        check(constrained.usedPercent == 60, "Select the most constrained window")
        for bad in [
            #"{"rate_limit":null}"#,
            #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#,
            #"{"rate_limit":{"primary_window":{"used_percent":101,"limit_window_seconds":18000}}}"#,
            #"{"rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":0}}}"#,
            #"{"rate_limit":{"primary_window":{"used_percent":4,"limit_window_seconds":18000},"secondary_window":{"used_percent":"broken","limit_window_seconds":604800}}}"#,
            #"{"rate_limit":{"primary_window":{"used_percent":true,"limit_window_seconds":18000}}}"#
        ] {
            rejects(.invalidResponse) { _ = try QuotaResponse.parse(Data(bad.utf8)) }
        }
        rejects(.chatGPTLoginRequired) {
            _ = try CodexCredential.parse(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"fixture-key","tokens":{"access_token":"stale-oauth"}}"#.utf8))
        }
        rejects(.credentialsUnavailable) { _ = try CodexCredential.parse(Data("{}".utf8)) }
        let parsed = try CodexCredential.parse(Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":"fixture-access","account_id":"fixture-account"}}"#.utf8))
        check(parsed == credential, "Native auth file")
        check(CodexCredential.home(environment: ["CODEX_HOME": "/tmp/quota-fixture"]).path == "/tmp/quota-fixture", "Respect explicit Codex home")
        check(OfficialUsageRedirectPolicy.allows(URL(string: "https://chatgpt.com/backend-api/wham/usage")), "Official HTTPS allowed")
        for value in ["http://chatgpt.com/", "https://chatgpt.com.evil.example/", "https://example.com/", "https://chatgpt.com:8443/"] {
            check(!OfficialUsageRedirectPolicy.allows(URL(string: value)), "Do not forward bearer to another destination")
        }
        let direct = stub([(200, weekly)])
        _ = try await direct.fetch()
        check(StubProtocol.requests.count == 1, "Exactly one direct request")
        check(StubProtocol.requests[0].url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage", "Fixed official endpoint")
        check(StubProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access", "OAuth header")
        check(StubProtocol.requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id") == "fixture-account", "Account scope")
        var reads = 0
        let changed = stub([(401, Data()), (200, weekly)]) {
            reads += 1
            return CodexCredential(accessToken: reads == 1 ? "old-fixture" : "new-fixture", accountID: "fixture-account")
        }
        _ = try await changed.fetch()
        check(reads == 2 && StubProtocol.requests.count == 2, "Reread owner's changed credentials on 401")
        check(StubProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer new-fixture", "Retry uses owner's new token")
        let expired = stub([(401, Data())])
        do { _ = try await expired.fetch(); fatalError("Expected expired login") }
        catch let error as QuotaError { check(error == .loginExpired, "No refresh rotation or infinite retry") }
        let limited = stub([(429, Data())])
        do { _ = try await limited.fetch(); fatalError("Expected service limit") }
        catch let error as QuotaError { check(error == .service(429), "429 remains explicit") }
        let unavailable = stub([(503, Data()), (200, weekly)])
        _ = try await unavailable.fetch()
        check(StubProtocol.requests.count == 2, "One bounded retry for service outage")
        print("PASS: \(count) quota client checks (no live credentials or network)")
    }
}
