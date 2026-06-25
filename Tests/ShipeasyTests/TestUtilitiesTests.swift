import XCTest
@testable import Shipeasy

final class TestUtilitiesTests: XCTestCase {
    // forTesting() builds a usable client with no API key and never touches the
    // network; initialize() is a no-op rather than an HTTP fetch.
    func testForTestingNeedsNoNetworkOrKey() async throws {
        let client = Engine.forTesting()
        // Would throw / hang if it tried to fetch from the edge; in local mode
        // it returns immediately.
        try await client.initialize()
        try await client.initializeOnce()
        // Unset entities fall back to defaults (no crash, no network).
        let flag = await client.getFlag("missing", user: ["id": "u1"])
        XCTAssertFalse(flag)
        let config = await client.getConfig("missing")
        XCTAssertNil(config)
        let exp = await client.getExperiment("missing", user: ["id": "u1"], defaultParams: nil)
        XCTAssertFalse(exp.inExperiment)
    }

    // Each override is returned by its matching getter.
    func testOverridesWin() async {
        let client = Engine.forTesting()

        await client.overrideFlag("new_checkout", true)
        let flag = await client.getFlag("new_checkout", user: [:])
        XCTAssertTrue(flag)

        await client.overrideConfig("limits", ["max": 10])
        let config = await client.getConfig("limits") as? [String: Int]
        XCTAssertEqual(config?["max"], 10)

        await client.overrideExperiment("price_test", group: "treatment", params: ["price": 9])
        let exp = await client.getExperiment("price_test", user: [:], defaultParams: nil)
        XCTAssertTrue(exp.inExperiment)
        XCTAssertEqual(exp.group, "treatment")
        XCTAssertEqual((exp.params as? [String: Int])?["price"], 9)
    }

    // overrideConfig can pin a nil value distinctly from "no override".
    func testOverrideConfigNil() async {
        let client = Engine.forTesting()
        await client.overrideConfig("maybe", nil)
        let config = await client.getConfig("maybe")
        XCTAssertNil(config)
    }

    // clearOverrides resets every override back to default evaluation.
    func testClearOverridesResets() async {
        let client = Engine.forTesting()
        await client.overrideFlag("f", true)
        await client.overrideConfig("c", 42)
        await client.overrideExperiment("e", group: "t", params: nil)

        await client.clearOverrides()

        let flag = await client.getFlag("f", user: [:])
        XCTAssertFalse(flag)
        let config = await client.getConfig("c")
        XCTAssertNil(config)
        let exp = await client.getExperiment("e", user: [:], defaultParams: nil)
        XCTAssertFalse(exp.inExperiment)
    }

    // track() is a no-op in local mode and never crashes / sends.
    func testTrackNoOps() async {
        let client = Engine.forTesting()
        await client.track(userId: "u1", eventName: "purchase", properties: ["amount": 10])
        await client.track(userId: "u1", eventName: "view")
        // Reaching here without crashing is the assertion.
        XCTAssertTrue(true)
    }

    // MARK: - Feature A: defaults

    // getFlag(default:) returns the default only when the flag can't be
    // evaluated (not-found / not-ready), never when it evaluates to false.
    func testGetFlagDefaultOnlyWhenUnevaluable() async {
        let snapshot: [String: Any] = [
            "gates": [
                "on_for_all": ["enabled": true, "rolloutPct": 10000, "salt": "s"],
                "off_gate": ["enabled": false],
            ]
        ]
        let client = Engine.fromSnapshot(flags: snapshot, experiments: [:])

        // Evaluates true → returns the real value, ignores default.
        let onVal = await client.getFlag("on_for_all", user: ["user_id": "u1"], default: true)
        XCTAssertTrue(onVal)

        // Gate present but disabled → evaluates false; default is NOT used.
        let offVal = await client.getFlag("off_gate", user: ["user_id": "u1"], default: true)
        XCTAssertFalse(offVal)

        // Flag not found → default is used.
        let missing = await client.getFlag("nope", user: ["user_id": "u1"], default: true)
        XCTAssertTrue(missing)
        let missingFalse = await client.getFlag("nope", user: ["user_id": "u1"], default: false)
        XCTAssertFalse(missingFalse)
    }

    // getConfig(default:) returns the default only when the key is absent.
    func testGetConfigDefault() async {
        let snapshot: [String: Any] = [
            "configs": ["limits": ["value": ["max": 10]]]
        ]
        let client = Engine.fromSnapshot(flags: snapshot, experiments: [:])

        let present = await client.getConfig("limits", default: ["max": 99]) as? [String: Int]
        XCTAssertEqual(present?["max"], 10)

        let absent = await client.getConfig("missing", default: ["max": 99]) as? [String: Int]
        XCTAssertEqual(absent?["max"], 99)

        // Existing nil-default behaviour preserved.
        let absentNil = await client.getConfig("missing")
        XCTAssertNil(absentNil)
    }

    // MARK: - Feature B: flag detail reasons

    func testFlagDetailReasons() async {
        let snapshot: [String: Any] = [
            "gates": [
                "on_for_all": ["enabled": true, "rolloutPct": 10000, "salt": "s"],
                "off_gate": ["enabled": false],
                "killed": ["enabled": true, "killswitch": true, "rolloutPct": 10000],
                "targeted": [
                    "enabled": true, "rolloutPct": 10000, "salt": "s",
                    "rules": [["attr": "country", "op": "eq", "value": "US"]],
                ],
            ]
        ]
        let client = Engine.fromSnapshot(flags: snapshot, experiments: [:])

        let match = await client.getFlagDetail("on_for_all", user: ["user_id": "u1"])
        XCTAssertTrue(match.value)
        XCTAssertEqual(match.reason, FlagReason.ruleMatch.rawValue)

        let off = await client.getFlagDetail("off_gate", user: ["user_id": "u1"])
        XCTAssertFalse(off.value)
        XCTAssertEqual(off.reason, FlagReason.off.rawValue)

        let killed = await client.getFlagDetail("killed", user: ["user_id": "u1"])
        XCTAssertFalse(killed.value)
        XCTAssertEqual(killed.reason, FlagReason.off.rawValue)

        let notFound = await client.getFlagDetail("nope", user: ["user_id": "u1"])
        XCTAssertFalse(notFound.value)
        XCTAssertEqual(notFound.reason, FlagReason.flagNotFound.rawValue)

        // Rule fails → DEFAULT (evaluated false, not OFF/not-found).
        let def = await client.getFlagDetail("targeted", user: ["user_id": "u1", "country": "CA"])
        XCTAssertFalse(def.value)
        XCTAssertEqual(def.reason, FlagReason.default.rawValue)

        // Override short-circuits to OVERRIDE.
        await client.overrideFlag("off_gate", true)
        let overridden = await client.getFlagDetail("off_gate", user: ["user_id": "u1"])
        XCTAssertTrue(overridden.value)
        XCTAssertEqual(overridden.reason, FlagReason.override.rawValue)
    }

    // CLIENT_NOT_READY when there is no blob yet (forTesting has none).
    func testFlagDetailClientNotReady() async {
        let client = Engine.forTesting()
        let d = await client.getFlagDetail("anything", user: ["user_id": "u1"])
        XCTAssertFalse(d.value)
        XCTAssertEqual(d.reason, FlagReason.clientNotReady.rawValue)
    }

    // MARK: - Feature C: change listeners

    func testOnChangeFiresOnApplyAndUnsubscribe() async {
        // Use a network-backed client (localMode never fires listeners) and
        // drive the internal apply-data seam directly.
        let client = Engine(apiKey: "k", disableTelemetry: true)
        let counter = Counter()

        let unsub = await client.onChange { counter.increment() }

        await client.applyData(flags: ["gates": [:]], experiments: nil, fireChange: true)
        XCTAssertEqual(counter.value, 1)

        // No fireChange (e.g. a 304) → listener not called.
        await client.applyData(flags: ["gates": [:]], experiments: nil, fireChange: false)
        XCTAssertEqual(counter.value, 1)

        await client.applyData(flags: ["gates": [:]], experiments: nil, fireChange: true)
        XCTAssertEqual(counter.value, 2)

        // Unsubscribe stops further notifications.
        unsub()
        // Allow the async removal Task to run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await client.applyData(flags: ["gates": [:]], experiments: nil, fireChange: true)
        XCTAssertEqual(counter.value, 2)
    }

    // Listeners never fire in localMode.
    func testOnChangeSilentInLocalMode() async {
        let client = Engine.forTesting()
        let counter = Counter()
        await client.onChange { counter.increment() }
        await client.applyData(flags: ["gates": [:]], experiments: nil, fireChange: true)
        XCTAssertEqual(counter.value, 0)
    }

    // MARK: - Feature D: offline snapshot

    func testFromSnapshotEvaluatesWithNoNetwork() async {
        let snapshot: [String: Any] = [
            "gates": ["new_checkout": ["enabled": true, "rolloutPct": 10000, "salt": "s"]],
            "configs": ["copy": ["value": ["headline": "Hi"]]],
        ]
        let exps: [String: Any] = [
            "experiments": [
                "price_test": [
                    "status": "running", "salt": "s", "allocationPct": 10000,
                    "groups": [["name": "treatment", "weight": 10000, "params": ["price": 9]]],
                ]
            ]
        ]
        let client = Engine.fromSnapshot(flags: snapshot, experiments: exps)
        // initialize() is a no-op (no network) and does not throw.
        try? await client.initialize()

        let flag = await client.getFlag("new_checkout", user: ["user_id": "u1"])
        XCTAssertTrue(flag)
        let cfg = await client.getConfig("copy") as? [String: String]
        XCTAssertEqual(cfg?["headline"], "Hi")
        let r = await client.getExperiment("price_test", user: ["user_id": "u1"], defaultParams: nil)
        XCTAssertTrue(r.inExperiment)
        XCTAssertEqual(r.group, "treatment")

        // Overrides apply on top of the snapshot.
        await client.overrideFlag("new_checkout", false)
        let overridden = await client.getFlag("new_checkout", user: ["user_id": "u1"])
        XCTAssertFalse(overridden)
    }
}

// Minimal thread-safe counter for listener assertions.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
