import XCTest
@testable import Shipeasy

/// configure(...) + the user-bound Client. Each test resets the package-global
/// config first so configure()'s first-config-wins idempotency does not leak
/// across tests.
final class BoundClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetGlobalConfig()
    }

    override func tearDown() {
        resetGlobalConfig()
        super.tearDown()
    }

    // configure({apiKey}) then Client(user).getFlag(...) resolves against the
    // global engine. `init: false` avoids the fire-and-forget network fetch; we
    // seed the engine directly via the test seam.
    func testConfigureThenBoundClientReadsFlag() async throws {
        let engine = configure(apiKey: "srv_key", env: "prod", disableTelemetry: true, init: false)
        // Seed a fully-rolled gate and mark the engine ready (no network).
        await engine.applyData(
            flags: ["gates": ["new_checkout": ["enabled": true, "rolloutPct": 10000, "salt": "s"]]],
            experiments: nil,
            fireChange: false,
            markReady: true
        )

        let client = try Client(["user_id": "u_123"])
        let on = await client.getFlag("new_checkout")
        XCTAssertTrue(on)

        // Default form: returns the default only when unevaluable.
        let missing = await client.getFlag("nope", default: true)
        XCTAssertTrue(missing)
    }

    // The configured attributes transform maps a raw user object to the
    // attribute map, and that mapped map is what reaches evaluation. The gate
    // targets country == "US"; the raw user has no `country`, only a `nation`
    // field the transform renames.
    func testAttributesTransformIsApplied() async throws {
        struct RawUser { let id: String; let nation: String }

        let engine = configure(
            apiKey: "srv_key",
            attributes: { user in
                let u = user as! RawUser
                return ["user_id": u.id, "country": u.nation]
            },
            disableTelemetry: true,
            init: false
        )
        await engine.applyData(
            flags: ["gates": [
                "us_only": [
                    "enabled": true, "rolloutPct": 10000, "salt": "s",
                    "rules": [["attr": "country", "op": "eq", "value": "US"]],
                ]
            ]],
            experiments: nil,
            fireChange: false,
            markReady: true
        )

        // The transform binds country=US → rule matches.
        let usClient = try Client(RawUser(id: "u1", nation: "US"))
        XCTAssertEqual(usClient.attributes["country"] as? String, "US")
        XCTAssertEqual(usClient.attributes["user_id"] as? String, "u1")
        let onForUS = await usClient.getFlag("us_only")
        XCTAssertTrue(onForUS)

        // A non-US user buckets the same engine but fails the rule.
        let caClient = try Client(RawUser(id: "u2", nation: "CA"))
        let onForCA = await caClient.getFlag("us_only")
        XCTAssertFalse(onForCA)
    }

    // Default (identity) transform: the user object IS the attribute map.
    func testIdentityTransformByDefault() async throws {
        _ = configure(apiKey: "srv_key", disableTelemetry: true, init: false)
        let client = try Client(["user_id": "u1", "plan": "pro"])
        XCTAssertEqual(client.attributes["plan"] as? String, "pro")
    }

    // Constructing a Client before configure() fails loudly.
    func testClientBeforeConfigureThrows() {
        resetGlobalConfig()
        XCTAssertThrowsError(try Client(["user_id": "u1"])) { error in
            XCTAssertTrue(error is NotConfiguredError)
        }
    }

    // First-config-wins: a second configure() returns the same engine and does
    // NOT replace the transform.
    func testConfigureIsFirstWins() async throws {
        let first = configure(apiKey: "key_a", attributes: { _ in ["user_id": "from_a"] }, init: false)
        let second = configure(apiKey: "key_b", attributes: { _ in ["user_id": "from_b"] }, init: false)
        XCTAssertTrue(first === second)

        // The first transform is the one that stuck.
        let client = try Client("ignored")
        XCTAssertEqual(client.attributes["user_id"] as? String, "from_a")
    }

    // The bound Client forwards getConfig / getExperiment / getKillswitch to the
    // engine with the bound attrs (configs/killswitches are not user-scoped).
    func testBoundClientForwardsConfigExperimentKillswitch() async throws {
        let engine = configure(apiKey: "srv_key", disableTelemetry: true, init: false)
        await engine.applyData(
            flags: [
                "configs": ["copy": ["value": ["headline": "Hi"]]],
                "killswitches": ["panic": ["value": true]],
            ],
            experiments: [
                "experiments": [
                    "price_test": [
                        "status": "running", "salt": "s", "allocationPct": 10000,
                        "groups": [["name": "treatment", "weight": 10000, "params": ["price": 9]]],
                    ]
                ]
            ],
            fireChange: false,
            markReady: true
        )

        let client = try Client(["user_id": "u1"])

        let cfg = await client.getConfig("copy") as? [String: String]
        XCTAssertEqual(cfg?["headline"], "Hi")

        let exp = await client.getExperiment("price_test", defaultParams: nil)
        XCTAssertTrue(exp.inExperiment)
        XCTAssertEqual(exp.group, "treatment")

        let killed = await client.getKillswitch("panic")
        XCTAssertTrue(killed)
        let absent = await client.getKillswitch("nope")
        XCTAssertFalse(absent)
    }
}
