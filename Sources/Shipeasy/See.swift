import Foundation

// MARK: - see() structured error reporting
//
// Mirrors `@shipeasy/sdk` (`packages/ts-sdk/src/see/core.ts`) and the Python
// reference (`sdk-python/shipeasy/_see.py`). Every handled exception documents
// its product *consequence*, not just its stack:
//
//     do {
//         try chargeCard(order)
//     } catch {
//         client.see(error).causesThe("checkout").to("use the backup processor")
//     }
//
// Dispatch model (differs from the TS microtask): `to(_:)` is the terminal — it
// builds the wire event and fire-and-forgets the POST to `/collect`.
// `causesThe(_:)` and `extras(_:)` are chainable setters that may be called in
// any order *before* `to(_:)`. `Engine` is an `actor`, so the chain is a plain
// (non-isolated) `final class` that captures the engine and accumulates state
// synchronously; `to(_:)` hops onto the actor via a detached `Task` to dispatch.

// MARK: Limits (mirror core.ts; kept in sync with the worker's /collect)

let SEE_MAX_MESSAGE = 500
let SEE_MAX_STACK = 8000
let SEE_MAX_SUBJECT = 200
let SEE_MAX_EXTRA_VALUE = 200
let SEE_MAX_EXTRA_KEYS = 20
let SEE_DEDUP_WINDOW_MS: Double = 30_000
let SEE_MAX_PER_PROCESS = 25

/// SDK version, single source for the `sdk_version` wire field. Bumped in lockstep
/// with the `VERSION` file (SwiftPM publishes by git tag, so no compile-time read
/// of `VERSION` exists — this constant IS the source the event reports).
public let SDK_VERSION = "0.8.0"

private let SEE_DEFAULT_SUBJECT = "app"
private let SEE_DEFAULT_OUTCOME = "hit an error"

func seeTruncate(_ s: String, _ limit: Int) -> String {
    s.count <= limit ? s : String(s.prefix(limit))
}

/// Drop nil values, keep only String / finite-number / Bool, truncate string
/// values to 200 chars, cap at 20 keys (insertion order). Returns nil if nothing
/// was kept so the field can be omitted.
func sanitizeExtras(_ extras: [String: Any]?) -> [String: Any]? {
    guard let extras, !extras.isEmpty else { return nil }
    var out: [String: Any] = [:]
    var n = 0
    // Preserve a stable order so the key cap is deterministic.
    for key in extras.keys.sorted() {
        if n >= SEE_MAX_EXTRA_KEYS { break }
        let v = extras[key]
        // Drop nil / NSNull.
        guard let v, !(v is NSNull) else { continue }
        if let b = v as? Bool {
            out[key] = b
        } else if let s = v as? String {
            out[key] = seeTruncate(s, SEE_MAX_EXTRA_VALUE)
        } else if let d = v as? Double {
            if d.isFinite { out[key] = d } else { continue }
        } else if let i = v as? Int {
            out[key] = i
        } else if let n2 = v as? NSNumber {
            // NSNumber covers bridged Int/Double/Bool from `[String: Any]`.
            if CFGetTypeID(n2) == CFBooleanGetTypeID() {
                out[key] = n2.boolValue
            } else {
                let dd = n2.doubleValue
                if dd.isFinite { out[key] = n2 } else { continue }
            }
        } else {
            continue
        }
        n += 1
    }
    return out.isEmpty ? nil : out
}

/// A non-exception problem. The name is a stable fingerprint key — put variable
/// data in `.extras()`, never in the name.
public struct Violation: Sendable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

// MARK: Wire event construction

/// The "problem" handed to `see()` — an `Error`, a `Violation`, or an arbitrary
/// string/value. Modelled as an enum so the chain is `Sendable`.
enum SeeProblem: @unchecked Sendable {
    case error(Error)
    case violation(Violation)
    case message(String)
}

/// Build the `type:"error"` event accepted by POST /collect.
func buildSeeEvent(
    _ problem: SeeProblem,
    subject: String,
    outcome: String,
    extras: [String: Any]?,
    side: String,
    sdkVersion: String,
    env: String?
) -> [String: Any] {
    let errorType: String
    let message: String
    let kind: String
    var stack: String? = nil

    switch problem {
    case .violation(let v):
        errorType = v.name
        message = v.name
        kind = "violation"
    case .error(let e):
        errorType = String(describing: type(of: e))
        // Prefer a custom localized message; otherwise the default printout
        // (`"\(e)"` — for an enum this is e.g. `MyError.boom`, which is fine).
        // (`Error` always bridges to NSError, whose `localizedDescription` for a
        // plain Swift enum is the unhelpful "operation couldn't be completed"
        // form, so we don't fall back to it.)
        if let le = e as? LocalizedError, let d = le.errorDescription, !d.isEmpty {
            message = d
        } else if let c = (e as Any) as? CustomStringConvertible {
            message = c.description
        } else {
            message = "\(e)"
        }
        kind = "caught"
        // Swift has no per-throw stack by default. Capture the *current* call
        // stack at report time (best-effort, truncated). It points at the
        // see() call site, not the original throw, but is better than nothing.
        let frames = Thread.callStackSymbols
        if !frames.isEmpty { stack = frames.joined(separator: "\n") }
    case .message(let m):
        errorType = "Error"
        message = m
        kind = "caught"
    }

    var ev: [String: Any] = [
        "type": "error",
        "kind": kind,
        "error_type": seeTruncate(errorType.isEmpty ? "Error" : errorType, SEE_MAX_SUBJECT),
        "message": seeTruncate(message.isEmpty ? errorType : message, SEE_MAX_MESSAGE),
        "subject": seeTruncate(subject, SEE_MAX_SUBJECT),
        "outcome": seeTruncate(outcome, SEE_MAX_SUBJECT),
        "side": side,
        "sdk_version": sdkVersion,
        "ts": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let stack { ev["stack"] = seeTruncate(stack, SEE_MAX_STACK) }
    if let clean = sanitizeExtras(extras) { ev["extras"] = clean }
    if let env, !env.isEmpty { ev["env"] = env }
    return ev
}

// MARK: Spam limiter (mirror SeeLimiter)

private func seeTopStackLine(_ stack: String?) -> String {
    guard let stack else { return "" }
    for raw in stack.split(separator: "\n") {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if !s.isEmpty { return String(s.prefix(200)) }
    }
    return ""
}

/// Per-process spam guard: identical events within 30s collapse to one send; a
/// hard cap bounds total sends per process. Thread-safe.
final class SeeLimiter: @unchecked Sendable {
    private let maxPerProcess: Int
    private let window: Double
    private let lock = NSLock()
    private var last: [String: Double] = [:]
    private var sent = 0

    init(maxPerProcess: Int = SEE_MAX_PER_PROCESS, dedupWindowMs: Double = SEE_DEDUP_WINDOW_MS) {
        self.maxPerProcess = maxPerProcess
        self.window = dedupWindowMs
    }

    func shouldSend(_ ev: [String: Any]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if sent >= maxPerProcess { return false }
        let key = [
            "\(ev["kind"] ?? "")",
            "\(ev["error_type"] ?? "")",
            String("\(ev["message"] ?? "")".prefix(200)),
            seeTopStackLine(ev["stack"] as? String),
        ].joined(separator: "|")
        let now = Date().timeIntervalSince1970 * 1000
        if let prev = last[key], now - prev < window { return false }
        last[key] = now
        sent += 1
        return true
    }
}

// MARK: Built carrier (handed to the actor dispatcher)

/// A finalized chain, ready for the actor to build + send. `@unchecked Sendable`
/// because `extras` is `[String: Any]`; the values we keep are value types.
struct SeeBuilt: @unchecked Sendable {
    let problem: SeeProblem
    let subject: String
    let outcome: String
    let extras: [String: Any]?
}

// MARK: Fluent chains

/// Accumulates consequence + extras; `to(_:)` dispatches once. Synchronous so
/// usage reads `client.see(e).causesThe("checkout").to("use cached prices")`.
public final class SeeChain {
    private let problem: SeeProblem
    private weak var client: Engine?
    private var subject: String?
    private var outcome: String?
    private var extras: [String: Any]?
    private var done = false

    init(problem: SeeProblem, client: Engine?) {
        self.problem = problem
        self.client = client
    }

    @discardableResult
    public func causesThe(_ subject: String) -> SeeChain {
        self.subject = subject
        return self
    }

    /// Merge extras (later wins). May be called before `to(_:)`.
    @discardableResult
    public func extras(_ dict: [String: Any]) -> SeeChain {
        if !dict.isEmpty {
            var merged = self.extras ?? [:]
            for (k, v) in dict { merged[k] = v }
            self.extras = merged
        }
        return self
    }

    /// Terminal: build the event and fire-and-forget the report. Idempotent —
    /// calling twice is a no-op. Never throws into caller code.
    public func to(_ outcome: String) {
        if done { return }
        done = true
        self.outcome = outcome
        guard let client else { return }
        let built = SeeBuilt(
            problem: problem,
            subject: subject ?? SEE_DEFAULT_SUBJECT,
            outcome: outcome.isEmpty ? SEE_DEFAULT_OUTCOME : outcome,
            extras: extras
        )
        Task { await client._dispatchSee(built) }
    }
}

/// `controlFlowException(e).because("because ...")` — marks the exception
/// expected and reports NOTHING. Swift errors are values, so there is no global
/// identity set to stamp; the marker is best-effort and `extras` is stored for
/// local debugging only (an expected exception is never transmitted).
public final class ControlFlowChain {
    private let err: Error
    init(_ err: Error) { self.err = err }

    @discardableResult
    public func because(_ reason: String) -> ControlFlowTail {
        ControlFlowTail(err, reason)
    }
}

public final class ControlFlowTail {
    let err: Error
    public let reason: String
    public private(set) var localExtras: [String: Any]?

    init(_ err: Error, _ reason: String) {
        self.err = err
        self.reason = reason
    }

    /// Stored for local debugging only — never sent. Returns self for chaining.
    @discardableResult
    public func extras(_ dict: [String: Any]) -> ControlFlowTail {
        localExtras = sanitizeExtras(dict)
        return self
    }
}

// MARK: Global default client + package-level functions

/// Thread-safe holder for the default `Engine` backing the package-level
/// `see(...)` functions. Last-constructed engine wins (registered in `Engine.init`,
/// or via `configure(...)`).
final class DefaultClientBox: @unchecked Sendable {
    static let shared = DefaultClientBox()
    private let lock = NSLock()
    private weak var client: Engine?

    func set(_ c: Engine?) {
        lock.lock(); defer { lock.unlock() }
        client = c
    }

    func get() -> Engine? {
        lock.lock(); defer { lock.unlock() }
        return client
    }
}

/// Register the engine backing the package-level `see()` functions. Called
/// automatically when an `Engine` is constructed (last wins).
public func setDefaultClient(_ client: Engine?) {
    DefaultClientBox.shared.set(client)
}

/// Report a caught error via the default client. Use `client.see(_:)` to target
/// a specific client.
public func see(_ problem: Error) -> SeeChain {
    guard let c = DefaultClientBox.shared.get() else {
        FileHandle.standardError.write(Data("[shipeasy] see() called before a client was created — error dropped\n".utf8))
        return SeeChain(problem: .error(problem), client: nil)
    }
    return c.see(problem)
}

/// Report a non-exception problem via the default client.
public func seeViolation(_ name: String) -> SeeChain {
    guard let c = DefaultClientBox.shared.get() else {
        FileHandle.standardError.write(Data("[shipeasy] seeViolation() called before a client was created — error dropped\n".utf8))
        return SeeChain(problem: .violation(Violation(name)), client: nil)
    }
    return c.seeViolation(name)
}

/// Mark an exception as expected control flow (reports nothing). Works without a
/// client — it only carries metadata for local debugging.
public func controlFlowException(_ err: Error) -> ControlFlowChain {
    ControlFlowChain(err)
}

// MARK: Engine integration

public extension Engine {
    /// Report a caught error. Fire-and-forget; never blocks or throws into the
    /// caller. `nonisolated` so the chain reads synchronously — terminate with
    /// `.to(outcome)`:
    ///
    ///     client.see(error).causesThe("checkout").to("use cached prices")
    nonisolated func see(_ problem: Error) -> SeeChain {
        SeeChain(problem: .error(problem), client: self)
    }

    /// Report a non-exception problem. The name is a stable fingerprint key —
    /// put variable data in `.extras()`, never the name.
    nonisolated func seeViolation(_ name: String) -> SeeChain {
        SeeChain(problem: .violation(Violation(name)), client: self)
    }

    /// Mark an exception as expected control flow — reports nothing.
    nonisolated func controlFlowException(_ err: Error) -> ControlFlowChain {
        ControlFlowChain(err)
    }
}
