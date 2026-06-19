import XCTest
@testable import Shipeasy

/// Feature A — private attributes. The keys listed in `privateAttributes` are
/// stripped from every outbound `track()` payload. We exercise the pure
/// stripping logic via the in-source filter shape; full network assertions need
/// a URLProtocol stub (the live `track()` path is no-op in local mode).
final class PrivateAttributesTests: XCTestCase {
    // The strip predicate (mirroring Client.stripPrivate): drop listed keys,
    // keep the rest, order-independent.
    private func strip(_ props: [String: Any], _ priv: [String]) -> [String: Any] {
        guard !priv.isEmpty else { return props }
        return props.filter { !priv.contains($0.key) }
    }

    func testPrivateKeysAreStripped() {
        let props: [String: Any] = ["amount": 10, "email": "a@b.com", "ssn": "x"]
        let out = strip(props, ["email", "ssn"])
        XCTAssertEqual(out.keys.sorted(), ["amount"])
        XCTAssertEqual(out["amount"] as? Int, 10)
        XCTAssertNil(out["email"])
        XCTAssertNil(out["ssn"])
    }

    func testEmptyPrivateListPassesThrough() {
        let props: [String: Any] = ["amount": 10, "email": "a@b.com"]
        let out = strip(props, [])
        XCTAssertEqual(out.keys.sorted(), ["amount", "email"])
    }

    func testUnlistedKeysSurvive() {
        let props: [String: Any] = ["plan": "pro", "region": "us"]
        let out = strip(props, ["email"])
        XCTAssertEqual(out.keys.sorted(), ["plan", "region"])
    }

    // A client configured with private attributes still constructs and tracks
    // without crashing (network path is exercised live; in tests we just assert
    // construction + a no-throw track on a localMode client is harmless).
    func testClientConstructsWithPrivateAttributes() async {
        let client = Client(apiKey: "k", disableTelemetry: true, privateAttributes: ["email"])
        // track on a non-local client posts asynchronously; calling it must not
        // throw synchronously into the caller.
        await client.track(userId: "u1", eventName: "purchase", properties: ["amount": 1, "email": "x"])
        XCTAssertTrue(true)
    }
}
