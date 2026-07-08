import XCTest
@testable import Shipeasy

// Self-monitoring channel: when the SDK swallows an internal ("on our end")
// error via safeRun, it also ships a structured see event to Shipeasy's OWN
// project — a baked-in destination + public client key, distinct from the
// consumer's see() path. These tests pin the wire shape, the enable gating, the
// dedup, and the no-throw guarantee. Mirrors the TS reference
// (sdk-ts/src/__tests__/internal-report.test.ts) using the channel's sink seam
// instead of stubbing the HTTP layer.
final class InternalReportTests: XCTestCase {

    // A real-looking client key to exercise the send path (the baked default is
    // an inert placeholder until the real key is minted).
    static let fakeKey = "sdk_client_testfakekey00000000000000000000"

    /// Thread-safe recorder for captured internal events via the channel's sink.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [[String: Any]] = []
        func add(_ e: [String: Any]) { lock.lock(); events.append(e); lock.unlock() }
        var all: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return events }
    }

    struct Boom: Error, CustomStringConvertible { let description: String }

    override func setUp() {
        super.setUp()
        InternalReport.shared.resetForTest()
        InternalReport.shared.setIngestKeyForTest(Self.fakeKey)
    }

    override func tearDown() {
        InternalReport.shared.resetForTest()
        Log.setSink(nil)
        Log.level = .warn
        super.tearDown()
    }

    // Install a sink, run body, return captured events.
    private func withSink(_ body: () -> Void) -> [[String: Any]] {
        let sink = Sink()
        InternalReport.shared.setSinkForTest { sink.add($0) }
        body()
        return sink.all
    }

    // MARK: destination + wire shape

    func testBuildsStableConsequenceWithSdkMarker() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        let events = withSink {
            reportInternalError("Client.getExperiment", Boom(description: "boom"))
        }
        XCTAssertEqual(events.count, 1)
        let ev = events[0]
        XCTAssertEqual(ev["type"] as? String, "error")
        XCTAssertEqual(ev["kind"] as? String, "caught")
        XCTAssertEqual(ev["subject"] as? String, "Client.getExperiment")
        XCTAssertEqual(ev["outcome"] as? String, "returned a safe default")
        XCTAssertEqual(ev["error_type"] as? String, "Boom")
        XCTAssertEqual(ev["message"] as? String, "boom")
        XCTAssertEqual(ev["side"] as? String, "server")
        XCTAssertEqual(ev["sdk_version"] as? String, "9.9.9")
        let extras = ev["extras"] as? [String: Any]
        XCTAssertEqual(extras?["sdk"] as? String, "swift")
    }

    func testDoesNotAttachConsumerEnv() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        let events = withSink {
            reportInternalError("flags.getKillswitch", Boom(description: "x"))
        }
        // The internal channel carries no consumer env — only the SDK-side context.
        XCTAssertNil(events[0]["env"])
    }

    func testBakedDestinationAndPlaceholderConstants() {
        XCTAssertEqual(InternalReport.ingestURL, "https://api.shipeasy.ai/collect")
        XCTAssertEqual(InternalReport.placeholderKey, "sdk_client_REPLACE_WITH_SHIPEASY_INTERNAL_ERROR_KEY")
    }

    // MARK: enable gating

    func testNoOpBeforeContextIsSet() {
        // resetForTest cleared the context; no setContext here.
        let events = withSink {
            reportInternalError("flags.getDetail", Boom(description: "boom"))
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testNoOpWhenDisabled() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: false)
        let events = withSink {
            reportInternalError("flags.getDetail", Boom(description: "boom"))
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testInertWhileKeyIsPlaceholder() {
        InternalReport.shared.setIngestKeyForTest(InternalReport.placeholderKey)
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        let events = withSink {
            reportInternalError("flags.getDetail", Boom(description: "boom"))
        }
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: resilience

    func testDedupesIdenticalInternalErrorsToOneSend() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        // Same error value => same fingerprint => one send within the window.
        let err = Boom(description: "same")
        let events = withSink {
            reportInternalError("flags.getDetail", err)
            reportInternalError("flags.getDetail", err)
        }
        XCTAssertEqual(events.count, 1)
    }

    func testNeverThrows() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        // No sink installed → the real (network) path runs; it must never throw
        // into caller code even when it dispatches a doomed request.
        XCTAssertNoThrow(reportInternalError("flags.getDetail", Boom(description: "boom")))
    }

    // MARK: safeRun integration

    func testSafeRunReportsSwallowedErrorAndReturnsFallback() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        Log.setSink { _, _ in }  // swallow the local error log
        let events = withSink {
            let out: String = safeRun("flags.getConfig", "fallback") {
                throw Boom(description: "internal invariant")
            }
            XCTAssertEqual(out, "fallback")
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0]["subject"] as? String, "flags.getConfig")
        XCTAssertEqual(events[0]["message"] as? String, "internal invariant")
    }

    func testSafeRunDoesNotReportOnSuccess() {
        InternalReport.shared.setContext(side: "server", sdkVersion: "9.9.9", enabled: true)
        let events = withSink {
            let out: Bool = safeRun("flags.getDetail", false) { true }
            XCTAssertTrue(out)
        }
        XCTAssertTrue(events.isEmpty)
    }
}
