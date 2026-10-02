@testable import CodexNotch
import XCTest

final class ClaudeUsageTests: XCTestCase {
    func testExtractTokenFromProcessCommand() {
        let sample = "something /usr/bin/node /path/to/claude CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-test_token_1234567890-XYZ CLAUDE_CODE_SUBSCRIPTION_TYPE=pro"
        let token = ClaudeUsageProvider.extractToken(from: sample)
        XCTAssertEqual(token, "sk-ant-oat01-test_token_1234567890-XYZ")
    }

    func testExtractTokenReturnsNilWhenMissing() {
        let sample = "something /usr/bin/node /path/to/other OTHER_TOKEN=abc"
        XCTAssertNil(ClaudeUsageProvider.extractToken(from: sample))
    }

    func testParseResponseWithCompleteData() throws {
        let json = """
        {
          "five_hour": {
            "utilization": 15.5,
            "resets_at": "2026-09-23T11:40:00.213529+00:00"
          },
          "seven_day": {
            "utilization": 5.0,
            "resets_at": "2026-09-25T19:00:00.213555+00:00"
          },
          "seven_day_breakdown": {
            "rows": [
              {"key": "claude_code", "display_name": "Claude Code", "percent": 86},
              {"key": "chat", "display_name": "Chats", "percent": 14}
            ]
          }
        }
        """

        let snapshot = try ClaudeUsageProvider.parseResponse(
            data: Data(json.utf8),
            account: (email: "user@example.com", billingType: "apple_subscription")
        )

        // 5-hour window
        XCTAssertNotNil(snapshot.primary)
        XCTAssertEqual(snapshot.primary?.title, "5 小时")
        XCTAssertEqual(snapshot.primary?.usedPercent, 15.5)
        XCTAssertEqual(snapshot.primary?.remainingPercent, 84.5)
        XCTAssertEqual(snapshot.primary?.durationMinutes, 300)
        XCTAssertNotNil(snapshot.primary?.resetsAt)

        // 7-day window
        XCTAssertEqual(snapshot.secondary.title, "一周")
        XCTAssertEqual(snapshot.secondary.usedPercent, 5.0)
        XCTAssertEqual(snapshot.secondary.remainingPercent, 95.0)
        XCTAssertEqual(snapshot.secondary.durationMinutes, 10_080)
        XCTAssertNotNil(snapshot.secondary.resetsAt)

        // Breakdown & Account
        XCTAssertEqual(snapshot.breakdown.count, 2)
        XCTAssertEqual(snapshot.breakdown[0].displayName, "Claude Code")
        XCTAssertEqual(snapshot.breakdown[0].percent, 86)
        XCTAssertEqual(snapshot.accountEmail, "user@example.com")
        XCTAssertEqual(snapshot.billingType, "apple_subscription")
    }

    func testParseResponseWithMissingFiveHour() throws {
        let json = """
        {
          "seven_day": {
            "utilization": 0.0,
            "resets_at": null
          }
        }
        """

        let snapshot = try ClaudeUsageProvider.parseResponse(data: Data(json.utf8))
        XCTAssertNil(snapshot.primary)
        XCTAssertEqual(snapshot.secondary.usedPercent, 0.0)
        XCTAssertEqual(snapshot.secondary.remainingPercent, 100.0)
        XCTAssertEqual(snapshot.secondary.durationMinutes, 10_080)
        XCTAssertTrue(snapshot.breakdown.isEmpty)
    }
}
