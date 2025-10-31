import Foundation
import SwiftData

public final class APIRequestLogger: @unchecked Sendable {
    public static let shared = APIRequestLogger()
    private init() {}

    // Convenience when start/end are known externally
    public func log(endpoint: String, fullEndpoint: String, method: String = "GET", startedAt: Date, endedAt: Date = Date(), status: APIRequestLog.Status = .success, code: Int? = nil, errorDescription: String? = nil, context: ModelContext? = nil) {
        let durationMs = endedAt.timeIntervalSince(startedAt) * 1000.0
        let log = APIRequestLog(endpoint: endpoint, fullEndpoint: fullEndpoint, method: method, startedAt: startedAt, durationMs: durationMs, status: status, code: code, errorDescription: errorDescription)
        
        if let context {
            Task { await APIRequestStore.shared.insert(log, in: context) }
        }
    }
}
