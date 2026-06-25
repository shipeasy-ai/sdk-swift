import Foundation

/// Why a flag resolved to its value. Computed at the SDK boundary (see
/// `Engine.getFlagDetail`) without touching the canonical eval in `Eval`.
public enum FlagReason: String, Sendable {
    /// Engine never finished an initial fetch, so there is no live blob.
    case clientNotReady = "CLIENT_NOT_READY"
    /// The gate name is not present in the flags blob.
    case flagNotFound = "FLAG_NOT_FOUND"
    /// The gate exists but is disabled (or killed).
    case off = "OFF"
    /// A local override (set via `overrideFlag`) supplied the value.
    case override = "OVERRIDE"
    /// The gate evaluated to `true` for this user (rules + rollout matched).
    case ruleMatch = "RULE_MATCH"
    /// The gate evaluated to `false` for this user (default — not targeted).
    case `default` = "DEFAULT"
}

/// The result of evaluating a flag plus the reason it resolved that way.
public struct FlagDetail: Sendable {
    public let value: Bool
    public let reason: String

    public init(value: Bool, reason: String) {
        self.value = value
        self.reason = reason
    }

    init(value: Bool, reason: FlagReason) {
        self.value = value
        self.reason = reason.rawValue
    }
}

public actor Engine {
    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession

    private var flagsBlob: [String: Any]?
    private var expsBlob: [String: Any]?
    private var flagsEtag: String?
    private var expsEtag: String?
    private var pollIntervalSec: Int = 30
    private var pollTask: Task<Void, Never>?
    private var initialized = false
    private let telemetry: Telemetry

    // Attribute names usable for targeting but never persisted in analytics
    // (LD/Statsig `privateAttributes`). The server evaluates locally, so private
    // attrs never leave for evaluation; the only egress is `/collect`, where the
    // listed keys are stripped from every outbound `track()` payload.
    private let privateAttributes: [String]

    // Sticky-bucketing store (doc 20 §2). When set, getExperiment locks a unit to
    // its first-assigned variant — changing allocation % / weights won't
    // re-bucket enrolled units (rotating the experiment salt is the reshuffle
    // lever). Absent ⇒ deterministic (fully backward compatible).
    private let stickyStore: StickyBucketStore?

    // Local test mode: when true the client performs no network I/O. Network
    // init/poll are no-ops, the client is immediately "ready", and track(...)
    // is a no-op. Built only via `forTesting()`.
    private let localMode: Bool

    // Deployment env, tagged onto see() error events. Telemetry already carries
    // env in its URL prefix; see() needs it as an explicit wire field.
    private let env: String

    // Per-process spam guard for see() error reports. Bound here so a hot loop
    // can't flood /collect (dedup window + hard cap; see SeeLimiter).
    private let seeLimiter = SeeLimiter()

    // Local overrides (Statsig-style). When set, an override wins over the
    // evaluated value in the matching getter. Usable on any client; on a
    // `forTesting()` client they are the only source of values. Access is
    // confined to the actor, like flagsBlob/expsBlob.
    private var flagOverrides: [String: Bool] = [:]
    private var configOverrides: [String: Any?] = [:]
    private var experimentOverrides: [String: ExperimentResult] = [:]

    // Change listeners (Feature C). Fire after a fetch applies NEW data (a 200,
    // not a 304). With the background poll running this fires on each refresh
    // that brings new data; without it, listeners fire on the next manual fetch
    // that applies new data. Never fired in localMode. Keyed by a monotonic id
    // so unsubscribe can remove the exact registration.
    private var changeListeners: [Int: @Sendable () -> Void] = [:]
    private var nextListenerId = 0

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://edge.shipeasy.dev")!,
        session: URLSession = .shared,
        env: String = "prod",
        disableTelemetry: Bool = false,
        telemetryURL: String = "https://t.shipeasy.ai",
        privateAttributes: [String] = [],
        stickyStore: StickyBucketStore? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.localMode = false
        self.env = env
        self.privateAttributes = privateAttributes
        self.stickyStore = stickyStore
        // Per-evaluation usage telemetry. ON by default; pass
        // disableTelemetry: true to opt out. See Telemetry.swift.
        self.telemetry = Telemetry(
            endpoint: telemetryURL, sdkKey: apiKey, side: "server",
            env: env, disabled: disableTelemetry, session: session
        )
        // Register as the default client backing the package-level see() funcs
        // (last constructed wins — the server-SDK analog of TS's shipeasy({key})).
        setDefaultClient(self)
    }

    // Private designated init for the local test client. No API key is needed
    // and telemetry is force-disabled (empty key/endpoint disables it anyway).
    private init(localMode: Bool) {
        self.apiKey = ""
        self.baseURL = URL(string: "https://edge.shipeasy.dev")!
        self.session = .shared
        self.localMode = localMode
        self.env = "prod"
        self.initialized = true
        self.privateAttributes = []
        self.stickyStore = nil
        self.telemetry = Telemetry(
            endpoint: "", sdkKey: "", side: "server", env: "prod", disabled: true
        )
    }

    /// Build a no-network, immediately-usable client for tests. Telemetry is
    /// disabled, `initialize()`/`initializeOnce()` are no-ops, `track(...)` is a
    /// no-op, and no API key is required. Seed values with the `override*`
    /// setters; everything else evaluates against the (empty) local state.
    public static func forTesting() -> Engine {
        Engine(localMode: true)
    }

    // Private designated init for an offline, snapshot-backed client. Loads the
    // blob fields directly, runs in localMode (no network), is immediately
    // initialized, and force-disables telemetry. Overrides apply on top.
    private init(
        snapshotFlags: [String: Any]?,
        snapshotExperiments: [String: Any]?,
        stickyStore: StickyBucketStore? = nil
    ) {
        self.apiKey = ""
        self.baseURL = URL(string: "https://edge.shipeasy.dev")!
        self.session = .shared
        self.localMode = true
        self.env = "prod"
        self.initialized = true
        self.flagsBlob = snapshotFlags
        self.expsBlob = snapshotExperiments
        self.privateAttributes = []
        self.stickyStore = stickyStore
        self.telemetry = Telemetry(
            endpoint: "", sdkKey: "", side: "server", env: "prod", disabled: true
        )
    }

    /// Build an offline client from in-memory snapshot blobs (Feature D). `flags`
    /// is the body of `/sdk/flags` (e.g. `["gates": …, "configs": …]`) and
    /// `experiments` the body of `/sdk/experiments` (e.g. `["experiments": …,
    /// "universes": …]`). The client performs no network I/O, is immediately
    /// ready, telemetry is off, `initialize()`/`initializeOnce()`/`track(...)`
    /// are no-ops, and evaluations run the real eval against the snapshot.
    /// Overrides apply on top.
    public static func fromSnapshot(
        flags: [String: Any],
        experiments: [String: Any],
        stickyStore: StickyBucketStore? = nil
    ) -> Engine {
        Engine(snapshotFlags: flags, snapshotExperiments: experiments, stickyStore: stickyStore)
    }

    /// Build an offline client from a JSON file (Feature D). The file is a JSON
    /// object `{ "flags": <body of /sdk/flags>, "experiments": <body of
    /// /sdk/experiments> }`. Parsed with `JSONSerialization`, matching how the
    /// live blobs are decoded. Behaves exactly like `fromSnapshot`.
    public static func fromFile(_ path: String) throws -> Engine {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let flags = root?["flags"] as? [String: Any]
        let experiments = root?["experiments"] as? [String: Any]
        return Engine(snapshotFlags: flags, snapshotExperiments: experiments)
    }

    public func initialize() async throws {
        if localMode { return }
        try await fetchAll()
        initialized = true
        startPoll()
    }

    public func initializeOnce() async throws {
        if localMode { return }
        guard !initialized else { return }
        try await fetchAll()
        initialized = true
    }

    // MARK: - Local overrides

    /// Force `getFlag(name:...)` to return `value` regardless of the live blob.
    public func overrideFlag(_ name: String, _ value: Bool) {
        flagOverrides[name] = value
    }

    /// Force `getConfig(name)` to return `value` regardless of the live blob.
    public func overrideConfig(_ name: String, _ value: Any?) {
        configOverrides[name] = value
    }

    /// Force `getExperiment(name:...)` to return an in-experiment result with
    /// the given group + params, regardless of the live blob.
    public func overrideExperiment(_ name: String, group: String, params: Any?) {
        experimentOverrides[name] = ExperimentResult(inExperiment: true, group: group, params: params)
    }

    /// Drop all local overrides; subsequent reads fall back to live evaluation.
    public func clearOverrides() {
        flagOverrides.removeAll()
        configOverrides.removeAll()
        experimentOverrides.removeAll()
    }

    // MARK: - Change listeners

    /// Register a listener fired after a fetch applies NEW data (a 200 — not a
    /// 304). When the background poll is running (after `initialize()`), this
    /// fires on each poll that brings new data; on a client that does not poll
    /// in the background, listeners fire on the next fetch that applies new data
    /// (i.e. on refresh). Never fired in `localMode`. Returns an unsubscribe
    /// closure; call it to stop receiving notifications.
    @discardableResult
    public func onChange(_ listener: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let id = nextListenerId
        nextListenerId += 1
        changeListeners[id] = listener
        return { [weak self] in
            guard let self = self else { return }
            Task { await self.removeListener(id) }
        }
    }

    private func removeListener(_ id: Int) {
        changeListeners[id] = nil
    }

    // Invoke every registered listener safely. Listener bodies are isolated from
    // each other — a crash in one would only affect that closure. Skipped in
    // localMode.
    private func notifyChange() {
        if localMode { return }
        for listener in changeListeners.values {
            listener()
        }
    }

    // Internal seam: apply freshly-fetched blobs and fire change listeners. The
    // fetch path calls this only when it actually applied NEW data; tests drive
    // it directly to exercise the listener contract without the network.
    func applyData(flags: [String: Any]?, experiments: [String: Any]?, fireChange: Bool, markReady: Bool = false) {
        if let flags { flagsBlob = flags }
        if let experiments { expsBlob = experiments }
        if markReady { initialized = true }
        if fireChange { notifyChange() }
    }

    public func destroy() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Evaluate a flag and explain why it resolved that way (Feature B). The
    /// reason is computed at this boundary without touching `Eval.evalGate`:
    ///
    /// 1. override set → `OVERRIDE` (short-circuits before telemetry)
    /// 2. client not ready → `CLIENT_NOT_READY`, value `false`
    /// 3. gate absent from blob → `FLAG_NOT_FOUND`, value `false`
    /// 4. gate present but disabled/killed → `OFF`, value `false`
    /// 5. else run `Eval.evalGate`; `RULE_MATCH` if true, `DEFAULT` if false
    ///
    /// The usage beacon is emitted exactly once here (steps 2–5), never on
    /// `OVERRIDE`.
    public func getFlagDetail(_ name: String, user: [String: Any]) -> FlagDetail {
        // 1. Override wins, short-circuit before telemetry (matches getExperiment).
        if let override = flagOverrides[name] {
            return FlagDetail(value: override, reason: .override)
        }
        // Single telemetry beacon for the non-override path.
        telemetry.emit("gate", name)
        // 2. No live blob yet.
        guard initialized, let flagsBlob else {
            return FlagDetail(value: false, reason: .clientNotReady)
        }
        // 3. Gate not present in the blob.
        let gates = flagsBlob["gates"] as? [String: Any]
        guard let gate = gates?[name] as? [String: Any] else {
            return FlagDetail(value: false, reason: .flagNotFound)
        }
        // 4. Gate disabled or killed (read the same fields evalGate reads).
        if Eval.enabled(gate["killswitch"]) || !Eval.enabled(gate["enabled"]) {
            return FlagDetail(value: false, reason: .off)
        }
        // 5. Real evaluation.
        let result = Eval.evalGate(gate, user)
        return FlagDetail(value: result, reason: result ? .ruleMatch : .default)
    }

    public func getFlag(_ name: String, user: [String: Any]) -> Bool {
        getFlagDetail(name, user: user).value
    }

    /// Evaluate a flag, returning `default` only when the flag cannot be
    /// evaluated — i.e. the client is not ready or the flag is not found — never
    /// when it simply evaluates to `false` (Feature A).
    public func getFlag(_ name: String, user: [String: Any], default defaultValue: Bool = false) -> Bool {
        let d = getFlagDetail(name, user: user)
        if d.reason == FlagReason.clientNotReady.rawValue || d.reason == FlagReason.flagNotFound.rawValue {
            return defaultValue
        }
        return d.value
    }

    public func getConfig(_ name: String) -> Any? {
        getConfig(name, default: nil)
    }

    /// Read a dynamic config, returning `default` when the key is absent
    /// (Feature A). An override always wins; an override pinned to `nil` returns
    /// `nil`, not the default.
    public func getConfig(_ name: String, default defaultValue: Any? = nil) -> Any? {
        if configOverrides.keys.contains(name) { return configOverrides[name] ?? nil }
        telemetry.emit("config", name)
        let configs = flagsBlob?["configs"] as? [String: Any]
        guard let entry = configs?[name] as? [String: Any] else { return defaultValue }
        return entry["value"]
    }

    public func getExperiment(_ name: String, user: [String: Any], defaultParams: Any?) -> ExperimentResult {
        if let override = experimentOverrides[name] { return override }
        telemetry.emit("experiment", name)
        let exps = expsBlob?["experiments"] as? [String: Any]
        let exp = exps?[name] as? [String: Any]
        let r = Eval.evalExperiment(
            exp, flagsBlob, expsBlob, user, name: name, stickyStore: stickyStore
        )
        if r.params == nil {
            return ExperimentResult(inExperiment: r.inExperiment, group: r.group, params: defaultParams)
        }
        return r
    }

    /// Return whether kill switch `name` is engaged (the feature is killed). In
    /// this SDK kill switches ride the flags blob alongside gates and are folded
    /// into gate evaluation; `getKillswitch` reads that same signal at the
    /// boundary. With `switchKey` it reports a named per-key override (the
    /// dashboard "switches" feature) when present, falling back to the kill
    /// switch's top-level value otherwise. Returns `false` (not killed) when the
    /// client isn't ready or the switch is absent.
    public func getKillswitch(_ name: String, switchKey: String? = nil) -> Bool {
        let killswitches = flagsBlob?["killswitches"] as? [String: Any]
        guard let entry = killswitches?[name] as? [String: Any] else { return false }
        if let switchKey {
            let switches = entry["switches"] as? [String: Any]
            if let raw = switches?[switchKey] {
                return Eval.enabled(raw)
            }
        }
        return Eval.enabled(entry["value"] ?? entry["enabled"])
    }

    /// Batch-evaluate every loaded gate, config and experiment for `user` into a
    /// bootstrap payload (`["flags": ..., "configs": ..., "experiments": ...,
    /// "killswitches": ...]`) keyed to match the browser SDK's
    /// `window.__SE_BOOTSTRAP` shape. Local overrides win. Killswitches are
    /// folded into per-gate evaluation, so the standalone `killswitches` map is
    /// empty for this SDK. No telemetry (a batch evaluate is not a per-flag
    /// exposure).
    public func evaluate(_ user: [String: Any]) -> [String: Any] {
        var outFlags: [String: Any] = [:]
        var outConfigs: [String: Any] = [:]
        var outExps: [String: Any] = [:]

        if let gates = flagsBlob?["gates"] as? [String: Any] {
            for (name, raw) in gates {
                if let ov = flagOverrides[name] {
                    outFlags[name] = ov
                } else {
                    outFlags[name] = Eval.evalGate(raw as? [String: Any], user)
                }
            }
        }
        if let configs = flagsBlob?["configs"] as? [String: Any] {
            for (name, raw) in configs {
                if configOverrides.keys.contains(name) {
                    outConfigs[name] = (configOverrides[name] ?? nil) ?? NSNull()
                } else if let entry = raw as? [String: Any] {
                    outConfigs[name] = entry["value"] ?? NSNull()
                }
            }
        }
        if let exps = expsBlob?["experiments"] as? [String: Any] {
            for (name, raw) in exps {
                let r = experimentOverrides[name]
                    ?? Eval.evalExperiment(raw as? [String: Any], flagsBlob, expsBlob, user, name: name, stickyStore: stickyStore)
                outExps[name] = [
                    "inExperiment": r.inExperiment,
                    "group": r.group,
                    "params": r.params ?? NSNull(),
                ]
            }
        }

        return [
            "flags": outFlags,
            "configs": outConfigs,
            "experiments": outExps,
            "killswitches": [String: Any](),
        ]
    }

    /// Return the cross-platform SSR bootstrap `<script>` tag for a request:
    /// `se-bootstrap.js` reads its `data-*` attributes and hydrates
    /// `window.__SE_BOOTSTRAP` (and writes the anon cookie). No SDK key is
    /// embedded — the server key must never reach the browser.
    public func bootstrapScriptTag(
        _ user: [String: Any],
        anonId: String? = nil,
        i18nProfile: String = "en:prod",
        baseURL: String? = nil
    ) -> String {
        let payload = evaluate(user)
        let base = Engine.cdnBase(baseURL)
        let profile = i18nProfile.isEmpty ? "en:prod" : i18nProfile
        var attrs = "data-se-bootstrap"
        attrs += " " + Engine.attr("data-flags", Engine.jsonString(payload["flags"]))
        attrs += " " + Engine.attr("data-configs", Engine.jsonString(payload["configs"]))
        attrs += " " + Engine.attr("data-experiments", Engine.jsonString(payload["experiments"]))
        attrs += " " + Engine.attr("data-killswitches", Engine.jsonString(payload["killswitches"]))
        attrs += " " + Engine.attr("data-i18n-profile", profile)
        attrs += " " + Engine.attr("data-api-url", base)
        if let anonId, !anonId.isEmpty {
            attrs += " " + Engine.attr("data-anon-id", anonId)
        }
        return "<script src=\"\(Engine.escapeAttr("\(base)/sdk/bootstrap.js"))\" \(attrs)></script>"
    }

    /// Return the i18n loader `<script>` tag. The loader fetches translations for
    /// the profile using the PUBLIC client key (safe to embed in HTML).
    public func i18nScriptTag(_ clientKey: String, profile: String = "en:prod", baseURL: String? = nil) -> String {
        let base = Engine.cdnBase(baseURL)
        let p = profile.isEmpty ? "en:prod" : profile
        return "<script src=\"\(Engine.escapeAttr("\(base)/sdk/i18n/loader.js"))\" \(Engine.attr("data-key", clientKey)) \(Engine.attr("data-profile", p))></script>"
    }

    private static let defaultCDNBase = "https://cdn.shipeasy.ai"

    private static func cdnBase(_ override: String?) -> String {
        var base = (override?.isEmpty == false) ? override! : defaultCDNBase
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    private static func jsonString(_ value: Any?) -> String {
        guard let value,
              let data = try? JSONSerialization.data(withJSONObject: value),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private static func attr(_ name: String, _ value: String) -> String {
        "\(name)=\"\(escapeAttr(value))\""
    }

    private static func escapeAttr(_ v: String) -> String {
        v.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    // Drop caller-marked private attributes from an outbound props bag before it
    // leaves for /collect. Private attrs may drive local targeting but are never
    // persisted in analytics (LD/Statsig parity). Returns the input unchanged
    // when there is nothing to strip.
    private func stripPrivate(_ props: [String: Any]?) -> [String: Any]? {
        guard let props, !privateAttributes.isEmpty else { return props }
        return props.filter { !privateAttributes.contains($0.key) }
    }

    public func track(userId: String, eventName: String, properties: [String: Any]? = nil) {
        if localMode { return }
        var event: [String: Any] = [
            "type": "metric",
            "event_name": eventName,
            "user_id": userId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let safeProps = stripPrivate(properties)
        if let safeProps, !safeProps.isEmpty { event["properties"] = safeProps }
        let body: [String: Any] = ["events": [event]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        Task { try? await self.post("/collect", body: data) }
    }

    /// Emit an exposure event for an experiment at the server-side decision
    /// point (parity with the browser's auto-exposure). The server is stateless
    /// and never auto-logs, so call this when you actually present the treatment.
    /// Re-evaluates `experiment` for the user; if enrolled, POSTs a single
    /// `{type:"exposure", experiment, group, user_id, ts}` to `/collect`.
    /// No-op in local mode or when the user is not enrolled.
    public func logExposure(userId: String, experiment: String) {
        if localMode { return }
        let result = getExperiment(experiment, user: ["user_id": userId], defaultParams: nil)
        guard result.inExperiment else { return }
        let event: [String: Any] = [
            "type": "exposure",
            "experiment": experiment,
            "group": result.group,
            "user_id": userId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        let body: [String: Any] = ["events": [event]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        Task { try? await self.post("/collect", body: data) }
    }

    // MARK: - see() structured error reporting

    // Test seam: when set, see() events are handed here (after limiter + sanitize)
    // instead of being POSTed. Capturing real POSTs from an actor is awkward; this
    // mirrors Telemetry's `sender` seam. Set via `setSeeSink(_:)`.
    private var seeSink: (@Sendable ([String: Any]) -> Void)?

    /// Install a test sink that receives the built see() event instead of the
    /// network POST. Test-only; pass nil to restore the network path.
    func setSeeSink(_ sink: (@Sendable ([String: Any]) -> Void)?) {
        seeSink = sink
    }

    /// Build the wire event and fire-and-forget POST it to /collect. No-op in
    /// local mode. Spam-guarded. Never throws into caller code. Invoked from
    /// `SeeChain.to(_:)` via `Task { await client._dispatchSee(built) }`.
    func _dispatchSee(_ built: SeeBuilt) {
        if localMode { return }
        let ev = buildSeeEvent(
            built.problem,
            subject: built.subject,
            outcome: built.outcome,
            extras: stripPrivate(built.extras),
            side: "server",
            sdkVersion: SDK_VERSION,
            env: env
        )
        if !seeLimiter.shouldSend(ev) { return }
        if let seeSink {
            seeSink(ev)
            return
        }
        let body: [String: Any] = ["events": [ev]]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        Task { try? await self.post("/collect", body: data) }
    }

    private func startPoll() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                let interval = await self.pollIntervalSec
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                try? await self.fetchAll()
            }
        }
    }

    private func fetchAll() async throws {
        // Track whether either blob applied NEW data (a 200, not a 304) so
        // change listeners fire exactly once per refresh that brings new data.
        var appliedNewData = false

        let (flagsStatus, flagsHeaders, flagsBody) = try await httpGet("/sdk/flags", etag: flagsEtag)
        if let pi = flagsHeaders["X-Poll-Interval"] as? String, let v = Int(pi) { pollIntervalSec = v }
        if flagsStatus == 200 {
            if let etag = flagsHeaders["Etag"] as? String { flagsEtag = etag }
            flagsBlob = try JSONSerialization.jsonObject(with: flagsBody) as? [String: Any]
            appliedNewData = true
        } else if flagsStatus != 304 {
            throw NSError(domain: "shipeasy", code: flagsStatus)
        }

        let (expsStatus, expsHeaders, expsBody) = try await httpGet("/sdk/experiments", etag: expsEtag)
        if expsStatus == 200 {
            if let etag = expsHeaders["Etag"] as? String { expsEtag = etag }
            expsBlob = try JSONSerialization.jsonObject(with: expsBody) as? [String: Any]
            appliedNewData = true
        } else if expsStatus != 304 {
            throw NSError(domain: "shipeasy", code: expsStatus)
        }

        if appliedNewData { notifyChange() }
    }

    private func httpGet(_ path: String, etag: String?) async throws -> (Int, [AnyHashable: Any], Data) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue(apiKey, forHTTPHeaderField: "X-SDK-Key")
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: req)
        let http = response as? HTTPURLResponse
        return (http?.statusCode ?? 0, http?.allHeaderFields ?? [:], data)
    }

    private func post(_ path: String, body: Data) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue(apiKey, forHTTPHeaderField: "X-SDK-Key")
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        _ = try await session.data(for: req)
    }
}
