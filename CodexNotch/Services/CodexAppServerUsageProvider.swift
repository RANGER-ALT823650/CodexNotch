// Portions of the process and JSONL RPC structure are adapted from CodexBar.
// CodexBar is Copyright (c) 2026 Peter Steinberger and licensed under MIT.

import Foundation

actor CodexAppServerUsageProvider: CodexUsageProviding {
    private let executableResolver: @Sendable () -> String?

    init() {
        executableResolver = Self.resolveCodexExecutable
    }

    init(executableResolver: @escaping @Sendable () -> String?) {
        self.executableResolver = executableResolver
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard let executable = executableResolver() else {
            throw CodexUsageError.codexNotInstalled
        }

        let client = try CodexRPCClient(executable: executable)
        defer { client.shutdown() }

        try await client.initialize()
        let response = try await client.fetchRateLimits()
        return try Self.makeSnapshot(from: response, fetchedAt: Date())
    }

    static func decodeRateLimitsResult(from data: Data) throws -> CodexRateLimitsResponse {
        try JSONDecoder().decode(CodexRateLimitsResponse.self, from: data)
    }

    static func makeSnapshot(
        from response: CodexRateLimitsResponse,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let limits = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        // NOTE: Codex 已取消 5 小时限额。API 可能只返回 primary（周限额被提升为
        // 唯一窗口），也可能仍返回 secondary。优先使用 secondary，降级到 primary。
        // guard let primary = limits.primary, let secondary = limits.secondary else {
        guard let weekly = limits.secondary ?? limits.primary else {
            throw CodexUsageError.missingRateLimits
        }

        return UsageSnapshot(
            // 只有当 secondary 存在时，primary 才可能是独立的 5h 窗口
            primary: limits.secondary != nil ? limits.primary?.usageWindow : nil,
            secondary: weekly.usageWindow,
            fetchedAt: fetchedAt
        )
    }

    private static func resolveCodexExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["CODEX_PATH"],
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            environment["HOME"].map { "\($0)/.local/bin/codex" },
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

struct CodexRateLimitsResponse: Decodable, Sendable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
        case rateLimitsByLimitIdSnake = "rate_limits_by_limit_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try container.decode(CodexRateLimitSnapshot.self, forKey: .rateLimits)
        rateLimitsByLimitId =
            (try? container.decodeIfPresent([String: CodexRateLimitSnapshot].self, forKey: .rateLimitsByLimitId))
            ?? (try? container.decodeIfPresent([String: CodexRateLimitSnapshot].self, forKey: .rateLimitsByLimitIdSnake))
    }
}

struct CodexRateLimitSnapshot: Decodable, Sendable {
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
}

struct CodexRateLimitWindow: Decodable, Sendable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?

    var usageWindow: UsageWindow {
        UsageWindow(
            usedPercent: usedPercent,
            durationMinutes: windowDurationMins,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private final class CodexRPCClient: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutLines: AsyncStream<Data>
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private var nextID = 1

    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrain(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                if !line.isEmpty { lines.append(line) }
            }
            return lines
        }
    }

    init(executable: String) throws {
        let stream = AsyncStream.makeStream(of: Data.self)
        stdoutLines = stream.stream
        stdoutContinuation = stream.continuation

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "-s", "read-only", "-a", "untrusted", "app-server", "--stdio"]
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let buffer = LineBuffer()
        let continuation = stdoutContinuation
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                continuation.finish()
                return
            }
            for line in buffer.appendAndDrain(data) {
                continuation.yield(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        do {
            try process.run()
        } catch {
            throw CodexUsageError.processStartFailed(error.localizedDescription)
        }
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "codex-notch",
                    "title": "Codex Notch",
                    "version": "0.1.0",
                ],
            ],
            timeout: 8
        )
        try sendNotification(method: "initialized")
    }

    func fetchRateLimits() async throws -> CodexRateLimitsResponse {
        let message = try await request(method: "account/rateLimits/read", timeout: 8)
        guard let result = message["result"] else {
            throw CodexUsageError.malformedResponse("缺少 result 字段")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try CodexAppServerUsageProvider.decodeRateLimitsResult(from: data)
    }

    func shutdown() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutContinuation.finish()
        if process.isRunning { process.terminate() }
    }

    private func request(
        method: String,
        params: [String: Any] = [:],
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try sendPayload(["id": id, "method": method, "params": params])

        return try await withThrowingTaskGroup(of: SendableMessage.self) { group in
            group.addTask { [weak self] in
                guard let self else {
                    throw CodexUsageError.malformedResponse("连接已关闭")
                }
                while true {
                    let message = try await self.readNextMessage()
                    guard self.messageID(message["id"]) == id else { continue }
                    if let error = message["error"] as? [String: Any] {
                        let text = error["message"] as? String ?? "未知错误"
                        throw CodexUsageError.requestFailed(text)
                    }
                    return SendableMessage(value: message)
                }
            }
            group.addTask { [weak self] in
                try await Task.sleep(for: .seconds(timeout))
                self?.terminateForTimeout()
                throw CodexUsageError.timeout(method)
            }

            do {
                guard let result = try await group.next() else {
                    throw CodexUsageError.timeout(method)
                }
                group.cancelAll()
                return result.value
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func terminateForTimeout() {
        if process.isRunning { process.terminate() }
    }

    private func sendNotification(method: String) throws {
        try sendPayload(["method": method, "params": [:]])
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await line in stdoutLines {
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                return message
            }
        }
        throw CodexUsageError.malformedResponse("app-server 关闭了输出")
    }

    private func messageID(_ value: Any?) -> Int? {
        switch value {
        case let id as Int:
            id
        case let number as NSNumber:
            number.intValue
        default:
            nil
        }
    }

    private struct SendableMessage: @unchecked Sendable {
        let value: [String: Any]
    }
}
