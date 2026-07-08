import XCTest
@testable import Shipeasy

/// Hardening contract (mirrors the TS SDK):
///  1. Runtime reads NEVER throw or trap — adversarial/garbage blobs resolve to
///     safe defaults instead of crashing.
///  2. The leveled logger gates on `LogLevel`: `.silent` mutes, `.warn` emits.
final class NoThrowLoggingTests: XCTestCase {

    // Thread-safe capture of logged lines via the Log test sink.
    final class LogRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [(LogLevel, String)] = []
        func add(_ l: LogLevel, _ m: String) { lock.lock(); lines.append((l, m)); lock.unlock() }
        var all: [(LogLevel, String)] { lock.lock(); defer { lock.unlock() }; return lines }
        var count: Int { lock.lock(); defer { lock.unlock() }; return lines.count }
    }

    override func setUp() {
        super.setUp()
        // This class constructs reporting-enabled engines (the public network
        // init leaves the process-global InternalReport channel enabled) and
        // trips the safeRun guard via adversarial/malformed snapshot reads. The
        // baked ingest key is now REAL, so an enabled channel + tripped guard
        // could fire a live POST to api.shipeasy.ai/collect. Force the key back
        // to the inert placeholder for every test here so no read in this class
        // can ever reach the real send — keyConfigured() gates on it.
        InternalReport.shared.setIngestKeyForTest(InternalReport.placeholderKey)
    }

    override func tearDown() {
        Log.setSink(nil)
        Log.level = .warn
        // Leave the channel inert for whatever test runs next.
        InternalReport.shared.setIngestKeyForTest(InternalReport.placeholderKey)
        super.tearDown()
    }

    // MARK: - LogLevel ordering

    func testLogLevelOrdering() {
        XCTAssertTrue(LogLevel.silent < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.warn)
        XCTAssertTrue(LogLevel.warn < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.debug)
    }

    // MARK: - Runtime reads never trap on adversarial input

    /// A snapshot whose blobs are the wrong shapes at every level (gates is a
    /// number, a gate is a string, configs is an array, experiments is a bool…).
    /// Every runtime read must resolve to a safe default and never trap.
    func testAdversarialSnapshotReadsReturnSafeDefaults() async {
        let flags: [String: Any] = [
            "gates": 42,                       // not an object
            "configs": ["not", "an", "object"],// array where object expected
            "killswitches": "nope",            // string where object expected
        ]
        let experiments: [String: Any] = [
            "experiments": true,               // bool where object expected
            "universes": NSNull(),
        ]
        let engine = Engine.fromSnapshot(flags: flags, experiments: experiments)

        let flag = await engine.getFlag("anything", user: ["user_id": "u1"])
        XCTAssertFalse(flag)

        let flagDefault = await engine.getFlag("anything", user: ["user_id": "u1"], default: true)
        // Absent gate → FLAG_NOT_FOUND → the supplied default is honoured.
        XCTAssertTrue(flagDefault)

        let detail = await engine.getFlagDetail("anything", user: [:])
        XCTAssertFalse(detail.value)

        let config = await engine.getConfig("missing", default: "fallback")
        XCTAssertEqual(config as? String, "fallback")

        let ks = await engine.getKillswitch("missing")
        XCTAssertFalse(ks)

        let exp = await engine.getExperiment("missing", user: [:], defaultParams: ["p": 1])
        XCTAssertFalse(exp.inExperiment)

        // A batch evaluate over garbage must also not trap.
        let evaluated = await engine.evaluate(["user_id": "u1", "anonymous_id": ""])
        XCTAssertNotNil(evaluated["flags"])

        // Track / logExposure on a snapshot (localMode) are no-ops, never trap.
        await engine.track(userId: "u1", eventName: "evt", properties: ["k": Double.nan])
        await engine.logExposure(userId: "u1", experiment: "missing")
    }

    /// Deeply malformed gate/experiment bodies (wrong-typed rules, rollout, etc.)
    /// still resolve without trapping.
    func testMalformedGateAndExperimentBodies() async {
        let flags: [String: Any] = [
            "gates": [
                "g1": ["enabled": "yes", "rules": 5, "killswitch": ["weird": true]],
                "g2": "totally not a gate",
            ],
            "configs": [
                "c1": ["value": ["nested": [1, 2, 3]]],
                "c2": "not an object",
            ],
            "killswitches": [
                "k1": ["value": "on", "switches": 99],
            ],
        ]
        let experiments: [String: Any] = [
            "experiments": [
                "e1": ["groups": "nope", "allocation": "half"],
            ],
        ]
        let engine = Engine.fromSnapshot(flags: flags, experiments: experiments)

        _ = await engine.getFlag("g1", user: ["user_id": "u1"])
        _ = await engine.getFlag("g2", user: ["user_id": "u1"])
        _ = await engine.getFlagDetail("g1", user: [:])
        _ = await engine.getConfig("c1")
        _ = await engine.getConfig("c2")
        _ = await engine.getKillswitch("k1", switchKey: "some")
        _ = await engine.getExperiment("e1", user: ["user_id": "u1"], defaultParams: nil)
        // Reaching here without a trap IS the assertion.
        XCTAssertTrue(true)
    }

    // MARK: - AnonId no force-unwrap trap

    func testAnonIdResolveOnAdversarialCookie() {
        // A tampered value (invalid charset) must be treated as absent and minted,
        // not force-unwrapped.
        let r = AnonId.resolve(cookieHeader: "__se_anon_id=has spaces & bad!")
        XCTAssertTrue(r.minted)
        XCTAssertFalse(r.id.isEmpty)
        // A valid UUID cookie is passed through.
        let uuid = AnonId.mint()
        let r2 = AnonId.resolve(cookieHeader: "__se_anon_id=\(uuid)")
        XCTAssertFalse(r2.minted)
        XCTAssertEqual(r2.id, uuid)
    }

    // MARK: - Log level gating

    func testSilentMutesAndWarnEmits() {
        let rec = LogRecorder()
        Log.setSink { rec.add($0, $1) }

        // .silent mutes every level.
        Log.level = .silent
        Log.error("e"); Log.warn("w"); Log.info("i"); Log.debug("d")
        XCTAssertEqual(rec.count, 0, "silent must mute all logs")

        // .warn emits error + warn, drops info + debug.
        Log.level = .warn
        Log.error("e"); Log.warn("w"); Log.info("i"); Log.debug("d")
        let levels = rec.all.map { $0.0 }
        XCTAssertEqual(levels, [.error, .warn], "warn emits error+warn only")
    }

    func testDebugEmitsAllLevels() {
        let rec = LogRecorder()
        Log.setSink { rec.add($0, $1) }
        Log.level = .debug
        Log.error("e"); Log.warn("w"); Log.info("i"); Log.debug("d")
        XCTAssertEqual(rec.count, 4)
    }

    /// The engine's `logLevel` sets the process-global `Log.level`.
    func testEngineInitSetsGlobalLogLevel() {
        _ = Engine(apiKey: "srv_key", baseURL: URL(string: "https://e.x")!, logLevel: .silent)
        XCTAssertEqual(Log.level, .silent)
        _ = Engine(apiKey: "srv_key", baseURL: URL(string: "https://e.x")!, logLevel: .debug)
        XCTAssertEqual(Log.level, .debug)
    }
}
