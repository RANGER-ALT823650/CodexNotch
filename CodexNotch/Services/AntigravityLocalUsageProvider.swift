// Portions adapted from CodexBar.
// Copyright 2026 Peter Steinberger
// SPDX-License-Identifier: MIT

import Foundation
import Darwin

enum AntigravityUsageError: LocalizedError, Equatable {
    case notRunning
    case missingCSRFToken
    case csrfRejected
    case binaryNotFound
    case noListeningPort
    case authenticationRequired
    case api(String)
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "未检测到 Antigravity 或 agy"
        case .missingCSRFToken:
            "Antigravity 本地会话缺少 CSRF token，请重启 Antigravity"
        case .csrfRejected:
            "Antigravity 本地接口认证失败：CSRF token 缺失或已失效"
        case .binaryNotFound:
            "未找到 agy；请安装 Antigravity CLI，或先启动 Antigravity 应用"
        case .noListeningPort:
            "Antigravity 已启动，但本地配额接口尚未就绪"
        case .authenticationRequired:
            "agy 尚未登录，请先在终端运行 agy 完成登录"
        case let .api(message):
            "Antigravity 接口错误：\(message)"
        case let .parse(message):
            "无法解析 Antigravity 配额：\(message)"
        }
    }
}

actor AntigravityLocalUsageProvider: AntigravityUsageProviding {
    struct ProcessInfo: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case app, ide, cli }

        let pid: Int
        let kind: Kind
        let csrfToken: String
    }

    struct Endpoint: Sendable {
        let scheme: String
        let port: Int
        let csrfToken: String
        let source: AntigravityUsageSnapshot.Source
    }

    private static let quotaPath =
        "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    private var cliProcess: Process?
    private var cliInputPipe: Pipe?
    private var cliOutputPipe: Pipe?
    private var cliOutput = LockedDataBuffer()
    private var managedCSRFToken: String?

    func fetchUsage() async throws -> AntigravityUsageSnapshot {
        var lastError: Error?
        let current = try await Self.detectProcesses()

        if !current.isEmpty {
            do {
                return try await fetch(from: current)
            } catch {
                try Task.checkCancellation()
                lastError = Self.preferredError(error, over: lastError)
                // If we have a managed CLI process and current processes failed to return quota,
                // terminate the stale managed CLI so a fresh one can be spawned.
                if managedCSRFToken != nil {
                    await stopCLI()
                }
            }
        }

        guard let agyPath = Self.resolveAgyBinary() else {
            throw lastError ?? AntigravityUsageError.binaryNotFound
        }
        try await startCLIIfNeeded(binary: agyPath)

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            try Task.checkCancellation()
            if cliOutput.containsAuthenticationPrompt {
                await stopCLI()
                throw AntigravityUsageError.authenticationRequired
            }

            let processes = try await Self.detectProcesses().filter { $0.kind == .cli }
            if !processes.isEmpty {
                do {
                    return try await fetch(from: processes)
                } catch {
                    try Task.checkCancellation()
                    lastError = Self.preferredError(error, over: lastError)
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        if cliOutput.containsAuthenticationPrompt {
            await stopCLI()
            throw AntigravityUsageError.authenticationRequired
        }
        // If deadline exceeded without success, clean up managed CLI rather than leaving a zombie.
        await stopCLI()
        throw lastError ?? AntigravityUsageError.noListeningPort
    }

    func shutdown() async {
        await stopCLI()
    }

    private func fetch(from processes: [ProcessInfo]) async throws -> AntigravityUsageSnapshot {
        var lastError: Error?
        // Reuse authenticated instances before probing legacy, tokenless ones.
        // If an authenticated candidate exists (Desktop app or CLI with token),
        // skip tokenless CLI processes to avoid spurious 401 CSRF failures.
        let hasAuthenticatedCandidate = processes.contains { !$0.csrfToken.isEmpty }
        let candidates = hasAuthenticatedCandidate
            ? processes.filter { !$0.csrfToken.isEmpty || $0.kind != .cli }
            : processes

        let sorted = candidates.sorted {
            let lhs = processRank($0.kind)
            let rhs = processRank($1.kind)
            if lhs != rhs { return lhs < rhs }
            if $0.csrfToken.isEmpty != $1.csrfToken.isEmpty { return !$0.csrfToken.isEmpty }
            return $0.pid < $1.pid
        }
        for process in sorted {
            try Task.checkCancellation()
            do {
                let ports = try await Self.listeningPorts(pid: process.pid)
                let source: AntigravityUsageSnapshot.Source = process.kind == .cli ? .cli : .app
                let endpoints = ports.map {
                    Endpoint(scheme: "https", port: $0, csrfToken: process.csrfToken, source: source)
                }
                for endpoint in endpoints {
                    do {
                        let data = try await Self.requestQuota(endpoint: endpoint)
                        return try AntigravityQuotaParser.parse(data, source: source)
                    } catch {
                        try Task.checkCancellation()
                        lastError = Self.preferredError(error, over: lastError)
                    }
                }
            } catch {
                try Task.checkCancellation()
                lastError = Self.preferredError(error, over: lastError)
            }
        }
        throw lastError ?? AntigravityUsageError.noListeningPort
    }

    private func processRank(_ kind: ProcessInfo.Kind) -> Int {
        switch kind {
        case .app: 0
        case .ide: 1
        case .cli: 2
        }
    }

    // A real API response is more useful than TLS errors from other listening ports.
    static func preferredError(_ error: Error, over previous: Error?) -> Error {
        func rank(_ error: Error) -> Int {
            guard let usageError = error as? AntigravityUsageError else { return 1 }
            switch usageError {
            case .noListeningPort, .notRunning, .binaryNotFound: return 0
            case .csrfRejected, .missingCSRFToken: return 2
            case .authenticationRequired: return 3
            case .api, .parse: return 4
            }
        }
        guard let previous, rank(previous) > rank(error) else { return error }
        return previous
    }

    private func startCLIIfNeeded(binary: String) async throws {
        if cliProcess?.isRunning == true { return }
        await stopCLI()

        let token = UUID().uuidString
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let buffer = LockedDataBuffer()
        output.fileHandleForReading.readabilityHandler = { handle in
            buffer.append(handle.availableData)
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // Newer agy versions require CSRF even for their localhost CLI API.
        // Set a fresh per-process token rather than reading account credentials.
        process.arguments = ["-q", "/dev/null", binary, "--csrf_token", token]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        process.environment = Foundation.ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
            "NO_COLOR": "1",
        ]) { _, new in new }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw AntigravityUsageError.api("无法启动 agy：\(error.localizedDescription)")
        }

        cliProcess = process
        cliInputPipe = input
        cliOutputPipe = output
        cliOutput = buffer
        managedCSRFToken = token
        ManagedCLIProcessRegistry.shared.register(pid: process.processIdentifier)
    }

    private func stopCLI() async {
        cliOutputPipe?.fileHandleForReading.readabilityHandler = nil
        if let token = managedCSRFToken {
            if let output = try? await Self.runCommand("/bin/ps", arguments: ["-ax", "-o", "pid=,command="]) {
                for line in output.split(separator: "\n") {
                    if line.contains(token) {
                        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1)
                        if let pidStr = parts.first, let pid = pid_t(pidStr) {
                            Darwin.kill(pid, SIGTERM)
                        }
                    }
                }
            }
        }
        if let process = cliProcess {
            ManagedCLIProcessRegistry.shared.clear(pid: process.processIdentifier)
            if process.isRunning {
                process.terminate()
            }
        }
        try? cliInputPipe?.fileHandleForWriting.close()
        try? cliOutputPipe?.fileHandleForReading.close()
        cliProcess = nil
        cliInputPipe = nil
        cliOutputPipe = nil
        cliOutput = LockedDataBuffer()
        managedCSRFToken = nil
    }

    static func parseProcesses(_ output: String) throws -> [ProcessInfo] {
        var matches: [ProcessInfo] = []
        var sawTokenlessDesktop = false

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            let command = String(parts[1])
            guard let kind = processKind(command) else { continue }

            if kind == .cli {
                let token = extractFlag("--csrf_token", from: command) ?? ""
                matches.append(ProcessInfo(pid: pid, kind: kind, csrfToken: token))
            } else if let token = extractFlag("--csrf_token", from: command) {
                matches.append(ProcessInfo(pid: pid, kind: kind, csrfToken: token))
            } else {
                sawTokenlessDesktop = true
            }
        }

        if matches.isEmpty, sawTokenlessDesktop {
            throw AntigravityUsageError.missingCSRFToken
        }
        return matches
    }

    static func parseListeningPorts(_ output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports: Set<Int> = []
        regex.enumerateMatches(in: output, range: range) { match, _, _ in
            guard let match,
                  let matchRange = Range(match.range(at: 1), in: output),
                  let port = Int(output[matchRange])
            else { return }
            ports.insert(port)
        }
        return ports.sorted()
    }

    private static func detectProcesses() async throws -> [ProcessInfo] {
        let output = try await runCommand("/bin/ps", arguments: ["-ax", "-o", "pid=,command="])
        return try parseProcesses(output)
    }

    private static func listeningPorts(pid: Int) async throws -> [Int] {
        let output = try await runCommand(
            "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)],
            allowsExitCodeOne: true
        )
        let ports = parseListeningPorts(output)
        guard !ports.isEmpty else { throw AntigravityUsageError.noListeningPort }
        return ports
    }

    private static func processKind(_ command: String) -> ProcessInfo.Kind? {
        let lower = command.lowercased()
        let languageServerPattern = #"(^|[/\\])language(?:_|-)server(?:[_-][a-z0-9]+)*(?:\.exe)?(\s|$)"#
        let isLanguageServer = lower.range(of: languageServerPattern, options: .regularExpression) != nil
        let isAntigravity = lower.contains("antigravity.app/")
            || lower.contains("antigravity ide.app/")
            || lower.contains("/antigravity/")
            || (lower.contains("--app_data_dir") && lower.contains("antigravity"))
        if isLanguageServer, isAntigravity {
            return lower.contains("antigravity ide.app/")
                || lower.contains("/extensions/antigravity/bin/language_server") ? .ide : .app
        }

        let agyPattern = #"(^|[/\\])agy(\s|$)"#
        let cliPattern = #"(^|[/\\])(antigravity-cli|antigravity_cli)([\s/\\]|$)"#
        if lower.range(of: agyPattern, options: .regularExpression) != nil
            || lower.range(of: cliPattern, options: .regularExpression) != nil
        {
            return .cli
        }
        return nil
    }

    private static func extractFlag(_ flag: String, from command: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: flag)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)[=\\s]+([^\\s]+)") else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let tokenRange = Range(match.range(at: 1), in: command)
        else { return nil }
        return String(command[tokenRange])
    }

    private static func resolveAgyBinary() -> String? {
        let environment = Foundation.ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            environment["ANTIGRAVITY_PATH"],
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func quotaRequest(endpoint: Endpoint) throws -> URLRequest {
        guard let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)\(quotaPath)") else {
            throw AntigravityUsageError.api("无效的本地接口地址")
        }
        let body = try JSONSerialization.data(withJSONObject: ["forceRefresh": true])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if !endpoint.csrfToken.isEmpty {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }
        return request
    }

    static func responseError(statusCode: Int, data: Data) -> AntigravityUsageError {
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = payload?["message"] as? String

        if statusCode == 401 || statusCode == 403 {
            if let message, message.lowercased().contains("csrf") {
                return .csrfRejected
            }
            if let message, message.lowercased().contains("not logged into antigravity") || message.lowercased().contains("login") {
                return .authenticationRequired
            }
        }
        if statusCode == 500,
           let message,
           message.lowercased().contains("not logged into antigravity") {
            return .authenticationRequired
        }
        return .api("HTTP \(statusCode)")
    }

    private static func requestQuota(endpoint: Endpoint) async throws -> Data {
        let request = try quotaRequest(endpoint: endpoint)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        configuration.waitsForConnectivity = false
        let delegate = LocalhostTrustDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AntigravityUsageError.api("本地接口没有返回 HTTP 响应")
        }
        guard response.statusCode == 200 else {
            throw responseError(statusCode: response.statusCode, data: data)
        }
        return data
    }

    private static func runCommand(
        _ executable: String,
        arguments: [String],
        allowsExitCodeOne: Bool = false
    ) async throws -> String {
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
            let allowed = process.terminationStatus == 0 || (allowsExitCodeOne && process.terminationStatus == 1)
            guard allowed else {
                throw AntigravityUsageError.api("\(URL(fileURLWithPath: executable).lastPathComponent) 执行失败")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

final class ManagedCLIProcessRegistry: @unchecked Sendable {
    static let shared = ManagedCLIProcessRegistry()

    private let lock = NSLock()
    private var processIDs: Set<pid_t> = []

    private init() {}

    func register(pid: pid_t) {
        lock.lock()
        processIDs.insert(pid)
        lock.unlock()
    }

    func clear(pid: pid_t) {
        lock.lock()
        processIDs.remove(pid)
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let processIDs = self.processIDs
        self.processIDs.removeAll()
        lock.unlock()
        for processID in processIDs {
            Darwin.kill(processID, SIGTERM)
        }
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ value: Data) {
        guard !value.isEmpty else { return }
        lock.lock()
        data.append(value)
        if data.count > 64 * 1024 {
            data = data.suffix(64 * 1024)
        }
        lock.unlock()
    }

    var containsAuthenticationPrompt: Bool {
        lock.lock()
        let snapshot = data
        lock.unlock()
        let text = String(decoding: snapshot, as: UTF8.self).lowercased()
        return text.contains("select login method")
            || text.contains("choose a login method")
            || text.contains("sign in") && text.contains("antigravity")
    }
}

private final class LocalhostTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["127.0.0.1", "localhost"].contains(space.host.lowercased()),
              let trust = space.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}
