import Foundation

// URLSession/URLRequest live in FoundationNetworking on non-Apple platforms (Linux).
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Native mobile client (iOS / macOS / tvOS / watchOS)
//
// The `configure(apiKey:)` / `Client(user)` front door above is the SERVER SDK:
// it holds a **server** key, pulls the raw rules blobs (`GET /sdk/flags` +
// `/sdk/experiments`) and evaluates them locally. That model is wrong for a
// shipped app — a server key must never be embedded in an app binary, and the
// edge forbids client keys from the blob routes (they are `requireKey("server")`).
//
// `ShipeasyClient` is the CLIENT SDK for that case. It holds a **public client
// key** (safe to ship), evaluates a single device user server-side over
// `POST /sdk/evaluate`, and caches the returned assignments. Reads are cheap
// local lookups against that cache. Crucially it persists the device's
// `anonymous_id` (via `AnonymousStore`, `UserDefaults` by default) so a
// logged-out visitor buckets **identically across app launches** — without
// persistence a fresh UUID every launch silently re-buckets every fractional
// rollout and experiment.
//
//     configureClient(clientKey: "pk_live_…")          // once, at app launch
//     await shipeasyClient()?.identify(["user_id": "u_123"])
//     let on = await shipeasyClient()?.getFlag("new_checkout") ?? false

/// Persistent, platform-scoped storage for the device's stable anonymous
/// bucketing id (the cross-SDK `__se_anon_id`). The id must survive app
/// launches, or a logged-out user re-buckets every fractional rollout on every
/// cold start. `get`/`set` are synchronous and best-effort — a throwing or slow
/// backing store must degrade gracefully, never crash a read.
///
/// The default `UserDefaultsAnonymousStore` covers most apps. Supply your own to
/// back the id with the Keychain (survives reinstalls), an app-group container
/// (shared with extensions), or an in-memory map (tests):
///
/// ```swift
/// struct KeychainAnonStore: AnonymousStore {
///     func get(_ key: String) -> String? { Keychain.read(key) }
///     func set(_ key: String, _ value: String) { Keychain.write(key, value) }
/// }
/// configureClient(clientKey: "pk_live_…", store: KeychainAnonStore())
/// ```
public protocol AnonymousStore: Sendable {
    /// The stored value for `key`, or `nil` when absent/unreadable.
    func get(_ key: String) -> String?
    /// Persist `value` under `key`. Best-effort — failures must be swallowed.
    func set(_ key: String, _ value: String)
}

/// Default `AnonymousStore` backed by `UserDefaults` (available on every Apple
/// platform, and via swift-corelibs-foundation on Linux). Persists across app
/// launches; cleared on app uninstall. Use a Keychain-backed store if you need
/// the id to survive reinstalls.
public struct UserDefaultsAnonymousStore: AnonymousStore {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func get(_ key: String) -> String? { defaults.string(forKey: key) }
    public func set(_ key: String, _ value: String) { defaults.set(value, forKey: key) }
}

/// The native mobile client handle. Holds a public client key, one device user,
/// and the cached assignments from the last `POST /sdk/evaluate`. Construct once
/// per app (usually via ``configureClient(clientKey:baseURL:env:session:store:disableTelemetry:privateAttributes:transport:)``
/// and read back with ``shipeasyClient()``). Reads are `async` because the type
/// is an `actor`, but they never touch the network — they serve the cache.
public actor ShipeasyClient {
    /// The HTTP seam. Defaults to `URLSession.seData`; tests inject a stub. Kept
    /// separate from `URLSession` so a hermetic test needs no `URLProtocol`.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let clientKey: String
    private let baseURL: URL
    private let env: String
    private let store: AnonymousStore
    private let transport: Transport
    private let telemetry: Telemetry
    private let privateAttributes: [String]

    /// The stable, persisted anonymous bucketing id — resolved once at init from
    /// the store (or freshly minted + written back on first launch).
    public let anonymousId: String

    private var userId: String?
    private var userAttributes: [String: Any] = [:]

    private var flags: [String: Bool] = [:]
    private var configs: [String: Any] = [:]
    private var experiments: [String: ExperimentResult] = [:]
    private var killswitches: [String: Any] = [:]
    /// Opaque sticky-bucketing state echoed back to the edge on each evaluate so
    /// enrolled units stay pinned to their variant across allocation changes.
    private var sticky: [String: Any] = [:]
    private var ready = false

    // Per-process spam guard for see() error reports so a hot loop can't flood
    // /collect (dedup window + hard cap; see SeeLimiter).
    private let seeLimiter = SeeLimiter()
    // Test seam: when set, built see() events are handed here (after limiter +
    // sanitize) instead of being POSTed. Set via `setSeeSink(_:)`.
    private var seeSink: (@Sendable ([String: Any]) -> Void)?

    /// Storage key for the sticky state (kept next to the anon id in the store).
    private static let stickyStoreKey = "__se_sticky"

    public init(
        clientKey: String,
        baseURL: URL = URL(string: "https://api.shipeasy.ai")!,
        env: String = "prod",
        session: URLSession = .shared,
        store: AnonymousStore = UserDefaultsAnonymousStore(),
        disableTelemetry: Bool = false,
        telemetryURL: String = "https://t.shipeasy.ai",
        privateAttributes: [String] = [],
        transport: Transport? = nil
    ) {
        self.clientKey = clientKey
        self.baseURL = baseURL
        self.env = env
        self.store = store
        self.privateAttributes = privateAttributes
        self.transport = transport ?? { req in
            let (data, response) = try await session.seData(for: req)
            return (data, (response as? HTTPURLResponse) ?? HTTPURLResponse())
        }
        // Resolve the stable device anon id: adopt the persisted one if valid,
        // else mint a fresh UUID and write it back for the next launch. This is
        // the whole point of the client SDK — bucketing stability across launches.
        let key = AnonId.cookie
        if let existing = store.get(key), AnonId.isValid(existing) {
            self.anonymousId = existing
        } else {
            let minted = AnonId.mint()
            store.set(key, minted)
            self.anonymousId = minted
        }
        // Restore any persisted sticky state so a cold start keeps enrolled units
        // pinned.
        if let raw = store.get(ShipeasyClient.stickyStoreKey),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.sticky = decoded
        }
        // Per-evaluation usage telemetry, tagged `client` so usage is metered on
        // the client path. ON by default (disable with `disableTelemetry`).
        self.telemetry = Telemetry(
            endpoint: telemetryURL, sdkKey: clientKey, side: "client",
            env: env, disabled: disableTelemetry, session: session
        )
        // Wire the internal self-monitoring channel (SDK-own-bug reporting to
        // Shipeasy's own project), tagged `client`. Inert until the ingest key is
        // baked; gated on telemetry so hermetic test clients stay silent.
        InternalReport.shared.setContext(
            side: "client", sdkVersion: SDK_VERSION, enabled: !disableTelemetry
        )
        // Register as the default client backing the package-level see() funcs
        // (last constructed wins — the client-SDK analog of TS's shipeasy({key})).
        setDefaultClient(self)
    }

    // MARK: - Identity

    /// Bind the current device user and refresh assignments over the network.
    ///
    /// Pass the user's attribute map — `["user_id": "u_123", "plan": "pro"]`. The
    /// persisted `anonymous_id` is always attached, so a signed-in user is still
    /// tied to the same device identity. Call this at launch (with `[:]` for a
    /// logged-out visitor), on login, and whenever targeting attributes change.
    /// Awaiting it guarantees the first reads see the evaluated assignments.
    public func identify(_ user: [String: Any] = [:]) async {
        userAttributes = user
        if let uid = user["user_id"], !"\(uid)".isEmpty {
            userId = "\(uid)"
        }
        await refresh()
        // Best-effort identity beacon so the edge can stitch anon → user_id.
        if let userId {
            send(event: [
                "type": "identify",
                "user_id": userId,
                "anonymous_id": anonymousId,
                "ts": Int(Date().timeIntervalSince1970 * 1000),
            ])
        }
    }

    /// Clear the signed-in user (logout) while keeping the stable device
    /// `anonymous_id`, then re-evaluate as an anonymous visitor.
    public func reset() async {
        userId = nil
        userAttributes = [:]
        await refresh()
    }

    /// Force a re-evaluation for the currently-bound user without changing
    /// identity — e.g. to pick up a just-published flag change.
    public func refreshAssignments() async {
        await refresh()
    }

    // MARK: - Reads (served from the cached evaluate response)

    /// The bound gate value, or `default` when the client hasn't evaluated yet
    /// or the gate is absent.
    public func getFlag(_ name: String, default defaultValue: Bool = false) -> Bool {
        telemetry.emit("gate", name)
        guard ready else { return defaultValue }
        return flags[name] ?? defaultValue
    }

    /// The bound dynamic config value, or `default` when absent.
    public func getConfig(_ name: String, default defaultValue: Any? = nil) -> Any? {
        telemetry.emit("config", name)
        guard ready, let v = configs[name] else { return defaultValue }
        return v is NSNull ? nil : v
    }

    /// The experiment assignment for the bound user. `defaultParams` fills in
    /// `params` when the user is not enrolled or the server sent none.
    public func getExperiment(_ name: String, defaultParams: Any? = nil) -> ExperimentResult {
        telemetry.emit("experiment", name)
        guard ready, let r = experiments[name] else {
            return ExperimentResult(inExperiment: false, group: "control", params: defaultParams)
        }
        if r.params == nil {
            return ExperimentResult(inExperiment: r.inExperiment, group: r.group, params: defaultParams)
        }
        return r
    }

    /// Whether kill switch `name` (optionally a named per-key override) is
    /// engaged. `false` when the client isn't ready or the switch is absent.
    public func getKillswitch(_ name: String, switchKey: String? = nil) -> Bool {
        guard ready, let entry = killswitches[name] else { return false }
        if let switchKey, let map = entry as? [String: Any], let raw = map[switchKey] {
            return Eval.enabled(raw)
        }
        if let map = entry as? [String: Any] {
            return Eval.enabled(map["value"] ?? map["enabled"])
        }
        return Eval.enabled(entry)
    }

    // MARK: - Events

    /// Record a conversion event for the bound user. Private attributes are
    /// stripped from `properties` before egress. Fire-and-forget.
    public func track(_ event: String, properties: [String: Any] = [:]) {
        var ev: [String: Any] = [
            "type": "metric",
            "event_name": event,
            "user_id": userId as Any,
            "anonymous_id": anonymousId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if userId == nil { ev.removeValue(forKey: "user_id") }
        let safeProps = stripPrivate(properties)
        if !safeProps.isEmpty { ev["properties"] = safeProps }
        send(event: ev)
    }

    /// Emit an exposure for `experiment` at the decision point, for the bound
    /// user. No-op when the user is not enrolled. Fire-and-forget.
    public func logExposure(_ experiment: String) {
        guard let r = experiments[experiment], r.inExperiment else { return }
        var ev: [String: Any] = [
            "type": "exposure",
            "experiment": experiment,
            "group": r.group,
            "anonymous_id": anonymousId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let userId { ev["user_id"] = userId }
        send(event: ev)
    }

    // MARK: - Internals

    /// The identity map sent to `/sdk/evaluate`: bound attributes plus the
    /// persisted anon id (and the resolved user id when signed in).
    private func evaluateUser() -> [String: Any] {
        var u = userAttributes
        u["anonymous_id"] = anonymousId
        if let userId { u["user_id"] = userId }
        return u
    }

    private func stripPrivate(_ props: [String: Any]) -> [String: Any] {
        guard !privateAttributes.isEmpty else { return props }
        return props.filter { !privateAttributes.contains($0.key) }
    }

    // MARK: - see() structured error reporting

    /// Install a test sink that receives the built see() event instead of the
    /// network POST. Test-only; pass nil to restore the network path.
    func setSeeSink(_ sink: (@Sendable ([String: Any]) -> Void)?) {
        seeSink = sink
    }

    /// Build the wire event and fire-and-forget POST it to `/collect`. Spam-
    /// guarded. Never throws into caller code. Invoked from `SeeChain.to(_:)` via
    /// `Task { await client._dispatchSee(built) }`.
    func _dispatchSee(_ built: SeeBuilt) {
        let ev = buildSeeEvent(
            built.problem,
            subject: built.subject,
            outcome: built.outcome,
            extras: built.extras.map(stripPrivate),
            side: "client",
            sdkVersion: SDK_VERSION,
            env: env
        )
        if !seeLimiter.shouldSend(ev) { return }
        if let seeSink {
            seeSink(ev)
            return
        }
        send(event: ev)
    }

    /// POST `/sdk/evaluate` for the bound user and apply the returned
    /// assignments. Never throws into caller code — a failed refresh leaves the
    /// last-known assignments in place (or the safe defaults before first fetch).
    private func refresh() async {
        var body: [String: Any] = ["user": evaluateUser()]
        if !privateAttributes.isEmpty { body["private_attributes"] = privateAttributes }
        if !sticky.isEmpty { body["sticky"] = sticky }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var comps = URLComponents(url: baseURL.appendingPathComponent("/sdk/evaluate"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "env", value: env)]
        guard let url = comps?.url else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue(clientKey, forHTTPHeaderField: "X-SDK-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (respData, http) = try await transport(req)
            guard http.statusCode == 200,
                  let root = try? JSONSerialization.jsonObject(with: respData) as? [String: Any]
            else {
                Log.warn("shipeasy: /sdk/evaluate returned an unexpected response")
                return
            }
            apply(root)
            ready = true
        } catch {
            Log.warn("shipeasy: /sdk/evaluate failed: \(error)")
        }
    }

    /// Decode the flat assignment response into the read caches.
    private func apply(_ root: [String: Any]) {
        if let f = root["flags"] as? [String: Any] {
            var out: [String: Bool] = [:]
            for (k, v) in f { out[k] = (v as? Bool) ?? Eval.enabled(v) }
            flags = out
        }
        if let c = root["configs"] as? [String: Any] { configs = c }
        if let k = root["killswitches"] as? [String: Any] { killswitches = k }
        if let e = root["experiments"] as? [String: Any] {
            var out: [String: ExperimentResult] = [:]
            for (name, raw) in e {
                guard let m = raw as? [String: Any] else { continue }
                let params = m["params"]
                out[name] = ExperimentResult(
                    inExperiment: (m["inExperiment"] as? Bool) ?? false,
                    group: (m["group"] as? String) ?? "control",
                    params: params is NSNull ? nil : params
                )
            }
            experiments = out
        }
        if let s = root["sticky"] as? [String: Any] {
            sticky = s
            // Persist so a cold start keeps enrolled units pinned.
            if let data = try? JSONSerialization.data(withJSONObject: s),
               let str = String(data: data, encoding: .utf8) {
                store.set(ShipeasyClient.stickyStoreKey, str)
            }
        }
    }

    /// Fire-and-forget one event to `/collect` with the client key.
    private func send(event: [String: Any]) {
        let body: [String: Any] = ["events": [event]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let url = baseURL.appendingPathComponent("/collect")
        let key = clientKey
        let transport = self.transport
        Task {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = data
            req.setValue(key, forHTTPHeaderField: "X-SDK-Key")
            req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            _ = try? await transport(req)
        }
    }
}

// MARK: - Package-global client front door

/// Process-wide holder for the single ``ShipeasyClient`` built by
/// ``configureClient(clientKey:baseURL:env:session:store:disableTelemetry:privateAttributes:transport:)``.
/// First-config-wins, matching the server SDK's `configure(...)` idempotency.
final class ClientGlobal: @unchecked Sendable {
    static let shared = ClientGlobal()
    private let lock = NSLock()
    private var client: ShipeasyClient?

    func configureOnce(_ build: () -> ShipeasyClient) -> (ShipeasyClient, Bool) {
        lock.lock(); defer { lock.unlock() }
        if let client { return (client, false) }
        let c = build()
        client = c
        return (c, true)
    }

    func current() -> ShipeasyClient? {
        lock.lock(); defer { lock.unlock() }
        return client
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        client = nil
    }
}

/// Configure the package-global native client and kick off an initial anonymous
/// evaluation so flags resolve before an explicit ``ShipeasyClient/identify(_:)``.
///
/// First-config-wins: the first call builds the client; later calls return the
/// already-built one. Call this once at app launch with your **public client
/// key** (never a server key — a server key must never ship in an app binary).
/// The device `anonymous_id` is resolved from `store` (``UserDefaults`` by
/// default) and persisted, so a logged-out user buckets identically across
/// launches.
@discardableResult
public func configureClient(
    clientKey: String,
    baseURL: URL = URL(string: "https://api.shipeasy.ai")!,
    env: String = "prod",
    session: URLSession = .shared,
    store: AnonymousStore = UserDefaultsAnonymousStore(),
    disableTelemetry: Bool = false,
    telemetryURL: String = "https://t.shipeasy.ai",
    privateAttributes: [String] = [],
    transport: ShipeasyClient.Transport? = nil
) -> ShipeasyClient {
    let (client, fresh) = ClientGlobal.shared.configureOnce {
        ShipeasyClient(
            clientKey: clientKey,
            baseURL: baseURL,
            env: env,
            session: session,
            store: store,
            disableTelemetry: disableTelemetry,
            telemetryURL: telemetryURL,
            privateAttributes: privateAttributes,
            transport: transport
        )
    }
    if fresh {
        // Fire-and-forget an anonymous evaluation so `getFlag(...)` resolves for
        // logged-out users without an explicit identify().
        Task { await client.identify([:]) }
    }
    return client
}

/// The client built by ``configureClient(clientKey:...)``, or `nil` if not yet
/// configured.
public func shipeasyClient() -> ShipeasyClient? {
    ClientGlobal.shared.current()
}

/// Drop the package-global client. Tests only.
public func resetClientConfig() {
    ClientGlobal.shared.reset()
}
