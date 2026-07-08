import Foundation

/// The result of an experiment assignment for the bound device user. Returned by
/// ``ShipeasyClient/getExperiment(_:defaultParams:)`` — the edge evaluates the
/// experiment server-side over `POST /sdk/evaluate` and the client caches this
/// projection.
public struct ExperimentResult: Sendable {
    public let inExperiment: Bool
    public let group: String
    public let params: Any?
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
