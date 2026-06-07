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
        // Per-evaluation usage telemetry. ON by default; pass
        // disableTelemetry: true to opt out. See Telemetry.swift.
        self.telemetry = Telemetry(
            endpoint: telemetryURL, sdkKey: apiKey, side: "server",
            env: env, disabled: disableTelemetry, session: session
        )
    }

    public func initialize() async throws {
        try await fetchAll()
        initialized = true
        startPoll()
    }

    public func initializeOnce() async throws {
        guard !initialized else { return }
        try await fetchAll()
        initialized = true
    }

    public func destroy() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func getFlag(_ name: String, user: [String: Any]) -> Bool {
        telemetry.emit("gate", name)
        let gates = flagsBlob?["gates"] as? [String: Any]
        return Eval.evalGate(gates?[name] as? [String: Any], user)
    }

    public func getConfig(_ name: String) -> Any? {
        telemetry.emit("config", name)
        let configs = flagsBlob?["configs"] as? [String: Any]
        let entry = configs?[name] as? [String: Any]
        return entry?["value"]
    }

    public func getExperiment(_ name: String, user: [String: Any], defaultParams: Any?) -> ExperimentResult {
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
