import Foundation

public actor Client {
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

    // Local test mode: when true the client performs no network I/O. Network
    // init/poll are no-ops, the client is immediately "ready", and track(...)
    // is a no-op. Built only via `forTesting()`.
    private let localMode: Bool

    // Local overrides (Statsig-style). When set, an override wins over the
    // evaluated value in the matching getter. Usable on any client; on a
    // `forTesting()` client they are the only source of values. Access is
    // confined to the actor, like flagsBlob/expsBlob.
    private var flagOverrides: [String: Bool] = [:]
    private var configOverrides: [String: Any?] = [:]
    private var experimentOverrides: [String: ExperimentResult] = [:]

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://edge.shipeasy.dev")!,
        session: URLSession = .shared,
        env: String = "prod",
        disableTelemetry: Bool = false,
        telemetryURL: String = "https://t.shipeasy.ai"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.localMode = false
        // Per-evaluation usage telemetry. ON by default; pass
        // disableTelemetry: true to opt out. See Telemetry.swift.
        self.telemetry = Telemetry(
            endpoint: telemetryURL, sdkKey: apiKey, side: "server",
            env: env, disabled: disableTelemetry, session: session
        )
    }

    // Private designated init for the local test client. No API key is needed
    // and telemetry is force-disabled (empty key/endpoint disables it anyway).
    private init(localMode: Bool) {
        self.apiKey = ""
        self.baseURL = URL(string: "https://edge.shipeasy.dev")!
        self.session = .shared
        self.localMode = localMode
        self.initialized = true
        self.telemetry = Telemetry(
            endpoint: "", sdkKey: "", side: "server", env: "prod", disabled: true
        )
    }

    /// Build a no-network, immediately-usable client for tests. Telemetry is
    /// disabled, `initialize()`/`initializeOnce()` are no-ops, `track(...)` is a
    /// no-op, and no API key is required. Seed values with the `override*`
    /// setters; everything else evaluates against the (empty) local state.
    public static func forTesting() -> Client {
        Client(localMode: true)
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

    public func destroy() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func getFlag(_ name: String, user: [String: Any]) -> Bool {
        if let override = flagOverrides[name] { return override }
        telemetry.emit("gate", name)
        let gates = flagsBlob?["gates"] as? [String: Any]
        return Eval.evalGate(gates?[name] as? [String: Any], user)
    }

    public func getConfig(_ name: String) -> Any? {
        if configOverrides.keys.contains(name) { return configOverrides[name] ?? nil }
        telemetry.emit("config", name)
        let configs = flagsBlob?["configs"] as? [String: Any]
        let entry = configs?[name] as? [String: Any]
        return entry?["value"]
    }

    public func getExperiment(_ name: String, user: [String: Any], defaultParams: Any?) -> ExperimentResult {
        if let override = experimentOverrides[name] { return override }
        telemetry.emit("experiment", name)
        let exps = expsBlob?["experiments"] as? [String: Any]
        let exp = exps?[name] as? [String: Any]
        let r = Eval.evalExperiment(exp, flagsBlob, expsBlob, user)
        if r.params == nil {
            return ExperimentResult(inExperiment: r.inExperiment, group: r.group, params: defaultParams)
        }
        return r
    }

    public func track(userId: String, eventName: String, properties: [String: Any]? = nil) {
        if localMode { return }
        var event: [String: Any] = [
            "type": "metric",
            "event_name": eventName,
            "user_id": userId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
        ]
        if let properties, !properties.isEmpty { event["properties"] = properties }
        let body: [String: Any] = ["events": [event]]
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
        let (flagsStatus, flagsHeaders, flagsBody) = try await httpGet("/sdk/flags", etag: flagsEtag)
        if let pi = flagsHeaders["X-Poll-Interval"] as? String, let v = Int(pi) { pollIntervalSec = v }
        if flagsStatus == 200 {
            if let etag = flagsHeaders["Etag"] as? String { flagsEtag = etag }
            flagsBlob = try JSONSerialization.jsonObject(with: flagsBody) as? [String: Any]
        } else if flagsStatus != 304 {
            throw NSError(domain: "shipeasy", code: flagsStatus)
        }

        let (expsStatus, expsHeaders, expsBody) = try await httpGet("/sdk/experiments", etag: expsEtag)
        if expsStatus == 200 {
            if let etag = expsHeaders["Etag"] as? String { expsEtag = etag }
            expsBlob = try JSONSerialization.jsonObject(with: expsBody) as? [String: Any]
        } else if expsStatus != 304 {
            throw NSError(domain: "shipeasy", code: expsStatus)
        }
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
