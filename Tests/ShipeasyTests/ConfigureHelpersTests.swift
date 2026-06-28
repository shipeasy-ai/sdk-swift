import XCTest
@testable import Shipeasy

/// Doc-23 configure() family + package-level helpers, all read through the bound
/// Client (never the Engine). Each test resets the package-global config first.
final class ConfigureHelpersTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetGlobalConfig()
    }

    override func tearDown() {
        resetGlobalConfig()
        super.tearDown()
    }

    func testConfigureForTestingSeedsAndReplaces() async throws {
        await configureForTesting(
            flags: ["new_checkout": true],
            configs: ["theme": "blue"],
            experiments: ["price_test": (group: "treatment", params: ["price": 9])]
        )
        let c = try Client(["user_id": "u_1"])
        let on = await c.getFlag("new_checkout", default: false)
        XCTAssertTrue(on)
        let theme = await c.getConfig("theme", default: nil) as? String
        XCTAssertEqual(theme, "blue")
        let exp = await c.getExperiment("price_test", defaultParams: nil)
        XCTAssertTrue(exp.inExperiment)
        XCTAssertEqual(exp.group, "treatment")

        // REPLACE (not first-wins): a second call wins.
        await configureForTesting(flags: ["new_checkout": false])
        let c2 = try Client([:])
        let off = await c2.getFlag("new_checkout", default: true)
        XCTAssertFalse(off)
    }

    func testPackageOverridesAndClear() async throws {
        await configureForTesting(flags: ["f": true])
        await overrideFlag("f", false)
        await overrideConfig("c", 123)
        await overrideExperiment("e", group: "B", params: ["v": 2])
        let c = try Client(["user_id": "u"])
        let f = await c.getFlag("f", default: true)
        XCTAssertFalse(f)
        let cfg = await c.getConfig("c", default: nil) as? Int
        XCTAssertEqual(cfg, 123)
        let exp = await c.getExperiment("e", defaultParams: nil)
        XCTAssertEqual(exp.group, "B")

        // Test mode has no blob beneath: clearOverrides drops the seed too.
        await clearOverrides()
        let c2 = try Client([:])
        let cleared = await c2.getConfig("c", default: nil)
        XCTAssertNil(cleared)
    }

    func testConfigureForOfflineLayersOverrides() async throws {
        let snapshot: [String: Any] = [
            "flags": [
                "gates": ["on_for_all": ["enabled": true, "rolloutPct": 10000, "salt": "s"]],
                "configs": ["color": ["value": "green"]],
                "killswitches": [:],
            ],
            "experiments": ["experiments": [:], "universes": [:]],
        ]
        try await configureForOffline(snapshot: snapshot)
        let c = try Client(["user_id": "u_1"])
        let on = await c.getFlag("on_for_all", default: false)
        XCTAssertTrue(on)
        let color = await c.getConfig("color", default: nil) as? String
        XCTAssertEqual(color, "green")

        await overrideFlag("on_for_all", false)
        let c2 = try Client([:])
        let off = await c2.getFlag("on_for_all", default: true)
        XCTAssertFalse(off)
        await clearOverrides()
        let c3 = try Client([:])
        let back = await c3.getFlag("on_for_all", default: false)
        XCTAssertTrue(back)
    }

    func testConfigureForOfflineRequiresSource() async {
        do {
            _ = try await configureForOffline()
            XCTFail("expected OfflineSourceError")
        } catch is OfflineSourceError {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
