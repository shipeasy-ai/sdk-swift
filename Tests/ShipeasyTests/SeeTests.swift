import XCTest
@testable import Shipeasy

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SeeTests: ShipeasyProdEnvTestCase {
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

    /// A no-op transport so a real `ShipeasyClient` never touches the network.
    private static let noopTransport: ShipeasyClient.Transport = { req in
        (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func makeClient(privateAttributes: [String] = []) -> ShipeasyClient {
        ShipeasyClient(
            clientKey: "pk_key",
            baseURL: URL(string: "https://e.x")!,
            isTrackingEnabled: false,
            privateAttributes: privateAttributes,
            transport: Self.noopTransport
        )
    }

    /// Build a client with a sink installed, run `body`, then drain the actor so
    /// any `to(_:)`-dispatched Task has flushed into the sink. `to(_:)` hops onto
    /// the actor via a detached Task; polling the sink after `body` serializes
    /// behind those Tasks because the actor runs its mailbox in order. We
    /// additionally sleep briefly for cross-thread settle.
    private func withClient(
        privateAttributes: [String] = [],
        expectEvents: Int,
        _ body: (ShipeasyClient) -> Void
    ) async -> [[String: Any]] {
        let sink = Sink()
        let c = makeClient(privateAttributes: privateAttributes)
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
        XCTAssertEqual(ev["side"] as? String, "client")
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

    func testInlineExtrasOnToMergeOverPriorExtras() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "x")).causesThe("checkout")
                .extras(["order_id": "o1", "region": "eu"])
                // Inline extras fold under the earlier .extras — later wins on a
                // shared key ("region"), and adds a new one ("attempt").
                .to("use cached prices", extras: ["region": "us", "attempt": 2])
        }
        let ev = events[0]
        XCTAssertEqual(ev["outcome"] as? String, "use cached prices")
        let extras = ev["extras"] as? [String: Any]
        XCTAssertEqual(extras?["order_id"] as? String, "o1")   // untouched
        XCTAssertEqual(extras?["region"] as? String, "us")     // inline wins
        XCTAssertEqual((extras?["attempt"] as? NSNumber)?.intValue, 2) // added
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

    // MARK: Cross-network correlation (X-SE-Correlation)

    func testCorrelateInjectsFreshHeaderAndReturnsToken() {
        var original = URLRequest(url: URL(string: "https://api.example.com/feed")!)
        original.setValue("application/json", forHTTPHeaderField: "Accept")
        let (req, token) = correlate(original)
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-SE-Correlation"), token)
        XCTAssertTrue(isValidCorrelationId(token))
        XCTAssertNotNil(UUID(uuidString: token))
        // Other headers and the URL are preserved; the original is untouched.
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(req.url, original.url)
        XCTAssertNil(original.value(forHTTPHeaderField: "X-SE-Correlation"))
        // One token per request — correlating again replaces it.
        let (req2, token2) = correlate(req)
        XCTAssertNotEqual(token, token2)
        XCTAssertEqual(req2.value(forHTTPHeaderField: "X-SE-Correlation"), token2)
    }

    func testCorrelatedEventCarriesCorrelationId() async {
        let (_, token) = correlate(URLRequest(url: URL(string: "https://api.example.com/feed")!))
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "502")).correlated(with: token)
                .causesThe("feed").to("show the cached feed")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["correlation_id"] as? String, token)
    }

    func testUncorrelatedEventOmitsCorrelationId() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "x")).correlated(with: nil)
                .causesThe("feed").to("show the cached feed")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0]["correlation_id"])
    }

    func testMalformedCorrelationIdIsDropped() async {
        let events = await withClient(expectEvents: 1) { c in
            c.see(Boom(description: "x")).correlated(with: "bad token!")
                .causesThe("feed").to("show the cached feed")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0]["correlation_id"])
    }

    func testCorrelationIdValidation() {
        XCTAssertTrue(isValidCorrelationId("abcd1234"))
        XCTAssertTrue(isValidCorrelationId(UUID().uuidString))
        XCTAssertTrue(isValidCorrelationId(String(repeating: "a", count: 64)))
        XCTAssertFalse(isValidCorrelationId("short"))                         // < 8
        XCTAssertFalse(isValidCorrelationId(String(repeating: "a", count: 65))) // > 64
        XCTAssertFalse(isValidCorrelationId("has space1"))
        XCTAssertFalse(isValidCorrelationId("under_score"))
        XCTAssertFalse(isValidCorrelationId("ünicode-123"))
        XCTAssertFalse(isValidCorrelationId(""))
        // buildSeeEvent drops a malformed id even if one slips past the chain.
        let ev = buildSeeEvent(
            .message("m"), subject: "s", outcome: "o", extras: nil,
            side: "client", sdkVersion: SDK_VERSION, env: nil,
            correlationId: "not valid!"
        )
        XCTAssertNil(ev["correlation_id"])
    }

    // MARK: Pure-function / no-network cases

    func testControlFlowMarksAndReportsNothing() async {
        let sink = Sink()
        let c = makeClient()
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
            side: "client",
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
