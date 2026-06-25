import Foundation

/// One persisted sticky assignment: the chosen `group` plus the 8-char prefix
/// of the experiment salt (`salt8`) that produced it. The salt prefix is the
/// reshuffle key — changing the experiment salt rotates `salt8`, which
/// invalidates stored entries and forces a re-bucket. Mirrors the canonical
/// `StickyEntry { g, s }` in the TS reference SDK (doc 20 §2).
public struct StickyEntry: Sendable, Equatable {
    /// The assigned group name.
    public let group: String
    /// The 8-char prefix of the experiment salt at assignment time.
    public let salt8: String

    public init(group: String, salt8: String) {
        self.group = group
        self.salt8 = salt8
    }
}

/// Pluggable sticky-bucketing store for the server (doc 20 §2). Keyed by the
/// bucketing unit (the `pickIdentifier`-resolved identifier); the value is that
/// unit's per-experiment assignments keyed by experiment name. Absent from the
/// `Engine` ⇒ today's deterministic behaviour (fully backward compatible). Use
/// `InMemoryStickyBucketStore` or a cookie-bridge built from request cookies.
///
/// Implementations must be `Sendable` because the `Engine` actor holds the
/// store and calls it from its isolated context.
public protocol StickyBucketStore: Sendable {
    /// Return the per-experiment assignments for `unit`, or `nil` if none.
    func get(_ unit: String) -> [String: StickyEntry]?
    /// Persist `entry` for `(unit, exp)`, overwriting any prior assignment.
    func set(_ unit: String, _ exp: String, _ entry: StickyEntry)
}

/// A process-local sticky store backed by a lock-guarded dictionary. Handy for
/// tests and single-process servers. Thread-safe so it can be shared across the
/// `Engine` actor and caller code.
public final class InMemoryStickyBucketStore: StickyBucketStore, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: [String: StickyEntry]]

    /// Build an in-memory store, optionally seeded with existing assignments.
    public init(seed: [String: [String: StickyEntry]] = [:]) {
        self.store = seed
    }

    public func get(_ unit: String) -> [String: StickyEntry]? {
        lock.lock(); defer { lock.unlock() }
        return store[unit]
    }

    public func set(_ unit: String, _ exp: String, _ entry: StickyEntry) {
        lock.lock(); defer { lock.unlock() }
        var cur = store[unit] ?? [:]
        cur[exp] = entry
        store[unit] = cur
    }
}
