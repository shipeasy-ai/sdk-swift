import XCTest
@testable import Shipeasy

final class SeeTests: XCTestCase {
    /// Thread-safe recorder for captured see() events via the actor's seeSink.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [[String: Any]] = []
        func add(_ e: [String: Any]) { lock.lock(); events.append(e); lock.unlock() }
        var all: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return events }
    }

    struct Boom: Error, CustomStringConvertible {
        let description: String
    }

    /// Build a real (network-mode) client with a sink installed, run `body`, then
    /// drain the actor so any `to(_:)`-dispatched Task has flushed into the sink.
    /// `to(_:)` hops onto the actor via a detached Task; awaiting a no-op actor
    /// call after `body` serializes behind those Tasks because the actor runs its
    /// mailbox in order. We additionally sleep briefly for cross-thread settle.
    private func withClient(
        privateAttributes: [String] = [],
        expectEvents: Int,
        _ body: (Engine) -> Void
    ) async -> [[String: Any]] {
        let sink = Sink()
        let c = Engine(apiKey: "srv_key", baseURL: URL(string: "https://e.x")!,
                       privateAttributes: privateAttributes)
        await c.setSeeSink { sink.add($0) }
        body(c)
        // Poll the sink until it reaches the expected count (or a timeout). For
        // expectEvents == 0 this just gives stray Tasks a chance to (not) fire.
        let deadline = Date().addingTimeInterval(3)
        while sink.all.count < expectEvents && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        return sink.all
    }

    func testCaughtExceptionReportsErrorEvent() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "boom")).causesThe("checkout").to("use cached prices")
        }
        XCTAssertEqual(events.count, 1)
        let ev = events[0]
        XCTAssertEqual(ev["type"] as? String, "error")
        XCTAssertEqual(ev["kind"] as? String, "caught")
        XCTAssertEqual(ev["error_type"] as? String, "Boom")
        XCTAssertEqual(ev["message"] as? String, "boom")
        XCTAssertEqual(ev["subject"] as? String, "checkout")
        XCTAssertEqual(ev["outcome"] as? String, "use cached prices")
        XCTAssertEqual(ev["side"] as? String, "server")
        XCTAssertEqual(ev["sdk_version"] as? String, SDK_VERSION)
        XCTAssertEqual(ev["env"] as? String, "prod")
        XCTAssertNotNil(ev["stack"])
    }

    func testExtrasBeforeToAreSanitizedAndSent() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "x")).causesThe("photo upload")
                .extras(["photo_id": "p1", "size": 42, "ok": true, "skip": NSNull()])
                .to("be rejected")
        }
        let extras = events[0]["extras"] as? [String: Any]
        XCTAssertEqual(extras?["photo_id"] as? String, "p1")
        XCTAssertEqual((extras?["size"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual(extras?["ok"] as? Bool, true)
        XCTAssertNil(extras?["skip"])
    }

    func testViolationUsesViolationKind() async {
        let events = await withClient(expectEvents: 1) { c in
            c.seeViolation("large query").causesThe("search results").to("be trimmed")
        }
        let ev = events[0]
        XCTAssertEqual(ev["kind"] as? String, "violation")
        XCTAssertEqual(ev["error_type"] as? String, "large query")
        XCTAssertEqual(ev["message"] as? String, "large query")
        XCTAssertEqual(ev["subject"] as? String, "search results")
        XCTAssertNil(ev["stack"])
    }

    func testDefaultsWhenConsequenceOmitted() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "x")).to("be incomplete")
        }
        XCTAssertEqual(events[0]["subject"] as? String, "app")
    }

    func testToIsIdempotent() async {
        let events = await withClient(expectEvents: 1) { c in
            let chain = c.see(Boom(description: "x")).causesThe("checkout")
            chain.to("a")
            chain.to("b")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["outcome"] as? String, "a")
    }

    func testToRequiredNoSendWithoutTerminal() async {
        let events = await withClient(expectEvents: 0) { c in
            _ = c.see(Boom(description: "x")).causesThe("checkout") // no .to()
        }
        XCTAssertEqual(events.count, 0)
    }

    func testPrivateAttributesStrippedFromExtras() async {
        let events = await withClient(privateAttributes: ["secret"], expectEvents: 1) { c in
            c.see(Boom(description: "x")).causesThe("checkout")
                .extras(["secret": "shh", "ok": "yes"])
                .to("use cached prices")
        }
        let extras = events[0]["extras"] as? [String: Any]
        XCTAssertNil(extras?["secret"])
        XCTAssertEqual(extras?["ok"] as? String, "yes")
    }

    // MARK: Pure-function / no-network cases

    func testTestModeIsNoop() async {
        let sink = Sink()
        let c = Engine.forTesting()
        await c.setSeeSink { sink.add($0) }
        c.see(Boom(description: "x")).causesThe("checkout").to("use cached prices")
        // Give any (incorrectly scheduled) Task a chance to run.
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(sink.all.isEmpty)
    }

    func testControlFlowMarksAndReportsNothing() async {
        let sink = Sink()
        let c = Engine(apiKey: "srv_key", baseURL: URL(string: "https://e.x")!)
        await c.setSeeSink { sink.add($0) }
        let tail = c.controlFlowException(Boom(description: "not a Foo"))
            .because("because it wasn't an encoded Foo")
            .extras(["tried": "Foo"])
        XCTAssertEqual(tail.reason, "because it wasn't an encoded Foo")
        XCTAssertEqual(tail.localExtras?["tried"] as? String, "Foo")
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(sink.all.isEmpty)
    }

    func testGlobalSeeBeforeClientWarnsAndDrops() {
        setDefaultClient(nil)
        // Must not crash and must produce a no-op chain.
        see(Boom(description: "x")).causesThe("checkout").to("use cached prices")
        seeViolation("v").causesThe("x").to("y")
    }

    func testSanitizeExtrasCapsKeysAndValueLength() {
        var big: [String: Any] = [:]
        for i in 0..<30 { big["k\(i)"] = i }
        big["long"] = String(repeating: "x", count: 500)
        let out = sanitizeExtras(big)!
        XCTAssertLessThanOrEqual(out.count, SEE_MAX_EXTRA_KEYS)
    }

    func testSanitizeExtrasDropsNonScalarsAndNonFinite() {
        let out = sanitizeExtras([
            "s": "str",
            "i": 7,
            "d": 3.14,
            "b": false,
            "nan": Double.nan,
            "inf": Double.infinity,
            "null": NSNull(),
            "arr": [1, 2, 3],
        ])!
        XCTAssertEqual(out["s"] as? String, "str")
        XCTAssertEqual((out["i"] as? NSNumber)?.intValue, 7)
        XCTAssertEqual(out["b"] as? Bool, false)
        XCTAssertNil(out["nan"])
        XCTAssertNil(out["inf"])
        XCTAssertNil(out["null"])
        XCTAssertNil(out["arr"])
    }

    func testSanitizeExtrasTruncatesStringValue() {
        let out = sanitizeExtras(["long": String(repeating: "x", count: 500)])!
        XCTAssertEqual((out["long"] as? String)?.count, SEE_MAX_EXTRA_VALUE)
    }

    func testBuildSeeEventTruncatesMessageAndSubject() {
        let ev = buildSeeEvent(
            .message(String(repeating: "m", count: 600)),
            subject: String(repeating: "s", count: 300),
            outcome: "o",
            extras: nil,
            side: "server",
            sdkVersion: SDK_VERSION,
            env: nil
        )
        XCTAssertEqual((ev["message"] as? String)?.count, SEE_MAX_MESSAGE)
        XCTAssertEqual((ev["subject"] as? String)?.count, SEE_MAX_SUBJECT)
        XCTAssertNil(ev["env"]) // omitted when nil
        XCTAssertNil(ev["extras"]) // omitted when empty
    }

    func testLimiterDedupsAndCaps() {
        let lim = SeeLimiter(maxPerProcess: 3, dedupWindowMs: 30_000)
        let ev: [String: Any] = ["kind": "caught", "error_type": "E", "message": "m"]
        XCTAssertTrue(lim.shouldSend(ev))   // first
        XCTAssertFalse(lim.shouldSend(ev))  // dedup within window
        let ev2: [String: Any] = ["kind": "caught", "error_type": "E2", "message": "m"]
        XCTAssertTrue(lim.shouldSend(ev2))
        let ev3: [String: Any] = ["kind": "caught", "error_type": "E3", "message": "m"]
        XCTAssertTrue(lim.shouldSend(ev3))
        let ev4: [String: Any] = ["kind": "caught", "error_type": "E4", "message": "m"]
        XCTAssertFalse(lim.shouldSend(ev4)) // hard cap of 3 reached
    }
}
