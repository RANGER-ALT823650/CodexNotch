import Foundation

actor CursorUsageProvider: CursorUsageProviding {
    private static let usageURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"
    private static let planURL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo"
    private static let refreshURL = "https://api2.cursor.sh/oauth/token"
    private static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    private let urlSession: URLSession
    private let authReader: @Sendable () async throws -> CursorCredentials
    private let now: @Sendable () -> Date
    private var sessionCredentials: CursorCredentials?

    init(
        urlSession: URLSession = .shared,
        authReader: @escaping @Sendable () async throws -> CursorCredentials = CursorUsageProvider.readLocalAuth,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.urlSession = urlSession
        self.authReader = authReader
        self.now = now
    }

    func fetchUsage() async throws -> CursorUsageSnapshot {
        var credentials = try await resolveCredentials()
        do {
            return try await requestUsage(credentials: credentials)
        } catch let error as CursorUsageError {
            guard case .unauthenticated = error, credentials.refreshToken?.isEmpty == false else {
                throw error
            }
            credentials = try await refresh(credentials)
            sessionCredentials = credentials
            return try await requestUsage(credentials: credentials)
        }
    }

    private func resolveCredentials() async throws -> CursorCredentials {
        var credentials = try await authReader()
        if let cached = sessionCredentials, !cached.accessToken.isEmpty {
            credentials.accessToken = cached.accessToken
            if let refresh = cached.refreshToken, !refresh.isEmpty {
                credentials.refreshToken = refresh
            }
        }
        if Self.needsRefresh(token: credentials.accessToken, now: now()) {
            credentials = try await refresh(credentials)
        }
        sessionCredentials = credentials
        return credentials
    }

    private func refresh(_ credentials: CursorCredentials) async throws -> CursorCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw CursorUsageError.unauthenticated("登录已过期")
        }
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
        ]
        let data = try await post(urlString: Self.refreshURL, token: nil, body: body)
        let json = try Self.jsonObject(data)
        if (json["shouldLogout"] as? Bool) == true {
            throw CursorUsageError.unauthenticated("需要重新登录")
        }
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw CursorUsageError.unauthenticated("刷新登录失败")
        }
        var updated = credentials
        updated.accessToken = accessToken
        if let rotated = json["refresh_token"] as? String, !rotated.isEmpty {
            updated.refreshToken = rotated
        }
        return updated
    }

    private func requestUsage(credentials: CursorCredentials) async throws -> CursorUsageSnapshot {
        let usageData = try await post(urlString: Self.usageURL, token: credentials.accessToken, body: [:])
        let planData = try? await post(urlString: Self.planURL, token: credentials.accessToken, body: [:])
        return try Self.makeSnapshot(
            usageData: usageData,
            planData: planData,
            credentials: credentials,
            fetchedAt: now()
        )
    }

    private func post(urlString: String, token: String?, body: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw CursorUsageError.requestFailed("无效的 API 地址")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw CursorUsageError.requestFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CursorUsageError.requestFailed("未获得有效的 HTTP 响应")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorUsageError.unauthenticated("HTTP \(http.statusCode)")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorUsageError.requestFailed("HTTP \(http.statusCode)")
        }
        if let json = try? Self.jsonObject(data),
           let code = json["code"] as? String,
           code == "unauthenticated" {
            let message = (json["message"] as? String) ?? code
            throw CursorUsageError.unauthenticated(message)
        }
        return data
    }

    static func needsRefresh(token: String, now: Date) -> Bool {
        guard let expiry = jwtExpiration(token: token) else { return false }
        return expiry.timeIntervalSince(now) < 120
    }

    static func jwtExpiration(token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let exp = number(json["exp"])
        guard exp > 0 else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    static func readLocalAuth() async throws -> CursorCredentials {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw CursorUsageError.tokenNotFound
        }
        let query = """
        SELECT key, value FROM ItemTable WHERE key IN (
          'cursorAuth/accessToken',
          'cursorAuth/refreshToken',
          'cursorAuth/cachedEmail',
          'cursorAuth/stripeMembershipType'
        );
        """
        let output = try await runCommand("/usr/bin/sqlite3", ["-readonly", database.path, query])
        guard let credentials = parseAuthRows(output) else {
            throw CursorUsageError.tokenNotFound
        }
        return credentials
    }

    static func parseAuthRows(_ text: String) -> CursorCredentials? {
        var accessToken = ""
        var refreshToken: String?
        var email: String?
        var membershipType: String?
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "|") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            switch key {
            case "cursorAuth/accessToken":
                accessToken = value
            case "cursorAuth/refreshToken":
                refreshToken = value
            case "cursorAuth/cachedEmail":
                email = value
            case "cursorAuth/stripeMembershipType":
                membershipType = value
            default:
                break
            }
        }
        guard !accessToken.isEmpty else { return nil }
        return CursorCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: email,
            membershipType: membershipType
        )
    }

    static func makeSnapshot(
        usageData: Data,
        planData: Data?,
        credentials: CursorCredentials,
        fetchedAt: Date = Date()
    ) throws -> CursorUsageSnapshot {
        let usage = try jsonObject(usageData)
        guard let planUsage = usage["planUsage"] as? [String: Any] else {
            throw CursorUsageError.parseFailed("缺少 planUsage")
        }
        let spend = usage["spendLimitUsage"] as? [String: Any]
        let plan = planData.flatMap { try? jsonObject($0) }
        let planInfo = plan?["planInfo"] as? [String: Any]

        let includedSpend = int(planUsage["includedSpend"]) ?? int(planUsage["totalSpend"]) ?? 0
        let limit = int(planUsage["limit"]) ?? int(planInfo?["includedAmountCents"]) ?? 0
        let onDemandSpend = int(spend?["individualUsed"]) ?? int(spend?["totalSpend"]) ?? 0
        let onDemandLimit = int(spend?["individualLimit"]) ?? int(spend?["pooledLimit"])
        let cycleEnd = date(from: usage["billingCycleEnd"]) ?? date(from: planInfo?["billingCycleEnd"])
        let planName = (planInfo?["planName"] as? String)
            ?? credentials.membershipType.map(displayPlanName)
            ?? "Cursor"
        let price = planInfo?["price"] as? String

        return CursorUsageSnapshot(
            planName: planName,
            priceLabel: price,
            email: credentials.email,
            includedSpendCents: includedSpend,
            includedLimitCents: limit,
            bonusSpendCents: int(planUsage["bonusSpend"]) ?? 0,
            totalPercentUsed: number(planUsage["totalPercentUsed"]),
            autoPercentUsed: number(planUsage["autoPercentUsed"]),
            apiPercentUsed: number(planUsage["apiPercentUsed"]),
            onDemandSpendCents: onDemandSpend,
            onDemandLimitCents: onDemandLimit,
            billingCycleEnd: cycleEnd,
            fetchedAt: fetchedAt
        )
    }

    private static func displayPlanName(_ membership: String) -> String {
        switch membership.lowercased() {
        case "pro": "Pro"
        case "pro_plus", "pro-plus": "Pro+"
        case "ultra": "Ultra"
        case "business", "team": "Team"
        case "free": "Free"
        default: membership
        }
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorUsageError.parseFailed("响应不是 JSON 对象")
        }
        return json
    }

    private static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Double:
            return Int(number.rounded())
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text) ?? Double(text).map { Int($0.rounded()) }
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let text as String:
            return Double(text) ?? 0
        default:
            return 0
        }
    }

    private static func date(from value: Any?) -> Date? {
        let millis = number(value)
        guard millis > 0 else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: CursorUsageError.tokenNotFound)
                    return
                }
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CursorUsageError.tokenNotFound)
            }
        }
    }
}
