@testable import CodexNotch
import XCTest

final class AgentUsageTests: XCTestCase {
    func testTotalTokensFormatsAsMillionsWithOneDecimalPlace() {
        let day = AgentUsageDay(
            day: date("2026-07-01T00:00:00Z"),
            dayKey: "2026-07-01",
            totalTokens: 22_100_000,
            level: 4
        )

        XCTAssertEqual(day.totalTokensInMillions, "22.1M")
    }

    func testQueueAggregationKeepsLatestBucketAndFills365Days() {
        let data = Data(#"""
        {"source":"codex","model":"gpt","hour_start":"2026-07-01T01:00:00.000Z","total_tokens":100,"billable_total_tokens":100}
        {"source":"codex","model":"gpt","hour_start":"2026-07-01T01:00:00.000Z","total_tokens":180,"billable_total_tokens":180}
        malformed
        {"source":"opencode","model":"glm","hour_start":"2026-07-01T02:00:00.000Z","total_tokens":20}
        {"source":"antigravity","model":"gemini","hour_start":"2026-06-30T03:00:00.000Z","total_tokens":40}
        """#.utf8)
        let calendar = utcCalendar()
        let now = date("2026-07-01T12:00:00Z")

        let snapshot = AgentTokenTrackerUsageProvider.makeSnapshot(
            from: data,
            calendar: calendar,
            now: now,
            fetchedAt: now
        )

        XCTAssertEqual(snapshot.days.count, 365)
        XCTAssertEqual(snapshot.totalTokens, 240)
        XCTAssertEqual(snapshot.activeDays, 2)
        XCTAssertEqual(snapshot.sources, ["antigravity", "codex", "opencode"])
        XCTAssertEqual(snapshot.days.suffix(2).map(\.totalTokens), [40, 200])
    }

    func testQueueAggregationUsesTotalTokensForEveryAgentSource() {
        let data = Data(#"""
        {"source":"codex","model":"gpt","hour_start":"2026-07-01T01:00:00Z","total_tokens":100,"billable_total_tokens":90}
        {"source":"antigravity","model":"gemini","hour_start":"2026-07-01T02:00:00Z","total_tokens":200,"billable_total_tokens":0}
        {"source":"opencode","model":"glm","hour_start":"2026-07-01T03:00:00Z","total_tokens":300,"billable_total_tokens":0}
        {"source":"mimo","model":"mimo","hour_start":"2026-07-01T04:00:00Z","total_tokens":400,"billable_total_tokens":0}
        """#.utf8)
        let now = date("2026-07-01T12:00:00Z")

        let snapshot = AgentTokenTrackerUsageProvider.makeSnapshot(
            from: data,
            calendar: utcCalendar(),
            now: now,
            fetchedAt: now
        )

        XCTAssertEqual(snapshot.days.last?.totalTokens, 1_000)
        XCTAssertEqual(snapshot.totalTokens, 1_000)
        XCTAssertEqual(snapshot.sources, ["antigravity", "codex", "mimo", "opencode"])
    }

    func testHeatLevelsUseFourRelativeBands() {
        let data = Data(#"""
        {"source":"codex","model":"gpt","hour_start":"2026-06-28T01:00:00Z","total_tokens":50}
        {"source":"codex","model":"gpt","hour_start":"2026-06-29T01:00:00Z","total_tokens":70}
        {"source":"codex","model":"gpt","hour_start":"2026-06-30T01:00:00Z","total_tokens":85}
        {"source":"codex","model":"gpt","hour_start":"2026-07-01T01:00:00Z","total_tokens":100}
        """#.utf8)
        let now = date("2026-07-01T12:00:00Z")

        let snapshot = AgentTokenTrackerUsageProvider.makeSnapshot(
            from: data,
            calendar: utcCalendar(),
            now: now,
            fetchedAt: now
        )

        XCTAssertEqual(snapshot.days.suffix(4).map(\.level), [1, 2, 3, 4])
    }

    func testCollectorPrefersConfiguredExecutable() {
        let command = AgentTokenTrackerUsageProvider.resolveCollectorCommand(
            environment: ["HOME": "/tmp/home", "TOKENTRACKER_PATH": "/custom/tokentracker"],
            isExecutable: { $0 == "/custom/tokentracker" }
        )

        XCTAssertEqual(
            command,
            .init(executable: "/custom/tokentracker", arguments: ["sync", "--auto"])
        )
    }

    func testCollectorFallsBackToPinnedNpxWithoutServeCommand() {
        let command = AgentTokenTrackerUsageProvider.resolveCollectorCommand(
            environment: ["HOME": "/tmp/home"],
            isExecutable: { $0 == "/opt/homebrew/bin/npx" }
        )

        XCTAssertEqual(command?.executable, "/opt/homebrew/bin/npx")
        XCTAssertEqual(
            command?.arguments,
            ["--yes", "tokentracker-cli@0.64.2", "sync", "--auto"]
        )
        XCTAssertFalse(command?.arguments.contains("serve") ?? true)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
