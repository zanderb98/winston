//
//  APIRequestLog.swift
//  winston
//
//  Created by Zander Bobronnikov on 10/31/25.
//

import Foundation
import SwiftData

@Model
public final class APIRequestLog {
    public enum Status: String, Codable, CaseIterable { case success, failure, cancelled }

    @Attribute(.unique) public var id: UUID
    public var endpoint: String
    public var fullEndpoint: String?
    public var method: String
    public var startedAt: Date
    public var durationMs: Double
    public var statusRaw: String
    public var code: Int?
    public var errorDescription: String?

    public var status: Status {
        get { Status(rawValue: statusRaw) ?? .success }
        set { statusRaw = newValue.rawValue }
    }

    public init(id: UUID = UUID(), endpoint: String, fullEndpoint: String?, method: String, startedAt: Date, durationMs: Double, status: Status, code: Int?, errorDescription: String?) {
        self.id = id
        self.endpoint = endpoint
        self.fullEndpoint = fullEndpoint
        self.method = method
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.statusRaw = status.rawValue
        self.code = code
        self.errorDescription = errorDescription
    }
}

public struct APIEndpointStats: Identifiable, Hashable {
    public var id: String { endpoint }
    public let endpoint: String
    public let count: Int
    public let avgMs: Double
    public let maxMs: Double
    public let minMs: Double
}

public actor APIRequestStore {
    public static let shared = APIRequestStore()
    private init() {}

    public func insert(_ log: APIRequestLog, in context: ModelContext) {
        context.insert(log)
        try? context.save()
    }

    public func clearAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<APIRequestLog>()
        if let results = try? context.fetch(descriptor) {
            for obj in results { context.delete(obj) }
            try? context.save()
        }
    }

    public func fetchAll(in context: ModelContext) -> [APIRequestLog] {
        let descriptor = FetchDescriptor<APIRequestLog>(sortBy: [SortDescriptor(\APIRequestLog.startedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func stats(in context: ModelContext) -> [APIEndpointStats] {
        let all = fetchAll(in: context)
        let groups = Dictionary(grouping: all, by: { $0.endpoint })
        return groups.map { endpoint, logs in
            let durations = logs.map { $0.durationMs }
            let count = logs.count
            let avg = durations.reduce(0, +) / Double(max(count, 1))
            let maxV = durations.max() ?? 0
            let minV = durations.min() ?? 0
            return APIEndpointStats(endpoint: endpoint, count: count, avgMs: avg, maxMs: maxV, minMs: minV)
        }.sorted(by: { $0.endpoint < $1.endpoint })
    }
}
