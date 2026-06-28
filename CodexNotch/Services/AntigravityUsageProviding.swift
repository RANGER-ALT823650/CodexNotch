protocol AntigravityUsageProviding: Sendable {
    func fetchUsage() async throws -> AntigravityUsageSnapshot
    func shutdown() async
}

extension AntigravityUsageProviding {
    func shutdown() async {}
}

