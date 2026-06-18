import XCTest
@testable import Shipeasy

final class TestUtilitiesTests: XCTestCase {
    // forTesting() builds a usable client with no API key and never touches the
    // network; initialize() is a no-op rather than an HTTP fetch.
    func testForTestingNeedsNoNetworkOrKey() async throws {
        let client = Client.forTesting()
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
        let client = Client.forTesting()

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
        let client = Client.forTesting()
        await client.overrideConfig("maybe", nil)
        let config = await client.getConfig("maybe")
        XCTAssertNil(config)
    }

    // clearOverrides resets every override back to default evaluation.
    func testClearOverridesResets() async {
        let client = Client.forTesting()
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
        let client = Client.forTesting()
        await client.track(userId: "u1", eventName: "purchase", properties: ["amount": 10])
        await client.track(userId: "u1", eventName: "view")
        // Reaching here without crashing is the assertion.
        XCTAssertTrue(true)
    }
}
