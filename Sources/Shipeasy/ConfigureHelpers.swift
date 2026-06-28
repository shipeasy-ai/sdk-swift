import Foundation

// Doc-23 configure() family + package-level helpers. The documented surface is
// exactly `configure(...)` (+ these test/offline siblings) and the bound
// `Client(user)`; the heavyweight `Engine` stays public but undocumented. These
// helpers let users avoid naming the Engine in tests, overrides, change
// listeners, and SSR tags. `Engine` is an `actor`, so the helpers are `async`.

@inline(__always)
private func requireGlobalEngine(_ fn: String) -> Engine {
    guard let engine = globalEngine() else {
        fatalError("Shipeasy.\(fn)(...) called before configure(apiKey:) (or a configureFor* sibling)")
    }
    return engine
}

private func applyOverrides(
    _ engine: Engine,
    _ flags: [String: Bool],
    _ configs: [String: Any?],
    _ experiments: [String: (group: String, params: Any?)]
) async {
    for (name, value) in flags { await engine.overrideFlag(name, value) }
    for (name, value) in configs { await engine.overrideConfig(name, value) }
    for (name, spec) in experiments {
        await engine.overrideExperiment(name, group: spec.group, params: spec.params)
    }
}

/// Configure Shipeasy in **test mode** — a drop-in sibling of `configure(...)`
/// with no network, ever (no api key needed). Seed the values your code under
/// test should see, then read them through the ordinary `Client(user)`. REPLACES
/// any previously-configured engine, so tests can reconfigure freely.
///
///     await configureForTesting(flags: ["new_checkout": true])
///     let client = try Client(["user_id": "u_1"])
///     await client.getFlag("new_checkout", default: false) // true
///
/// - Parameters:
///   - attributes: same transform as `configure` (default identity).
///   - flags: `name -> Bool` forced `getFlag` results.
///   - configs: `name -> value` forced `getConfig` results.
///   - experiments: `name -> (group, params)` forced enrolments.
@discardableResult
public func configureForTesting(
    attributes: AttributesFn? = nil,
    flags: [String: Bool] = [:],
    configs: [String: Any?] = [:],
    experiments: [String: (group: String, params: Any?)] = [:]
) async -> Engine {
    let engine = Engine.forTesting()
    await applyOverrides(engine, flags, configs, experiments)
    GlobalConfig.shared.install(engine, attributes)
    return engine
}

/// Configure Shipeasy **offline** — evaluate the REAL rules from an in-memory
/// snapshot or a JSON file, with no network. A drop-in sibling of `configure(...)`
/// (no api key needed). Optional `flags`/`configs`/`experiments` overrides layer
/// on top. Provide exactly one source: `snapshot` (`["flags": ..., "experiments":
/// ...]`) or `path` (a JSON file). REPLACES any previously-configured engine.
@discardableResult
public func configureForOffline(
    snapshot: [String: Any]? = nil,
    path: String? = nil,
    attributes: AttributesFn? = nil,
    flags: [String: Bool] = [:],
    configs: [String: Any?] = [:],
    experiments: [String: (group: String, params: Any?)] = [:]
) async throws -> Engine {
    let engine: Engine
    if let path {
        engine = try Engine.fromFile(path)
    } else if let snapshot {
        engine = Engine.fromSnapshot(
            flags: snapshot["flags"] as? [String: Any] ?? [:],
            experiments: snapshot["experiments"] as? [String: Any] ?? [:]
        )
    } else {
        throw OfflineSourceError()
    }
    await applyOverrides(engine, flags, configs, experiments)
    GlobalConfig.shared.install(engine, attributes)
    return engine
}

/// Thrown by ``configureForOffline(snapshot:path:...)`` when neither a `snapshot`
/// nor a `path` source is provided.
public struct OfflineSourceError: Error, CustomStringConvertible {
    public let description = "configureForOffline requires either a snapshot: or a path: source"
}

/// Force `getFlag(name)` -> `value` on the spot, for the current configuration —
/// a quick in-test override layered on top of whatever `configureForTesting` /
/// `configureForOffline` (or `configure`) set up. Wins over the blob until
/// `clearOverrides()`.
public func overrideFlag(_ name: String, _ value: Bool) async {
    await requireGlobalEngine("overrideFlag").overrideFlag(name, value)
}

/// Force `getConfig(name)` -> `value` on the spot (see `overrideFlag`).
public func overrideConfig(_ name: String, _ value: Any?) async {
    await requireGlobalEngine("overrideConfig").overrideConfig(name, value)
}

/// Force `getExperiment(name)` to report enrolment in `group` with `params` on
/// the spot (see `overrideFlag`).
public func overrideExperiment(_ name: String, group: String, params: Any?) async {
    await requireGlobalEngine("overrideExperiment").overrideExperiment(name, group: group, params: params)
}

/// Drop every on-the-spot flag/config/experiment override — INCLUDING the seed
/// from `configureForTesting` (test mode has no blob beneath, so everything
/// reverts to empty-blob defaults). Under `configureForOffline` the snapshot
/// remains and evaluations revert to it.
public func clearOverrides() async {
    await requireGlobalEngine("clearOverrides").clearOverrides()
}

/// Register a listener fired after a background poll fetches NEW data (a 200, not
/// a 304). Returns an unsubscribe closure. Requires `configure(..., poll: true)`
/// (no poll runs otherwise). Configuration owns the engine; you never touch it.
@discardableResult
public func onChange(_ listener: @escaping @Sendable () -> Void) async -> @Sendable () -> Void {
    await requireGlobalEngine("onChange").onChange(listener)
}

/// Return the cross-platform SSR bootstrap `<script>` tag for a request (no key
/// embedded), via the configured global engine — call `configure(...)` first.
public func bootstrapScriptTag(
    _ user: [String: Any],
    anonId: String? = nil,
    i18nProfile: String = "en:prod",
    baseURL: String? = nil
) async -> String {
    await requireGlobalEngine("bootstrapScriptTag")
        .bootstrapScriptTag(user, anonId: anonId, i18nProfile: i18nProfile, baseURL: baseURL)
}

/// Return the i18n loader `<script>` tag (public client key) for SSR, via the
/// configured global engine — call `configure(...)` first.
public func i18nScriptTag(
    _ clientKey: String,
    profile: String = "en:prod",
    baseURL: String? = nil
) async -> String {
    await requireGlobalEngine("i18nScriptTag").i18nScriptTag(clientKey, profile: profile, baseURL: baseURL)
}
