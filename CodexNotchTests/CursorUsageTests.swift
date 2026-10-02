@testable import CodexNotch
import XCTest

final class CursorUsageTests: XCTestCase {
    func testParseAuthRows() {
        let text = """
        cursorAuth/accessToken|access-token
        cursorAuth/refreshToken|refresh-token
        cursorAuth/cachedEmail|user@example.com
        cursorAuth/stripeMembershipType|pro
        """
        let credentials = CursorUsageProvider.parseAuthRows(text)
        XCTAssertEqual(credentials?.accessToken, "access-token")
        XCTAssertEqual(credentials?.refreshToken, "refresh-token")
        XCTAssertEqual(credentials?.email, "user@example.com")
        XCTAssertEqual(credentials?.membershipType, "pro")
    }

    func testJwtExpiration() throws {
        let header = Data("{}".utf8).base64EncodedString()
        let payloadJSON = #"{"exp":1771077734}"#
        let payload = Data(payloadJSON.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(header).\(payload).sig"
        let expiry = try XCTUnwrap(CursorUsageProvider.jwtExpiration(token: token))
        XCTAssertEqual(expiry.timeIntervalSince1970, 1_771_077_734, accuracy: 0.001)
        XCTAssertTrue(CursorUsageProvider.needsRefresh(token: token, now: expiry.addingTimeInterval(-30)))
        XCTAssertFalse(CursorUsageProvider.needsRefresh(token: token, now: expiry.addingTimeInterval(-600)))
    }

    func testMakeSnapshotUsesIncludedSpendAgainstPlanLimit() throws {
        let usage = """
        {
          "billingCycleStart": "1768399334000",
          "billingCycleEnd": "1771077734000",
          "planUsage": {
            "totalSpend": 23222,
            "includedSpend": 23222,
            "bonusSpend": 150,
            "remaining": 16778,
            "limit": 40000,
            "autoPercentUsed": 12.5,
            "apiPercentUsed": 46.444,
            "totalPercentUsed": 15.48
          },
          "spendLimitUsage": {
            "totalSpend": 250,
            "individualLimit": 10000,
            "individualUsed": 250,
            "limitType": "user"
          }
        }
        """
        let plan = """
        {
          "planInfo": {
            "planName": "Ultra",
            "includedAmountCents": 40000,
            "price": "$200/mo",
            "billingCycleEnd": "1771077734000"
          }
        }
        """
        let snapshot = try CursorUsageProvider.makeSnapshot(
            usageData: Data(usage.utf8),
            planData: Data(plan.utf8),
            credentials: CursorCredentials(
                accessToken: "token",
                email: "user@example.com",
                membershipType: "pro"
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(snapshot.planName, "Ultra")
        XCTAssertEqual(snapshot.priceLabel, "$200/mo")
        XCTAssertEqual(snapshot.email, "user@example.com")
        XCTAssertEqual(snapshot.includedSpendCents, 23222)
        XCTAssertEqual(snapshot.includedLimitCents, 40000)
        XCTAssertEqual(snapshot.grokWindow.title, "Grok")
        XCTAssertEqual(snapshot.grokWindow.usedPercent, 12.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.otherWindow.usedPercent, 46.444, accuracy: 0.001)
        XCTAssertEqual(snapshot.otherWindow.title, "其他")
        XCTAssertEqual(snapshot.planUsedPercent, 58.055, accuracy: 0.001)
        XCTAssertEqual(snapshot.bonusSpendCents, 150)
        XCTAssertEqual(snapshot.onDemandSpendCents, 250)
        XCTAssertEqual(snapshot.onDemandLimitCents, 10000)
        XCTAssertEqual(snapshot.billingCycleEnd?.timeIntervalSince1970 ?? 0, 1_771_077_734, accuracy: 0.001)
        XCTAssertEqual(CursorUsageSnapshot.dollars(23222), "$232.22")
        XCTAssertEqual(CursorUsageSnapshot.dollars(40000), "$400")
    }

    func testMakeSnapshotFallsBackToMembershipName() throws {
        let usage = """
        {
          "billingCycleEnd": 1771077734000,
          "planUsage": {
            "includedSpend": "0",
            "limit": "2000",
            "apiPercentUsed": "0"
          }
        }
        """
        let snapshot = try CursorUsageProvider.makeSnapshot(
            usageData: Data(usage.utf8),
            planData: nil,
            credentials: CursorCredentials(accessToken: "token", membershipType: "pro")
        )
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.planUsedPercent, 0)
        XCTAssertEqual(snapshot.grokWindow.remainingPercent, 100)
        XCTAssertEqual(snapshot.otherWindow.remainingPercent, 100)
        XCTAssertNil(snapshot.priceLabel)
    }
}
