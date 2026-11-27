import Foundation

/// Tracks retry delays after failed schedule refreshes to prevent polling storms.
public struct RefreshBackoff: Sendable, Equatable {
    public static let defaultDelays: [TimeInterval] = [30, 120, 300]

    private let delays: [TimeInterval]
    public private(set) var failureCount: Int = 0
    public private(set) var nextAllowedAttempt: Date?

    public init(delays: [TimeInterval] = RefreshBackoff.defaultDelays) {
        self.delays = delays.isEmpty ? Self.defaultDelays : delays
    }

    /// Resets failure state after a successful refresh.
    public mutating func recordSuccess() {
        failureCount = 0
        nextAllowedAttempt = nil
    }

    /// Records a failed refresh at `date` and returns the scheduled backoff delay in seconds.
    @discardableResult
    public mutating func recordFailure(at date: Date) -> TimeInterval {
        let index = min(failureCount, delays.count - 1)
        let delay = delays[index]
        failureCount += 1
        nextAllowedAttempt = date.addingTimeInterval(delay)
        return delay
    }

    /// Returns true if automatic retries are currently permitted at `date`.
    public func canRetry(at date: Date) -> Bool {
        guard let nextAllowedAttempt else { return true }
        return date >= nextAllowedAttempt
    }
}
