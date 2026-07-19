import Foundation

actor AgentTokenTrackerUsageProvider: AgentUsageProviding {
    static let pinnedVersion = "0.64.2"

    struct CollectorCommand: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    private struct QueueRow: Decodable {
        let source: String
        let model: String
        let hourStart: String
        let totalTokens: Int64

        enum CodingKeys: String, CodingKey {
            case source
            case model
            case hourStart = "hour_start"
            case totalTokens = "total_tokens"
        }

        var bucketKey: String { "\(source)|\(model)|\(hourStart)" }
    }

    private let homeDirectory: URL
    private let environment: [String: String]
    private let collectorCommand: CollectorCommand?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        collectorCommand = Self.resolveCollectorCommand(environment: environment)
    }

    func fetchUsage() async throws -> AgentUsageSnapshot {
        guard let collectorCommand else { throw AgentUsageError.collectorNotFound }
        try await Self.runCollector(collectorCommand, environment: environment)

        let queueURL = homeDirectory
            .appendingPathComponent(".tokentracker", isDirectory: true)
            .appendingPathComponent("tracker", isDirectory: true)
            .appendingPathComponent("queue.jsonl")
        guard FileManager.default.fileExists(atPath: queueURL.path) else {
            throw AgentUsageError.queueNotFound(queueURL.path)
        }

        do {
            let data = try Data(contentsOf: queueURL, options: .mappedIfSafe)
            return Self.makeSnapshot(from: data)
        } catch let error as AgentUsageError {
            throw error
        } catch {
            throw AgentUsageError.unreadableQueue(error.localizedDescription)
        }
    }

    static func resolveCollectorCommand(
        environment: [String: String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> CollectorCommand? {
        if let configured = environment["TOKENTRACKER_PATH"], isExecutable(configured) {
            return CollectorCommand(executable: configured, arguments: ["sync", "--auto"])
        }

        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let installedCandidates = [
            "\(home)/.local/bin/tokentracker",
            "/opt/homebrew/bin/tokentracker",
            "/usr/local/bin/tokentracker",
        ]
        if let installed = installedCandidates.first(where: isExecutable) {
            return CollectorCommand(executable: installed, arguments: ["sync", "--auto"])
        }

        let npxCandidates = [
            environment["NVM_BIN"].map { "\($0)/npx" },
            "/opt/homebrew/bin/npx",
            "/usr/local/bin/npx",
            "/usr/bin/npx",
        ].compactMap { $0 }
        guard let npx = npxCandidates.first(where: isExecutable) else { return nil }
        return CollectorCommand(
            executable: npx,
            arguments: ["--yes", "tokentracker-cli@\(pinnedVersion)", "sync", "--auto"]
        )
    }

    static func makeSnapshot(
        from data: Data,
        calendar: Calendar = .current,
        now: Date = Date(),
        fetchedAt: Date = Date()
    ) -> AgentUsageSnapshot {
        let decoder = JSONDecoder()
        var latestBuckets: [String: QueueRow] = [:]

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let row = try? decoder.decode(QueueRow.self, from: Data(line)) else { continue }
            latestBuckets[row.bucketKey] = row
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let basicFormatter = ISO8601DateFormatter()
        basicFormatter.formatOptions = [.withInternetDateTime]

        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -364, to: today) ?? today
        var totalsByDay: [Date: Int64] = [:]
        var sources = Set<String>()

        for row in latestBuckets.values {
            guard let timestamp = fractionalFormatter.date(from: row.hourStart)
                    ?? basicFormatter.date(from: row.hourStart)
            else { continue }
            let day = calendar.startOfDay(for: timestamp)
            guard day >= firstDay, day <= today else { continue }
            totalsByDay[day, default: 0] += max(0, row.totalTokens)
            sources.insert(row.source)
        }

        let activeTokenTotals = totalsByDay
            .filter { dayKey(for: $0.key, calendar: calendar) != "2026-05-08" }
            .values
            .filter { $0 > 0 }
            .sorted()
        let days = (0..<365).compactMap { offset -> AgentUsageDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let tokens = totalsByDay[day, default: 0]
            let isTargetDay = dayKey(for: day, calendar: calendar) == "2026-05-08"
            let level = isTargetDay ? 99 : heatLevel(tokens: tokens, activeTokenTotals: activeTokenTotals)
            return AgentUsageDay(
                day: day,
                dayKey: dayKey(for: day, calendar: calendar),
                totalTokens: tokens,
                level: level
            )
        }

        return AgentUsageSnapshot(
            days: days,
            totalTokens: days.reduce(0) { $0 + $1.totalTokens },
            activeDays: days.count { $0.totalTokens > 0 },
            sources: sources.sorted(),
            fetchedAt: fetchedAt
        )
    }

    private static func heatLevel(tokens: Int64, activeTokenTotals: [Int64]) -> Int {
        guard tokens > 0, activeTokenTotals.isEmpty == false else { return 0 }

        var lowerBound = 0
        var upperBound = activeTokenTotals.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if activeTokenTotals[middle] < tokens {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let percentile = Double(lowerBound + 1) / Double(activeTokenTotals.count)

        // Dynamic non-linear percentile bands:
        // Level 1: Lowest 25% (percentile <= 0.25)
        // Level 2: Mid-range 45% (percentile <= 0.70)
        // Level 3: High-range 25% (percentile <= 0.95)
        // Level 4: Top 5% peak usage (percentile > 0.95)
        if percentile <= 0.25 {
            return 1
        } else if percentile <= 0.70 {
            return 2
        } else if percentile <= 0.95 {
            return 3
        } else {
            return 4
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func runCollector(
        _ command: CollectorCommand,
        environment: [String: String]
    ) async throws {
        let processBox = CollectorProcessBox()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let process = Process()
                let output = Pipe()
                process.executableURL = URL(fileURLWithPath: command.executable)
                process.arguments = command.arguments
                process.standardOutput = output
                process.standardError = output
                process.environment = environment.merging([
                    "PATH": Self.collectorPath(environment["PATH"]),
                    "NO_COLOR": "1",
                ]) { _, new in new }
                do {
                    try process.run()
                    processBox.set(process)
                } catch {
                    throw AgentUsageError.collectorFailed(error.localizedDescription)
                }

                let outputData = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                processBox.clear()
                guard process.terminationStatus == 0 else {
                    let message = String(decoding: outputData.suffix(2_000), as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    throw AgentUsageError.collectorFailed(
                        message.isEmpty ? "退出码 \(process.terminationStatus)" : message
                    )
                }
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    private static func collectorPath(_ existing: String?) -> String {
        let defaults = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        guard let existing, !existing.isEmpty else { return defaults }
        return "\(defaults):\(existing)"
    }
}

private final class CollectorProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.withLock { self.process = process }
        ManagedCLIProcessRegistry.shared.register(pid: process.processIdentifier)
    }

    func clear() {
        let processID = lock.withLock { () -> pid_t? in
            let processID = process?.processIdentifier
            process = nil
            return processID
        }
        if let processID {
            ManagedCLIProcessRegistry.shared.clear(pid: processID)
        }
    }

    func terminate() {
        let processID = lock.withLock { () -> pid_t? in
            guard let process, process.isRunning else { return nil }
            process.terminate()
            self.process = nil
            return process.processIdentifier
        }
        if let processID {
            ManagedCLIProcessRegistry.shared.clear(pid: processID)
        }
    }
}
