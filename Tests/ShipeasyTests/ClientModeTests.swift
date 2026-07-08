import XCTest
@testable import Shipeasy

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native mobile client (`ShipeasyClient`): the client-key `/sdk/evaluate` path
/// plus the whole point of the client SDK — a device `anonymous_id` that is
/// PERSISTED across launches so a logged-out visitor buckets identically every
/// cold start. These tests inject an in-memory store + a stub transport so they
/// run hermetically (no network, no UserDefaults).
final class ClientModeTests: ShipeasyProdEnvTestCase {

    /// An in-memory `AnonymousStore` standing in for UserDefaults/Keychain.
    final class MemStore: AnonymousStore, @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: String]
        private(set) var setKeys: [String] = []
        init(_ seed: [String: String] = [:]) { self.map = seed }
        func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[key] }
        func set(_ key: String, _ value: String) {
            lock.lock(); defer { lock.unlock() }
            map[key] = value; setKeys.append(key)
        }
    }

    /// Records every request and replies with a canned `/sdk/evaluate` body.
    final class StubTransport: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [URLRequest] = []
        var evaluateResponse: [String: Any]
        var failEvaluate = false
        init(evaluateResponse: [String: Any] = [:]) { self.evaluateResponse = evaluateResponse }

        func record(_ req: URLRequest) { lock.lock(); defer { lock.unlock() }; requests.append(req) }
        func requestsFor(_ pathSuffix: String) -> [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return requests.filter { $0.url?.path.hasSuffix(pathSuffix) ?? false }
        }

        var transport: ShipeasyClient.Transport {
            { [self] req in
                record(req)
                let path = req.url?.path ?? ""
                if path.hasSuffix("/sdk/evaluate") {
                    if failEvaluate { throw URLError(.notConnectedToInternet) }
                    let data = try JSONSerialization.data(withJSONObject: evaluateResponse)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (data, resp)
                }
                // /collect etc.
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(), resp)
            }
        }
    }

    private func bodyJSON(_ req: URLRequest) -> [String: Any]? {
        guard let b = req.httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: b)) as? [String: Any]
    }

    func testAdoptsPersistedAnonId() async {
        let store = MemStore([AnonId.cookie: "anon_persisted_123"])
        let stub = StubTransport(evaluateResponse: ["flags": ["f": true], "configs": [:], "experiments": [:], "killswitches": [:]])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        let anon = await client.anonymousId
        XCTAssertEqual(anon, "anon_persisted_123")
        await client.identify(["user_id": "u1"])
        // The persisted id (not a fresh mint) is what the edge evaluated on.
        let evalReq = stub.requestsFor("/sdk/evaluate").first
        let user = (bodyJSON(evalReq!)?["user"]) as? [String: Any]
        XCTAssertEqual(user?["anonymous_id"] as? String, "anon_persisted_123")
        // Nothing minted → nothing written for the anon key.
        XCTAssertFalse(store.setKeys.contains(AnonId.cookie))
    }

    func testMintsAndPersistsOnFirstRun() async {
        let store = MemStore()
        let stub = StubTransport(evaluateResponse: ["flags": [:], "configs": [:], "experiments": [:], "killswitches": [:]])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        let anon = await client.anonymousId
        XCTAssertFalse(anon.isEmpty)
        // A non-empty id was written back for the next launch.
        XCTAssertEqual(store.get(AnonId.cookie), anon)
        XCTAssertTrue(store.setKeys.contains(AnonId.cookie))
    }

    func testReadsReturnDefaultsBeforeIdentify() async {
        let store = MemStore()
        let stub = StubTransport()
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        let f = await client.getFlag("f", default: false)
        let c = await client.getConfig("c")
        let a = await client.universe("checkout").assign()
        XCTAssertFalse(f)
        XCTAssertNil(c)
        XCTAssertFalse(a.enrolled)
        XCTAssertNil(a.group)
    }

    func testIdentifyEvaluatesAndCaches() async {
        let store = MemStore()
        let stub = StubTransport(evaluateResponse: [
            "flags": ["new_ui": true],
            "configs": ["theme": ["accent": "blue"]],
            "experiments": ["exp1": ["inExperiment": true, "group": "treatment", "params": ["copy": "hi"], "universe": "checkout"]],
            "universes": ["checkout": ["defaults": ["copy": "default"]]],
            "killswitches": ["payments": true],
        ])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])

        let f = await client.getFlag("new_ui")
        XCTAssertTrue(f)
        let cfg = await client.getConfig("theme") as? [String: Any]
        XCTAssertEqual(cfg?["accent"] as? String, "blue")
        let a = await client.universe("checkout").assign()
        XCTAssertTrue(a.enrolled)
        XCTAssertEqual(a.name, "exp1")
        XCTAssertEqual(a.group, "treatment")
        let ks = await client.getKillswitch("payments")
        XCTAssertTrue(ks)

        // Auth header carried the client key on the evaluate call.
        let evalReq = stub.requestsFor("/sdk/evaluate").first
        XCTAssertEqual(evalReq?.value(forHTTPHeaderField: "X-SDK-Key"), "pk")
    }

    /// Enrolled: `assign()` reads the variant params the edge pre-merged, and
    /// auto-logs exactly one exposure to /collect.
    func testUniverseAssignEnrolledReadsVariantAndLogsExposure() async {
        let store = MemStore([AnonId.cookie: "anon_e"])
        let stub = StubTransport(evaluateResponse: [
            "flags": [:], "configs": [:], "killswitches": [:],
            "experiments": ["exp1": [
                "inExperiment": true, "group": "treatment",
                // Edge pre-merges universe defaults ⊕ variant into params.
                "params": ["button_color": "blue", "size": 1], "universe": "checkout",
            ]],
            "universes": ["checkout": ["defaults": ["button_color": "red", "size": 1]]],
        ])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])

        let a = await client.universe("checkout").assign()
        XCTAssertTrue(a.enrolled)
        XCTAssertEqual(a.name, "exp1")
        XCTAssertEqual(a.group, "treatment")
        // Variant override wins; unset field inherited (pre-merged); absent → fallback.
        XCTAssertEqual(a.get("button_color", "x"), "blue")
        XCTAssertEqual(a.get("size", 0), 1)
        XCTAssertEqual(a.get("missing", "fb"), "fb")

        // Exactly one exposure auto-logged for the enrolled unit.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let exposures = stub.requestsFor("/collect").compactMap { bodyJSON($0) }
            .compactMap { ($0["events"] as? [[String: Any]])?.first }
            .filter { $0["type"] as? String == "exposure" }
        XCTAssertEqual(exposures.count, 1)
        XCTAssertEqual(exposures.first?["experiment"] as? String, "exp1")
        XCTAssertEqual(exposures.first?["group"] as? String, "treatment")
        XCTAssertEqual(exposures.first?["anonymous_id"] as? String, "anon_e")
    }

    /// Not enrolled: `assign()` resolves `get()` to the universe defaults, no
    /// exposure is emitted, and group/name are nil.
    func testUniverseAssignNotEnrolledResolvesUniverseDefaults() async {
        let store = MemStore()
        let stub = StubTransport(evaluateResponse: [
            "flags": [:], "configs": [:], "killswitches": [:],
            "experiments": ["exp1": [
                "inExperiment": false, "group": "control", "universe": "checkout",
            ]],
            "universes": ["checkout": ["defaults": ["button_color": "red"]]],
        ])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])

        let a = await client.universe("checkout").assign()
        XCTAssertFalse(a.enrolled)
        XCTAssertNil(a.name)
        XCTAssertNil(a.group)
        // Not enrolled → universe default resolves.
        XCTAssertEqual(a.get("button_color", "x"), "red")
        XCTAssertEqual(a.get("missing", "fb"), "fb")

        // No exposure for a not-enrolled unit.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let exposures = stub.requestsFor("/collect").compactMap { bodyJSON($0) }
            .compactMap { ($0["events"] as? [[String: Any]])?.first }
            .filter { $0["type"] as? String == "exposure" }
        XCTAssertTrue(exposures.isEmpty)
    }

    /// `assign(logExposure: false)` suppresses the auto-exposure while still
    /// returning the enrolled assignment.
    func testUniverseAssignSuppressesExposureWhenAsked() async {
        let store = MemStore()
        let stub = StubTransport(evaluateResponse: [
            "flags": [:], "configs": [:], "killswitches": [:],
            "experiments": ["exp1": [
                "inExperiment": true, "group": "treatment", "params": [:], "universe": "checkout",
            ]],
            "universes": ["checkout": ["defaults": [:]]],
        ])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])

        let a = await client.universe("checkout").assign(logExposure: false)
        XCTAssertTrue(a.enrolled)

        try? await Task.sleep(nanoseconds: 100_000_000)
        let exposures = stub.requestsFor("/collect").compactMap { bodyJSON($0) }
            .compactMap { ($0["events"] as? [[String: Any]])?.first }
            .filter { $0["type"] as? String == "exposure" }
        XCTAssertTrue(exposures.isEmpty)
    }

    func testFailedEvaluateIsNonFatal() async {
        let store = MemStore()
        let stub = StubTransport()
        stub.failEvaluate = true
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])   // must not throw
        let f = await client.getFlag("f", default: true)
        XCTAssertTrue(f, "reads fall back to the supplied default when no assignments loaded")
    }

    func testTrackPostsToCollectWithAnonId() async {
        let store = MemStore([AnonId.cookie: "anon_x"])
        let stub = StubTransport(evaluateResponse: ["flags": [:], "configs": [:], "experiments": [:], "killswitches": [:]])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])
        await client.track("checkout", properties: ["value": 42])

        // Give the fire-and-forget /collect Task a moment to run.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let collects = stub.requestsFor("/collect")
        XCTAssertFalse(collects.isEmpty)
        let metric = collects.compactMap { bodyJSON($0) }
            .compactMap { ($0["events"] as? [[String: Any]])?.first }
            .first { $0["type"] as? String == "metric" }
        XCTAssertEqual(metric?["event_name"] as? String, "checkout")
        XCTAssertEqual(metric?["anonymous_id"] as? String, "anon_x")
    }

    func testStickyStateRoundTripsAndPersists() async {
        let store = MemStore()
        let stub = StubTransport(evaluateResponse: [
            "flags": [:], "configs": [:], "experiments": [:], "killswitches": [:],
            "sticky": ["exp1": ["g": "treatment", "s": "abc12345"]],
        ])
        let client = ShipeasyClient(clientKey: "pk", isTrackingEnabled: false, store: store, transport: stub.transport)
        await client.identify(["user_id": "u1"])
        // Sticky persisted for the next launch.
        XCTAssertNotNil(store.get("__se_sticky"))
        // A second evaluate echoes the sticky state back to the edge.
        await client.refreshAssignments()
        let evalReqs = stub.requestsFor("/sdk/evaluate")
        let lastBody = bodyJSON(evalReqs.last!)
        let sticky = lastBody?["sticky"] as? [String: Any]
        XCTAssertNotNil(sticky?["exp1"])
    }
}
