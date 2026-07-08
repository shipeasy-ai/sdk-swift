import Foundation

// URLSession/URLRequest live in FoundationNetworking on non-Apple platforms (Linux).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Global configure + user-bound Client
//
// Two-part ergonomic front door, mirroring `@shipeasy/sdk` and the other server
// SDKs (see `.agents/sdk-bound-client-spec.md`):
//
//   1. `configure(apiKey:attributes:)` — once, process-wide. Builds the single
//      package-global `Engine` (the heavyweight type that owns the API key, HTTP,
//      the blob cache and the poll timer), stores an optional `attributes`
//      transform, and fire-and-forgets the engine's one-shot fetch so a bound
//      `Client` resolves against real rules without an explicit init call.
//
//   2. `Client(_ user:)` — a cheap, user-bound handle. The configured
//      `attributes` transform runs ONCE in the constructor and the resulting
//      attribute map is bound, so every method takes NO user argument. It owns no
//      connection/cache/timer — it delegates evaluation to the global engine.
//
//      let on = try await Client(["user_id": "u_123"]).getFlag("new_checkout")
//
// Because `Engine` is an `actor`, the bound `Client`'s methods are `async`
// (they forward to the actor). Construction itself is synchronous and `throws`
// when `configure(...)` has not been called, so the failure is loud and local.

/// Transform from *your* user object (any shape) to the Shipeasy attribute map
/// (`["user_id": ..., "anonymous_id": ..., <targeting attrs>]`) that every bound
/// `Client` evaluation uses. The default is identity — the user value is assumed
/// to already BE the attribute map.
public typealias AttributesFn = (Any) -> [String: Any]

/// Default transform: the user object IS already the attribute map.
private func identityAttributes(_ user: Any) -> [String: Any] {
    user as? [String: Any] ?? [:]
}

/// Process-wide holder for the global `Engine` + `attributes` transform built by
/// `configure(...)`. First-config-wins, matching the default-engine idempotency
/// the `see()` wiring uses. Thread-safe.
final class GlobalConfig: @unchecked Sendable {
    static let shared = GlobalConfig()
    private let lock = NSLock()
    private var engine: Engine?
    private var attributes: AttributesFn = identityAttributes

    /// First call wins: build + store the engine and transform, returning the
    /// new engine and `true`. Later calls return the existing engine and `false`.
    func configureOnce(_ build: () -> Engine, _ transform: AttributesFn?) -> (Engine, Bool) {
        lock.lock(); defer { lock.unlock() }
        if let engine { return (engine, false) }
        let e = build()
        engine = e
        attributes = transform ?? identityAttributes
        return (e, true)
    }

    func currentEngine() -> Engine? {
        lock.lock(); defer { lock.unlock() }
        return engine
    }

    func currentAttributes() -> AttributesFn {
        lock.lock(); defer { lock.unlock() }
        return attributes
    }

    /// Drop the global engine + transform. Tests only.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        engine = nil
        attributes = identityAttributes
    }

    /// REPLACE the global engine + transform unconditionally (unlike
    /// `configureOnce`'s first-config-wins). Used by the `configureFor*` siblings
    /// so a test suite can reconfigure between cases.
    func install(_ engine: Engine, _ transform: AttributesFn?) {
        lock.lock(); defer { lock.unlock() }
        self.engine = engine
        attributes = transform ?? identityAttributes
    }
}

/// Configure the package-global engine and the `attributes` transform.
///
/// First-config-wins: the first call builds the engine and stores it (plus the
/// transform); later calls are a no-op and return the already-built engine — the
/// same idempotency the default-engine `see()` wiring uses. Constructing the
/// engine also registers it as the default client backing the package-level
/// `see()` functions.
///
/// `attributes` is a function from *your* user object to the Shipeasy attribute
/// map (`["user_id": ..., "anonymous_id": ..., <targeting attrs>]`) that every
/// bound ``Client`` evaluation uses. Default = identity (the user object is
/// assumed to already be the attribute map).
///
/// Unless `init` is `false`, the engine's one-shot fetch (`initializeOnce()`) is
/// kicked off fire-and-forget so `Client(user).getFlag(...)` resolves against
/// real rules without an explicit init call. Long-running servers wanting the
/// background poll can call `initialize()` on the returned engine instead (pass
/// `init: false` here to avoid the redundant one-shot fetch).
///
/// `logLevel` (default `.warn`) sets the process-global verbosity of the SDK's
/// own diagnostic logging — `.silent` mutes it entirely. Runtime reads never
/// throw or trap regardless of level; logging is a best-effort stderr side
/// channel that can never surface into caller code.
///
/// All other parameters are forwarded straight to the `Engine` initializer.
@discardableResult
public func configure(
    apiKey: String,
    attributes: AttributesFn? = nil,
    baseURL: URL = URL(string: "https://edge.shipeasy.dev")!,
    session: URLSession = .shared,
    env: String = "prod",
    disableTelemetry: Bool = false,
    telemetryURL: String = "https://t.shipeasy.ai",
    privateAttributes: [String] = [],
    stickyStore: StickyBucketStore? = nil,
    logLevel: LogLevel = .warn,
    `init`: Bool = true,
    poll: Bool = false
) -> Engine {
    let (engine, fresh) = GlobalConfig.shared.configureOnce({
        Engine(
            apiKey: apiKey,
            baseURL: baseURL,
            session: session,
            env: env,
            disableTelemetry: disableTelemetry,
            telemetryURL: telemetryURL,
            privateAttributes: privateAttributes,
            stickyStore: stickyStore,
            logLevel: logLevel
        )
    }, attributes)
    if fresh {
        if poll {
            // Long-running server: initial fetch + periodic background refresh.
            // The poll lifecycle lives inside the engine — the docs never tell a
            // user to call initialize() themselves.
            Task { try? await engine.initialize() }
        } else if `init` {
            // Fire-and-forget one-shot fetch — never block configure().
            Task { try? await engine.initializeOnce() }
        }
    }
    return engine
}

/// Return the engine built by `configure(...)` (or `nil` if not yet configured).
public func globalEngine() -> Engine? {
    GlobalConfig.shared.currentEngine()
}

/// Drop the package-global engine + transform. Tests only.
public func resetGlobalConfig() {
    GlobalConfig.shared.reset()
}

/// Raised when a ``Client`` is constructed before ``configure(apiKey:)``.
public struct NotConfiguredError: Error, CustomStringConvertible {
    public let description = "Shipeasy.Client(user) constructed before configure(apiKey:) was called"
}

/// A cheap, user-bound handle over the global engine built by ``configure(...)``.
///
/// Construct one per user/request: `try Client(user)`. The configured
/// `attributes` transform runs once here and the resulting attribute map is
/// bound, so every method takes NO user argument — the user is bound. It owns no
/// HTTP connection, cache, or poll timer: it delegates every evaluation to the
/// single configured engine.
///
/// `Engine` is an `actor`, so the read methods are `async`. Construction is
/// synchronous and `throws` ``NotConfiguredError`` when `configure(...)` has not
/// been called, so the failure is loud and local:
///
///     let client = try Client(["user_id": "u_123"])
///     let on = await client.getFlag("new_checkout")
public struct Client: @unchecked Sendable {
    private let engine: Engine
    /// The bound attribute map: the result of the configured `attributes`
    /// transform applied to the user object once at construction.
    public let attributes: [String: Any]

    /// Build a user-bound client. Runs the configured `attributes` transform on
    /// `user` and binds the result. Throws ``NotConfiguredError`` if
    /// `configure(apiKey:)` has not been called.
    public init(_ user: Any) throws {
        guard let engine = GlobalConfig.shared.currentEngine() else {
            throw NotConfiguredError()
        }
        self.engine = engine
        self.attributes = GlobalConfig.shared.currentAttributes()(user)
    }

    /// Evaluate the bound user against gate `name`. Returns `false` when the
    /// engine isn't ready or the gate is absent.
    public func getFlag(_ name: String) async -> Bool {
        await engine.getFlag(name, user: attributes)
    }

    /// Evaluate the bound user against gate `name`, returning `default` only when
    /// the flag cannot be evaluated (engine not ready / flag not found), never
    /// when it simply evaluates to `false`.
    public func getFlag(_ name: String, default defaultValue: Bool) async -> Bool {
        await engine.getFlag(name, user: attributes, default: defaultValue)
    }

    /// Evaluate the bound user against gate `name` and explain why it resolved.
    public func getFlagDetail(_ name: String) async -> FlagDetail {
        await engine.getFlagDetail(name, user: attributes)
    }

    /// Read a dynamic config (configs are not user-scoped; forwarded straight to
    /// the engine).
    public func getConfig(_ name: String) async -> Any? {
        await engine.getConfig(name)
    }

    /// Read a dynamic config, returning `default` when the key is absent.
    public func getConfig(_ name: String, default defaultValue: Any?) async -> Any? {
        await engine.getConfig(name, default: defaultValue)
    }

    /// Evaluate the bound user against experiment `name`.
    public func getExperiment(_ name: String, defaultParams: Any?) async -> ExperimentResult {
        await engine.getExperiment(name, user: attributes, defaultParams: defaultParams)
    }

    /// Report whether kill switch `name` (optionally a named per-key override) is
    /// engaged. Kill switches are not user-scoped; forwarded to the engine.
    public func getKillswitch(_ name: String, switchKey: String? = nil) async -> Bool {
        await engine.getKillswitch(name, switchKey: switchKey)
    }

    /// The bucketing/identity unit for the bound user: `user_id` else
    /// `anonymous_id` from the bound attribute map, or `nil` when neither is set.
    private var unitId: String? {
        if let v = attributes["user_id"] { return "\(v)" }
        if let v = attributes["anonymous_id"] { return "\(v)" }
        return nil
    }

    /// Record a conversion event for the bound user. Derives the unit id from the
    /// bound attribute map (`user_id` else `anonymous_id`) and forwards to the
    /// engine's `track`. A no-op when the bound user has neither id. This is the
    /// Client-only path to record a conversion — the advanced
    /// `Engine.track(userId:eventName:properties:)` form remains for callers that
    /// need an explicit unit.
    public func track(_ event: String, properties: [String: Any] = [:]) async {
        guard let id = unitId else { return }
        await engine.track(userId: id, eventName: event, properties: properties.isEmpty ? nil : properties)
    }

    /// Emit an exposure event for `experiment` at the server-side decision point,
    /// for the bound user. Derives the unit id from the bound attribute map and
    /// forwards to the engine's `logExposure`; a no-op when the bound user has no
    /// id or is not enrolled. The advanced `Engine.logExposure(userId:experiment:)`
    /// form remains for callers that need an explicit unit.
    public func logExposure(_ experiment: String) async {
        guard let id = unitId else { return }
        await engine.logExposure(userId: id, experiment: experiment)
    }
}
