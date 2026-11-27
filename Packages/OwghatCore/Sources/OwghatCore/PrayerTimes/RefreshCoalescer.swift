import Foundation

/// Serializes schedule refreshes without dropping requests made while one is in flight.
///
/// A request that arrives during a running refresh is queued; when the running refresh
/// finishes, exactly one follow-up run happens with the latest settings. Several requests
/// queued during one run collapse into that single follow-up, which is forced if any of
/// them was forced.
public struct RefreshCoalescer: Sendable, Equatable {
    public private(set) var isRunning = false
    public private(set) var queuedForce: Bool?

    public init() {}

    /// Call before refreshing. Returns `true` when the caller should run now;
    /// `false` when a refresh is already running and this request was queued.
    public mutating func begin(force: Bool) -> Bool {
        if isRunning {
            queuedForce = (queuedForce ?? false) || force
            return false
        }
        isRunning = true
        return true
    }

    /// Call after a refresh run. Returns the `force` flag for the follow-up run the caller
    /// must perform now, or `nil` when nothing is queued (the coalescer is then idle).
    public mutating func finish() -> Bool? {
        guard isRunning else { return nil }
        if let queued = queuedForce {
            queuedForce = nil
            return queued
        }
        isRunning = false
        return nil
    }
}
