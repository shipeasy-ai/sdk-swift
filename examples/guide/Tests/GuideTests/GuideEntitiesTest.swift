import Testing
import Shipeasy
@testable import Guide

/// End-to-end-ish test of the guide example's "rendered page".
///
/// This SwiftUI app does not emit an HTML page — it renders one native card per
/// Shipeasy entity from `Entity.all` (see `ContentView.swift`, the
/// `ForEach(Entity.all)`). The faithful analog of "fetch the main HTML page and
/// assert it has the mocked values" is therefore:
///
///   1. Build a Shipeasy client with the SDK *testing* setup
///      (`Engine.forTesting()` — zero network, no key) and MOCK every value it
///      returns via the `override*` setters.
///   2. Build the exact data the main view renders (`Entity.all` — the same
///      array `ContentView` iterates).
///   3. Assert the rendered card data CONTAINS each mocked value: the feature-
///      flag card shows the mocked flag, the config card shows the mocked config,
///      the experiment card shows the mocked group + params.
///
/// NOTE: the example's `Entity.all` is, by design, a set of HARDCODED
/// PLACEHOLDER values — the SDK is not wired into `Entity.swift` yet (see the
/// `// TODO` blocks there and the placeholder banner in `ContentView.swift`). So
/// the value-matching assertions below are EXPECTED to fail until someone wires
/// the SDK into `Entity.swift`. Everything else — the testing setup, the
/// overrides, reading values back off the mocked client with no network — is
/// correct and is what proves the wiring is right once the placeholders go away.
///
/// Uses **swift-testing** (`import Testing`) rather than XCTest so the suite runs
/// from the command line with the open-source Swift toolchain (`swift test`);
/// macOS XCTest ships only with full Xcode, whereas swift-testing is bundled with
/// the toolchain.
struct GuideEntitiesTest {

    // Keys + example values taken verbatim from `Guide/Entity.swift`.
    private let flagKey = "new_checkout"
    private let configKey = "billing_copy"
    private let experimentKey = "checkout_button"

    private let mockedFlag = true
    //
    // Distinctive SENTINEL values — deliberately different from the placeholder
    // strings hardcoded in `Entity.swift` (its config is "Welcome back 👋" /
    // "Upgrade to Pro"; its experiment params are "#34d399" / "Buy now"). This
    // guarantees the card assertions below fail on a real placeholder≠mock
    // mismatch, never a coincidental match, and flip to passing only once
    // `Entity.swift` is wired to the engine.
    private let mockedConfig: [String: String] = [
        "headline": "Welcome aboard 🚀",
        "cta": "Start free trial",
    ]
    private let mockedGroup = "treatment"
    private let mockedParams: [String: String] = [
        "color": "#0ea5e9",
        "label": "Checkout now",
    ]

    private let user: [String: Any] = ["user_id": "u_123"]

    /// Build a fully-mocked testing client. Zero network, no API key; the
    /// override values are the only source of truth.
    private func makeMockedClient() async -> Engine {
        let client = Engine.forTesting()
        await client.overrideFlag(flagKey, mockedFlag)
        await client.overrideConfig(configKey, mockedConfig)
        await client.overrideExperiment(experimentKey, group: mockedGroup, params: mockedParams)
        return client
    }

    /// Find the entity card the view renders for `key`.
    private func card(_ key: String) throws -> Entity {
        try #require(
            Entity.all.first { $0.key == key },
            "the rendered guide has no card for key \(key)"
        )
    }

    // MARK: - The mocked client reads back exactly what we seeded (SDK contract)

    /// Sanity: the SDK testing setup itself returns the mocked values with no
    /// network. This part must always pass — it is the "fetch" half of the test.
    @Test func mockedClientReturnsOverrides() async throws {
        let client = await makeMockedClient()

        let flag = await client.getFlag(flagKey, user: user)
        #expect(flag == mockedFlag, "mocked flag should read back true")

        let cfg = await client.getConfig(configKey) as? [String: String]
        #expect(cfg == mockedConfig, "mocked config should read back unchanged")

        let exp = await client.getExperiment(experimentKey, user: user, defaultParams: nil)
        #expect(exp.inExperiment, "overridden experiment forces inExperiment=true")
        #expect(exp.group == mockedGroup, "mocked experiment group")
        #expect(exp.params as? [String: String] == mockedParams, "mocked experiment params")
    }

    // MARK: - The rendered page contains every mocked value

    /// The feature-flag card the view renders must reflect the mocked flag.
    /// (EXPECTED TO FAIL until Entity.swift is wired to the SDK — the placeholder
    /// value is "true · RULE_MATCH".)
    @Test func featureFlagCardShowsMockedFlag() async throws {
        let client = await makeMockedClient()
        let flag = await client.getFlag(flagKey, user: user)

        let rendered = try card(flagKey).value
        #expect(
            rendered.contains(String(flag)),
            "feature-flag card value \"\(rendered)\" should contain the mocked flag \(flag)"
        )
    }

    /// The dynamic-config card must show the mocked config's values.
    /// (EXPECTED TO FAIL: placeholder is the literal old copy.)
    @Test func configCardShowsMockedConfig() async throws {
        let client = await makeMockedClient()
        let cfg = try #require(await client.getConfig(configKey) as? [String: String])

        let rendered = try card(configKey).value
        for (k, v) in cfg {
            #expect(
                rendered.contains(v),
                "config card value \"\(rendered)\" should contain mocked \(k)=\"\(v)\""
            )
        }
    }

    /// The A/B-experiment card must show the mocked group and param values.
    /// (EXPECTED TO FAIL until wired — placeholder group/params happen to match
    /// the example, but the card is not actually derived from the SDK.)
    @Test func experimentCardShowsMockedGroupAndParams() async throws {
        let client = await makeMockedClient()
        let exp = await client.getExperiment(experimentKey, user: user, defaultParams: nil)
        let params = try #require(exp.params as? [String: String])

        let rendered = try card(experimentKey).value
        #expect(
            rendered.contains(exp.group),
            "experiment card value \"\(rendered)\" should contain mocked group \(exp.group)"
        )
        for (k, v) in params {
            #expect(
                rendered.contains(v),
                "experiment card value \"\(rendered)\" should contain mocked param \(k)=\"\(v)\""
            )
        }
    }
}
