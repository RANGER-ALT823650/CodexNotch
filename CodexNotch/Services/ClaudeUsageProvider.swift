import Foundation

actor ClaudeUsageProvider: ClaudeUsageProviding {
    private static let userDefaultsKey = "claude_oauth_token"
    private static let endpointURL = "https://api.anthropic.com/api/oauth/usage"

    private var cachedToken: String?
    private let urlSession: URLSession
    private let commandRunner: @Sendable (String, [String]) async throws -> String
    private let accountReader: @Sendable () -> (email: String?, billingType: String?)

    init(
        urlSession: URLSession = .shared,
        commandRunner: @escaping @Sendable (String, [String]) async throws -> String = ClaudeUsageProvider.defaultRunCommand,
        accountReader: @escaping @Sendable () -> (email: String?, billingType: String?) = ClaudeUsageProvider.readAccountInfo
    ) {
        self.urlSession = urlSession
        self.commandRunner = commandRunner
        self.accountReader = accountReader
        if let saved = UserDefaults.standard.string(forKey: ClaudeUsageProvider.userDefaultsKey), !saved.isEmpty {
            self.cachedToken = saved
        }
    }

    func fetchUsage() async throws -> ClaudeUsageSnapshot {
        let token = try await resolveToken()
        do {
            return try await requestUsage(token: token)
        } catch let error as ClaudeUsageError {
            if case .unauthenticated = error {
                // Token may have rotated or expired. Clear cache and try scanning running processes again.
                clearCachedToken()
                if let freshToken = try? await scanRunningProcessesForToken() {
                    saveToken(freshToken)
                    return try await requestUsage(token: freshToken)
                }
            }
            throw error
        }
    }

    private func resolveToken() async throws -> String {
        let env = ProcessInfo.processInfo.environment
        if let envToken = env["CLAUDE_CODE_OAUTH_TOKEN"], !envToken.isEmpty {
            saveToken(envToken)
            return envToken
        }

        if let cachedToken, !cachedToken.isEmpty {
            return cachedToken
        }

        if let fileToken = Self.readTokenFromFile() {
            saveToken(fileToken)
            return fileToken
        }

        if let processToken = try? await scanRunningProcessesForToken() {
            saveToken(processToken)
            return processToken
        }

        throw ClaudeUsageError.tokenNotFound
    }

    private func saveToken(_ token: String) {
        cachedToken = token
        UserDefaults.standard.set(token, forKey: ClaudeUsageProvider.userDefaultsKey)
        let dirURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codex-notch")
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let fileURL = dirURL.appendingPathComponent("claude_token")
        try? token.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func clearCachedToken() {
        cachedToken = nil
        UserDefaults.standard.removeObject(forKey: ClaudeUsageProvider.userDefaultsKey)
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codex-notch/claude_token")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func scanRunningProcessesForToken() async throws -> String? {
        let output = try await commandRunner("/bin/ps", ["-ax", "-E", "-o", "command="])
        return Self.extractToken(from: output)
    }

    static func extractToken(from text: String) -> String? {
        let pattern = #"CLAUDE_CODE_OAUTH_TOKEN=(sk-ant-oat[0-9a-zA-Z_-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let tokenRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[tokenRange])
    }

    private static func readTokenFromFile() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".claude/oauth_token"),
            home.appendingPathComponent(".claude/token"),
            home.appendingPathComponent(".config/codex-notch/claude_token"),
        ]
        for url in candidates {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.starts(with: "sk-ant-") {
                    return trimmed
                }
            }
        }
        return nil
    }

    static func readAccountInfo() -> (email: String?, billingType: String?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["oauthAccount"] as? [String: Any]
        else {
            return (nil, nil)
        }
        let email = oauth["emailAddress"] as? String
        let billing = oauth["billingType"] as? String
        return (email, billing)
    }

    private func requestUsage(token: String) async throws -> ClaudeUsageSnapshot {
        guard let url = URL(string: Self.endpointURL) else {
            throw ClaudeUsageError.requestFailed("无效的 API 请求地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Claude-Code/2.1.280", forHTTPHeaderField: "User-Agent")
        request.setValue("claude-code-20250219", forHTTPHeaderField: "anthropic-beta")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw ClaudeUsageError.requestFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeUsageError.requestFailed("未获得有效的 HTTP 响应")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ClaudeUsageError.unauthenticated("HTTP \(httpResponse.statusCode)")
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeUsageError.requestFailed("HTTP \(httpResponse.statusCode)")
        }

        let account = accountReader()
        return try Self.parseResponse(data: data, account: account)
    }

    static func parseResponse(
        data: Data,
        account: (email: String?, billingType: String?) = (nil, nil),
        fetchedAt: Date = Date()
    ) throws -> ClaudeUsageSnapshot {
        struct RawResponse: Decodable {
            struct Window: Decodable {
                let utilization: Double
                let resets_at: String?
            }
            struct Breakdown: Decodable {
                struct Row: Decodable {
                    let key: String
                    let display_name: String
                    let percent: Int
                }
                let rows: [Row]?
            }
            let five_hour: Window?
            let seven_day: Window?
            let seven_day_breakdown: Breakdown?
        }

        let decoded: RawResponse
        do {
            decoded = try JSONDecoder().decode(RawResponse.self, from: data)
        } catch {
            throw ClaudeUsageError.parseFailed(error.localizedDescription)
        }

        let primaryWindow: UsageWindow? = decoded.five_hour.map { w in
            UsageWindow(
                usedPercent: w.utilization,
                durationMinutes: 300,
                resetsAt: parseISO8601Date(w.resets_at)
            )
        }

        let secondaryWindow: UsageWindow
        if let w = decoded.seven_day {
            secondaryWindow = UsageWindow(
                usedPercent: w.utilization,
                durationMinutes: 10_080,
                resetsAt: parseISO8601Date(w.resets_at)
            )
        } else {
            secondaryWindow = UsageWindow(
                usedPercent: 0,
                durationMinutes: 10_080,
                resetsAt: nil
            )
        }

        let breakdownItems = (decoded.seven_day_breakdown?.rows ?? []).map {
            ClaudeBreakdownItem(key: $0.key, displayName: $0.display_name, percent: $0.percent)
        }

        return ClaudeUsageSnapshot(
            primary: primaryWindow,
            secondary: secondaryWindow,
            breakdown: breakdownItems,
            accountEmail: account.email,
            billingType: account.billingType,
            fetchedAt: fetchedAt
        )
    }

    static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFraction.date(from: string) {
            return date
        }
        let standardFormatter = ISO8601DateFormatter()
        return standardFormatter.date(from: string)
    }

    private static func defaultRunCommand(_ executable: String, _ arguments: [String]) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ClaudeUsageError.requestFailed("\(executable) 执行退出码 \(process.terminationStatus)")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
