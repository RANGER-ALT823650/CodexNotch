import Foundation

protocol UsageResetNotifying: Sendable {
    func notifyUnexpectedReset(_ reset: UnexpectedUsageReset) async throws
}

enum UsageResetNotificationError: LocalizedError {
    case openClawNotInstalled
    case telegramTargetMissing
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .openClawNotInstalled:
            "未找到 OpenClaw CLI，无法发送 Codex 重置提醒。"
        case .telegramTargetMissing:
            "未找到 Telegram 目标，请设置 CODEX_NOTCH_TELEGRAM_TARGET。"
        case let .sendFailed(message):
            "OpenClaw 发送 Telegram 提醒失败：\(message)"
        }
    }
}

struct OpenClawTelegramResetNotifier: UsageResetNotifying {
    private let executableResolver: @Sendable () -> String?
    private let targetResolver: @Sendable () -> String?

    init(
        executableResolver: @escaping @Sendable () -> String? = Self.resolveExecutable,
        targetResolver: @escaping @Sendable () -> String? = Self.resolveTelegramTarget
    ) {
        self.executableResolver = executableResolver
        self.targetResolver = targetResolver
    }

    func notifyUnexpectedReset(_ reset: UnexpectedUsageReset) async throws {
        guard let executable = executableResolver() else {
            throw UsageResetNotificationError.openClawNotInstalled
        }
        guard let target = targetResolver(), !target.isEmpty else {
            throw UsageResetNotificationError.telegramTargetMissing
        }

        let message = Self.message(for: reset)
        try await Task.detached(priority: .utility) {
            let process = Process()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [
                "message", "send",
                "--channel", "telegram",
                "--target", target,
                "--message", message,
                "--json",
            ]
            process.standardOutput = Pipe()
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                throw UsageResetNotificationError.sendFailed(error.localizedDescription)
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = stderr.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw UsageResetNotificationError.sendFailed(
                    detail?.isEmpty == false ? detail! : "退出码 \(process.terminationStatus)"
                )
            }
        }.value
    }

    static func message(for reset: UnexpectedUsageReset) -> String {
        let previous = reset.previous.usedPercent.formatted(.number.precision(.fractionLength(1)))
        let current = reset.current.usedPercent.formatted(.number.precision(.fractionLength(1)))
        let observedAt = reset.current.fetchedAt.formatted(date: .abbreviated, time: .shortened)
        let scheduled = reset.previous.resetsAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
        return """
        ⚠️ Codex 一周用量疑似被提前重置
        已用量：\(previous)% → \(current)%
        检测时间：\(observedAt)
        原定自动重置：\(scheduled)

        该变化发生在 7 天周期到期前，并已由约 10 分钟内的连续多次查询确认，且未在 Codex Notch 中标记为本人手动 Reset。
        """
    }

    private static func resolveExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["OPENCLAW_PATH"],
            "/opt/homebrew/bin/openclaw",
            "/usr/local/bin/openclaw",
            environment["HOME"].map { "\($0)/.local/bin/openclaw" },
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func resolveTelegramTarget() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let explicit = environment["CODEX_NOTCH_TELEGRAM_TARGET"], !explicit.isEmpty {
            return explicit
        }

        guard let home = environment["HOME"] else { return nil }
        let configURL = URL(fileURLWithPath: home)
            .appending(path: ".openclaw/openclaw.json")
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = root["channels"] as? [String: Any],
              let telegram = channels["telegram"] as? [String: Any],
              let allowFrom = telegram["allowFrom"] as? [Any]
        else {
            return nil
        }

        return allowFrom.lazy.compactMap { value in
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }.first
    }
}
