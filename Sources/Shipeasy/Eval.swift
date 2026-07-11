import Foundation

/// A universe assignment for the bound device user. Returned by
/// ``ShipeasyClient/universe(_:)``'s `assign()` — a universe is a mutual-exclusion
/// pool, so the unit lands in **at most one** experiment there. The edge evaluates
/// server-side over `POST /sdk/evaluate` and the client caches the projection.
///
/// The handle never throws: an un-enrolled unit still resolves ``get(_:_:)`` to the
/// universe defaults (or your fallback).
public struct Assignment: Sendable {
    /// The experiment the unit landed in, or `nil` when not enrolled.
    public let name: String?
    /// The assigned variant/group name, or `nil` when not enrolled.
    public let group: String?
    /// The resolved params for this assignment. When enrolled these are already
    /// merged by the edge (universe defaults ⊕ variant); when not enrolled they
    /// are the universe defaults.
    let params: [String: Any]

    /// True iff the unit is enrolled in an experiment in this universe.
    public var enrolled: Bool { group != nil }

    init(name: String?, group: String?, params: [String: Any]) {
        self.name = name
        self.group = group
        self.params = params
    }

    /// Read a resolved param, cast to `T`: variant override ?? universe default ??
    /// `fallback`. Returns `fallback` when the field is absent or the value isn't a
    /// `T`. Works even when not enrolled (you get the universe default ?? fallback).
    public func get<T>(_ field: String, _ fallback: T? = nil) -> T? {
        guard let v = params[field], !(v is NSNull) else { return fallback }
        return (v as? T) ?? fallback
    }

    /// Read a resolved param untyped: variant override ?? universe default ?? `nil`.
    public func get(_ field: String) -> Any? {
        guard let v = params[field], !(v is NSNull) else { return nil }
        return v
    }
}

/// One experiment entry from the cached `/sdk/evaluate` response, retaining the
/// owning `universe` so ``ShipeasyClient/universe(_:)`` can scan the pool.
struct CachedExperiment: Sendable {
    let inExperiment: Bool
    let group: String
    let params: [String: Any]?
    let universe: String?
}

/// A programmatic experiment override: force `universe(...).assign()` to enrol the
/// unit in `group`, with `params` layered over the universe defaults. Set via
/// ``ShipeasyClient/overrideExperiment(_:group:params:)`` and cleared by
/// ``ShipeasyClient/clearOverrides()``. Actor-isolated state, so it needn't be
/// `Sendable`.
struct ExperimentOverride {
    let group: String
    let params: [String: Any]
}

// The client evaluates nothing locally (the edge owns evaluation over
// `/sdk/evaluate`); it only needs to coerce the loosely-typed values the edge
// returns for flags and kill switches into a `Bool`.
enum Eval {
    /// Coerce an edge-returned value (`Bool`, or `1`/`1.0`) into a Bool.
    static func enabled(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i == 1 }
        if let d = v as? Double { return d == 1 }
        return false
    }
}
