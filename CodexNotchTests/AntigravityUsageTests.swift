@testable import CodexNotch
import XCTest

final class AntigravityUsageTests: XCTestCase {
    func testParsesQuotaSummaryGroupsAndBuckets() throws {
        let data = Data(#"""
        {
          "code": 0,
          "response": {
            "groups": [
              {
                "displayName": "Gemini Models",
                "buckets": [
                  {
                    "bucketId": "gemini-5h",
                    "displayName": "5-hour",
                    "remaining": {"case": "remainingFraction", "value": 0.72},
                    "resetTime": "2026-06-27T12:34:56Z"
                  },
                  {
                    "bucketId": "gemini-weekly",
                    "displayName": "Weekly",
                    "remainingFraction": 0.44
                  }
                ]
              },
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {
                    "bucketId": "claude-gpt-weekly",
                    "displayName": "Weekly",
                    "remainingFraction": 0.19
                  }
                ]
              }
            ]
          }
        }
        """#.utf8)

        let snapshot = try AntigravityQuotaParser.parse(data, source: .app)

        XCTAssertEqual(snapshot.groups.map(\.title), ["Gemini", "Claude / GPT"])
        XCTAssertEqual(snapshot.groups[0].buckets.map(\.title), ["5 小时", "一周"])
        XCTAssertEqual(snapshot.groups[0].buckets[0].remainingPercent, 72)
        XCTAssertNotNil(snapshot.groups[0].buckets[0].resetsAt)
        XCTAssertEqual(snapshot.groups[1].buckets[0].remainingPercent, 19)
    }

    func testParsesAntigravityProcessesWithoutExposingToken() throws {
        let output = """
          101 /Applications/Antigravity.app/Contents/Resources/bin/language_server_macos_arm --csrf_token secret-token --app_data_dir antigravity
          202 /Users/test/.local/bin/agy
          303 /usr/bin/other
        """

        let processes = try AntigravityLocalUsageProvider.parseProcesses(output)

        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].pid, 101)
        XCTAssertEqual(processes[0].kind, .app)
        XCTAssertEqual(processes[0].csrfToken, "secret-token")
        XCTAssertEqual(processes[1].kind, .cli)
        XCTAssertEqual(processes[1].csrfToken, "")
    }

    func testParsesUniqueListeningPorts() {
        let output = """
        language_ 101 user 10u IPv4 0x0 0t0 TCP 127.0.0.1:42100 (LISTEN)
        language_ 101 user 11u IPv6 0x0 0t0 TCP *:42100 (LISTEN)
        language_ 101 user 12u IPv4 0x0 0t0 TCP 127.0.0.1:42101 (LISTEN)
        """

        XCTAssertEqual(AntigravityLocalUsageProvider.parseListeningPorts(output), [42100, 42101])
    }

    func testCLIProcessTokenIsSentToQuotaEndpoint() throws {
        let processes = try AntigravityLocalUsageProvider.parseProcesses("""
          202 /Users/test/.local/bin/agy --csrf_token test-session-token
          203 agy --csrf_token=another-session-token
          204 agy
        """)

        XCTAssertEqual(processes.map(\.csrfToken), ["test-session-token", "another-session-token", ""])
        for process in processes {
            let request = try AntigravityLocalUsageProvider.quotaRequest(endpoint: .init(
                scheme: "https", port: 42100, csrfToken: process.csrfToken, source: .cli
            ))
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token"),
                process.csrfToken.isEmpty ? nil : process.csrfToken
            )
        }
    }

    func testDesktopQuotaRequestStillSendsCSRFToken() throws {
        let request = try AntigravityLocalUsageProvider.quotaRequest(endpoint: .init(
            scheme: "https", port: 42100, csrfToken: "desktop-session-token", source: .app
        ))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Codeium-Csrf-Token"), "desktop-session-token")
    }

    func testCSRFResponseIsNotOverwrittenByOtherPortTLSFailure() {
        let response = Data(#"{"code":"unauthenticated","message":"missing CSRF token"}"#.utf8)
        let apiError = AntigravityLocalUsageProvider.responseError(statusCode: 401, data: response)
        XCTAssertEqual(apiError, .csrfRejected)

        let tlsError = URLError(.secureConnectionFailed)
        let selected = AntigravityLocalUsageProvider.preferredError(tlsError, over: apiError)
        XCTAssertEqual(selected as? AntigravityUsageError, .csrfRejected)
        let laterProcessError = AntigravityLocalUsageProvider.preferredError(
            AntigravityUsageError.noListeningPort, over: selected
        )
        XCTAssertEqual(laterProcessError as? AntigravityUsageError, .csrfRejected)
    }

    func testNotLoggedInReturnsAuthenticationRequired() {
        let response = Data(#"{"code":"internal","message":"internal: failed to get load code assist response: error getting token source: You are not logged into Antigravity."}"#.utf8)
        let error = AntigravityLocalUsageProvider.responseError(statusCode: 500, data: response)
        XCTAssertEqual(error, .authenticationRequired)
    }

    func testAuthenticationRequiredIsNotOverwrittenByCSRFRejected() {
        let authError = AntigravityUsageError.authenticationRequired
        let csrfError = AntigravityUsageError.csrfRejected
        let selected = AntigravityLocalUsageProvider.preferredError(csrfError, over: authError)
        XCTAssertEqual(selected as? AntigravityUsageError, .authenticationRequired)
    }

    func testAPIErrorsAreNotOverwrittenByCSRFRejected() {
        let apiError = AntigravityUsageError.api("HTTP 500")
        let csrfError = AntigravityUsageError.csrfRejected
        let selected = AntigravityLocalUsageProvider.preferredError(csrfError, over: apiError)
        XCTAssertEqual(selected as? AntigravityUsageError, .api("HTTP 500"))
    }
}
