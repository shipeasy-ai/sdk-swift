# Testing

Tests run **hermetically** — no network, no `UserDefaults` — by constructing a
`ShipeasyClient` directly with two injected dependencies:

- an **in-memory `AnonymousStore`** (instead of `UserDefaultsAnonymousStore`), and
- a **stub `ShipeasyClient.Transport`** that returns a canned `/sdk/evaluate` body.

You then `await identify(...)` and assert against the ordinary reads. There is no
`configureClient` in a test — you build the client yourself.

```swift
import XCTest
@testable import Shipeasy

final class FlagTests: XCTestCase {
    /// In-memory AnonymousStore standing in for UserDefaults/Keychain.
    final class MemStore: AnonymousStore, @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: String]
        init(_ seed: [String: String] = [:]) { self.map = seed }
        func get(_ key: String) -> String? { lock.lock(); defer { lock.unlock() }; return map[key] }
        func set(_ key: String, _ value: String) { lock.lock(); defer { lock.unlock() }; map[key] = value }
    }

    /// Transport stub: replies to /sdk/evaluate with a canned assignments body.
    private let stubTransport: ShipeasyClient.Transport = { req in
        let body: [String: Any] = [
            "flags": ["new_ui": true],
            "configs": ["theme": ["accent": "blue"]],
            "experiments": ["exp1": ["inExperiment": true, "group": "treatment", "params": ["copy": "hi"], "universe": "checkout"]],
            "universes": ["checkout": ["defaults": ["copy": "default"]]],
            "killswitches": ["payments": true],
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, resp)
    }

    func testFlagResolvesFromEvaluate() async {
        let client = ShipeasyClient(
            clientKey: "pk_test",
            isNetworkEnabled: true,          // force the network on for the test env
            isTrackingEnabled: false,        // keep the usage telemetry beacon off
            store: MemStore(),
            transport: stubTransport
        )
        await client.identify(["user_id": "u1"])   // evaluate + cache

        let on = await client.getFlag("new_ui", default: false)
        XCTAssertTrue(on)
    }
}
```

## What the injected pieces do

- **`store:`** — a `MemStore` seeded with `[AnonId.cookie: "anon_x"]` pins the
  device id; seeded empty, the client mints one and writes it back (assert on the
  keys your stub recorded). This is how you test that bucketing is stable across
  "launches".
- **`transport:`** — a closure `(URLRequest) async throws -> (Data, HTTPURLResponse)`.
  Branch on `req.url?.path`: return your canned body for `/sdk/evaluate`, and an
  empty `200` for `/collect`. Throw (e.g. `URLError(.notConnectedToInternet)`) to
  test that a failed evaluate is non-fatal and reads fall back to their defaults.
- **`isNetworkEnabled: true`** — the SDK is offline by default outside production
  (see [configuration](configuration.md#environment-derived-egress-defaults)), and
  a test process is not production, so a `/sdk/evaluate` call would never fire.
  Force it on for the client under test — or set `SHIPEASY_ENV=production` for the
  whole test target so every client defaults to on. When you *want* to assert the
  offline default itself, leave it `nil` and keep the env non-production.
- **`isTrackingEnabled: false`** — keeps the usage telemetry beacon off while the
  evaluate/`/collect` network path stays on. If you *do* want to assert on
  telemetry, leave it on and record the requests in the transport instead.

## The `/sdk/evaluate` response shape

The canned body mirrors what the edge returns. Every key is optional (an absent
map is an empty map):

```json
{
  "flags": { "new_ui": true },
  "configs": { "theme": { "accent": "blue" } },
  "experiments": { "exp1": { "inExperiment": true, "group": "treatment", "params": { "copy": "hi" }, "universe": "checkout" } },
  "universes": { "checkout": { "defaults": { "copy": "default" } } },
  "killswitches": { "payments": true }
}
```

Each experiment entry carries its owning `universe`; the top-level `universes` map
holds each universe's `defaults`, which `universe(name).assign().get(field)` falls
back to when the unit isn't enrolled. Before the first `identify`/evaluate, every
read returns the supplied default (`getFlag` → `false`/your default, `getConfig` →
`nil`/your default, `universe(name).assign()` → not enrolled). See the real
patterns in
`Tests/ShipeasyTests/ClientModeTests.swift` and `Tests/ShipeasyTests/SeeTests.swift`.

## Local overrides

Force a flag, config, or experiment to a value at runtime — winning over whatever
`/sdk/evaluate` returned — with the `override*` methods on `ShipeasyClient`. They
are the fastest way to pin a value in a test (no transport stub needed for that
one key), and they back the native devtools overlay, which drives them live so a
forced variant takes effect without a reload. All are `async` (the client is an
`actor`):

```swift
let client = shipeasyClient()!            // or the client you built in a test

await client.overrideFlag("new_ui", true)                    // getFlag → true
await client.overrideConfig("theme", ["accent": "green"])    // getConfig → that value
await client.overrideConfig("theme", nil)                    // force "absent" → your default
await client.overrideExperiment(                             // force a variant…
    "checkout_copy", group: "treatment",
    params: ["headline": "Forced"]                           // …params layer over universe defaults
)

let on = await client.getFlag("new_ui")                      // true, from the override
let a  = await client.universe("checkout").assign()          // enrolled in "treatment", no exposure logged

await client.removeOverride(kind: "flag", name: "new_ui")    // drop one
await client.clearOverrides()                                // drop them all
```

Overrides win over the cached assignment and skip telemetry/exposure — an explicit
in-code decision. `overrideExperiment` requires the experiment to be **known to the
client** (present in the cached assignments) so its owning universe is resolvable;
`overridesSnapshot()` returns the current store (`flags` / `configs` /
`experiments` → forced group) for tooling.

## Resetting global state

If a test path went through `configureClient(...)`, drop the process-global client
between tests with `resetClientConfig()` so the next `configureClient` takes
effect. It exists for tests only.
