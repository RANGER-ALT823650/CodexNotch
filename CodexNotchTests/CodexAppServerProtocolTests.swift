@testable import CodexNotch
import XCTest

final class CodexAppServerProtocolTests: XCTestCase {
    func testDecodesCodexRateLimitResponse() throws {
        let data = Data(
            #"{"rateLimits":{"primary":{"usedPercent":24,"windowDurationMins":300,"resetsAt":1782554080},"secondary":{"usedPercent":77,"windowDurationMins":10080,"resetsAt":1782646545}},"rateLimitsByLimitId":null}"#.utf8
        )

        let response = try CodexAppServerUsageProvider.decodeRateLimitsResult(from: data)
        let snapshot = try CodexAppServerUsageProvider.makeSnapshot(
            from: response,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.primary.remainingPercent, 76)
        XCTAssertEqual(snapshot.primary.durationMinutes, 300)
        XCTAssertEqual(snapshot.secondary.remainingPercent, 23)
        XCTAssertEqual(snapshot.secondary.durationMinutes, 10_080)
    }

    func testPrefersCodexBucketFromMultiBucketResponse() throws {
        let data = Data(
            #"{"rateLimits":{"primary":{"usedPercent":90},"secondary":{"usedPercent":90}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":10,"windowDurationMins":300},"secondary":{"usedPercent":20,"windowDurationMins":10080}}}}"#.utf8
        )

        let response = try CodexAppServerUsageProvider.decodeRateLimitsResult(from: data)
        let snapshot = try CodexAppServerUsageProvider.makeSnapshot(from: response, fetchedAt: .now)

        XCTAssertEqual(snapshot.primary.remainingPercent, 90)
        XCTAssertEqual(snapshot.secondary.remainingPercent, 80)
    }
}
