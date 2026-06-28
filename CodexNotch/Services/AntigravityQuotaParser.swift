// Portions adapted from CodexBar.
// Copyright 2026 Peter Steinberger
// SPDX-License-Identifier: MIT

import Foundation

enum AntigravityQuotaParser {
    static func parse(_ data: Data, source: AntigravityUsageSnapshot.Source) throws
        -> AntigravityUsageSnapshot
    {
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let code = response.code, !code.isOK {
            throw AntigravityUsageError.api("Antigravity 返回状态码 \(code.rawValue)")
        }

        let payload = response.response ?? response.summary ?? response.rootPayload
        guard let payload else {
            throw AntigravityUsageError.parse("响应中没有配额摘要")
        }

        let groups = payload.groups.compactMap { group -> AntigravityQuotaGroup? in
            let groupTitle = displayGroupTitle(group.displayName)
            let buckets = (group.buckets ?? []).compactMap { bucket -> AntigravityQuotaBucket? in
                guard let bucketID = nonEmpty(bucket.bucketId) else { return nil }
                return AntigravityQuotaBucket(
                    id: bucketID,
                    groupTitle: groupTitle,
                    title: displayBucketTitle(id: bucketID, name: bucket.displayName),
                    remainingFraction: bucket.remainingFraction ?? bucket.remaining?.remainingFraction,
                    resetsAt: bucket.resetTime.flatMap(parseDate),
                    resetDescription: bucket.description,
                    disabled: bucket.disabled ?? false
                )
            }
            .sorted { bucketRank($0.title) < bucketRank($1.title) }

            guard !buckets.isEmpty else { return nil }
            return AntigravityQuotaGroup(
                id: nonEmpty(group.displayName) ?? groupTitle,
                title: groupTitle,
                buckets: buckets
            )
        }
        .sorted { groupRank($0.title) < groupRank($1.title) }

        guard groups.contains(where: { $0.buckets.contains(where: \.usageKnown) }) else {
            throw AntigravityUsageError.parse("没有可用的配额数据")
        }
        return AntigravityUsageSnapshot(groups: groups, fetchedAt: Date(), source: source)
    }

    private static func displayGroupTitle(_ raw: String?) -> String {
        let title = nonEmpty(raw) ?? "Quota"
        let lower = title.lowercased()
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") { return "Claude / GPT" }
        return title
    }

    private static func displayBucketTitle(id: String, name: String?) -> String {
        let raw = "\(id) \(name ?? "")".lowercased()
        if raw.contains("5h") || raw.contains("5-hour") || raw.contains("five hour") {
            return "5 小时"
        }
        if raw.contains("weekly") || raw.contains("week") {
            return "一周"
        }
        return nonEmpty(name) ?? id
    }

    private static func groupRank(_ title: String) -> Int {
        let lower = title.lowercased()
        if lower.contains("gemini") { return 0 }
        if lower.contains("claude") || lower.contains("gpt") { return 1 }
        return 2
    }

    private static func bucketRank(_ title: String) -> Int {
        if title == "5 小时" { return 0 }
        if title == "一周" { return 1 }
        return 2
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
            ?? Double(value).map { Date(timeIntervalSince1970: $0) }
    }
}

private struct Response: Decodable {
    let code: CodeValue?
    let response: Payload?
    let summary: Payload?
    let description: String?
    let groups: [GroupPayload]?

    var rootPayload: Payload? {
        groups.map { Payload(description: description, groups: $0) }
    }
}

private struct Payload: Decodable {
    let description: String?
    let groups: [GroupPayload]

    init(description: String?, groups: [GroupPayload]) {
        self.description = description
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey { case description, groups }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        groups = try container.decodeIfPresent([GroupPayload].self, forKey: .groups) ?? []
    }
}

private struct GroupPayload: Decodable {
    let displayName: String?
    let buckets: [BucketPayload]?
}

private struct BucketPayload: Decodable {
    let bucketId: String?
    let displayName: String?
    let description: String?
    let disabled: Bool?
    let remainingFraction: Double?
    let remaining: RemainingPayload?
    let resetTime: String?
}

private struct RemainingPayload: Decodable {
    let remainingFraction: Double?

    private enum CodingKeys: String, CodingKey {
        case remainingFraction
        case oneofCase = "case"
        case value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(Double.self, forKey: .remainingFraction) {
            remainingFraction = value
        } else if try container.decodeIfPresent(String.self, forKey: .oneofCase) == "remainingFraction" {
            remainingFraction = try container.decodeIfPresent(Double.self, forKey: .value)
        } else {
            remainingFraction = nil
        }
    }
}

private enum CodeValue: Decodable {
    case int(Int)
    case string(String)

    var isOK: Bool {
        switch self {
        case let .int(value): value == 0
        case let .string(value): ["ok", "success", "0"].contains(value.lowercased())
        }
    }

    var rawValue: String {
        switch self {
        case let .int(value): String(value)
        case let .string(value): value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported code type")
        }
    }
}

