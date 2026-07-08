---
name: shipeasy-swift
description: Use Shipeasy from a native iOS/macOS/tvOS/watchOS app in Swift — feature flags, dynamic configs, kill switches, A/B experiments, metric tracking, and see() error reporting. The native client SDK uses a public client key (pk_…, safe to embed), configureClient() once at launch returns a ShipeasyClient actor, identify() binds the device user and refreshes assignments, getFlag/getConfig/getKillswitch serve cached reads, and universe(name).assign() returns an experiment Assignment. Persists the device anonymous_id across launches so bucketing is stable. SwiftPM (iOS 15+/macOS 12+/tvOS 15+/watchOS 8+).
---

# Shipeasy Swift SDK (native client)

SwiftPM SDK for **shipped iOS / macOS / tvOS / watchOS apps** (iOS 15+ / macOS 12+
/ tvOS 15+ / watchOS 8+). It uses a **public client key** (`pk_…`, safe to embed),
evaluates the device user server-side over `POST /sdk/evaluate`, and serves cheap
local reads from the cached response. `ShipeasyClient` is a Swift `actor`, so its
methods are `async`. There is **no server surface, no OpenFeature provider, and no
i18n** in this SDK.

> The documented surface is exactly **`configureClient(clientKey:)`** (once, at
> launch) and the **`ShipeasyClient`** it returns, plus the package-level `see()`
> family. For deeper docs, fetch any page/snippet from the manifest at
> <https://shipeasy-ai.github.io/sdk-swift/manifest.json> (raw URLs below).

## Install

```swift
// Package.swift
.package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "1.0.0"),
```

```swift
import Shipeasy
```

## Configure once at launch, then identify + read

```swift
import Shipeasy

// Once at app launch (SwiftUI App init / AppDelegate). PUBLIC client key (pk_…),
// safe to embed. First-config-wins; returns + registers the process-global client.
let client = configureClient(clientKey: "pk_live_…")

// Bind the user ([:] for a logged-out visitor; again on login). Attaches the
// persisted device anonymous_id automatically so bucketing is stable across
// cold starts. Awaiting the first identify guarantees the first reads see assignments.
await client.identify(["user_id": "u_123", "plan": "pro"])

// Anywhere later, fetch the configured client with shipeasyClient():
let on = await shipeasyClient()?.getFlag("new_checkout") ?? false
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/installation.md> ·
<https://shipeasy-ai.github.io/sdk-swift/pages/configuration.md>

## Evaluate (cached reads)

```swift
let client = shipeasyClient()!
let enabled = await client.getFlag("new_checkout")                 // Bool
let on      = await client.getFlag("new_checkout", default: true)  // default only when unevaluable
let cfg     = await client.getConfig("billing_copy", default: ["headline": "Hi"]) // Any?
let killed  = await client.getKillswitch("panic_button")           // true = killed
// Named switch: getKillswitch(name, switchKey:) — an unconfigured key falls back
// to the kill switch's top-level value.
```

Reads serve the cached `/sdk/evaluate` response (no per-call network, any thread).
Before the first identify they return the supplied defaults. Reference:
<https://shipeasy-ai.github.io/sdk-swift/pages/flags.md>

## Identity lifecycle

```swift
await client.identify(["user_id": "u_123"])   // launch / login / attrs changed
await client.reset()                          // logout: keep device anon id, drop user_id
await client.refreshAssignments()             // re-evaluate current user (pick up a new flag)
let id = await client.anonymousId             // stable, persisted device bucketing id
```

## Experiments + track

```swift
let client = shipeasyClient()!
// A universe is a mutual-exclusion pool → the unit lands in ≤1 experiment.
let a = await client.universe("checkout").assign()            // auto-logs one exposure when enrolled
// a.name: String?, a.group: String?, a.enrolled: Bool
let color = a.get("button_color", "blue")                    // variant override ?? universe default ?? fallback
await client.track("purchase", properties: ["amount": 49])    // conversion (fire-and-forget)
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/experiments.md> · track
snippet <https://shipeasy-ai.github.io/sdk-swift/snippets/metrics/track.md>

## Testing (hermetic — no network, no UserDefaults)

Build a `ShipeasyClient` directly with an in-memory `AnonymousStore` + a stub
`Transport` returning a canned `/sdk/evaluate` body; `await identify`, then assert.

```swift
final class MemStore: AnonymousStore, @unchecked Sendable {
    private var map: [String: String] = [:]
    func get(_ key: String) -> String? { map[key] }
    func set(_ key: String, _ value: String) { map[key] = value }
}

let transport: ShipeasyClient.Transport = { req in
    let body: [String: Any] = ["flags": ["new_ui": true]]
    let data = try JSONSerialization.data(withJSONObject: body)
    return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}

// isNetworkEnabled: true forces the network on (the SDK is offline by default
// outside production); isTrackingEnabled: false keeps the telemetry beacon off.
let client = ShipeasyClient(clientKey: "pk_test", isNetworkEnabled: true,
                            isTrackingEnabled: false, store: MemStore(), transport: transport)
await client.identify(["user_id": "u1"])
_ = await client.getFlag("new_ui", default: false)   // true
// resetClientConfig() drops the process-global client between tests (tests only).
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/testing.md>

## Error reporting — see()

```swift
do {
    try chargeCard(order)
} catch {
    see(error).causesThe("checkout").to("use cached prices")
}

seeViolation("large query").causesThe("search results").to("be trimmed")
controlFlowException(error).because("expected — token expiry is normal") // reports nothing
```

`to(_:)` is the terminal (nothing sends without it). Package-level `see(_:)` /
`seeViolation(_:)` dispatch through the configured client (side `"client"`).
Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/error-reporting.md> ·
snippet <https://shipeasy-ai.github.io/sdk-swift/snippets/ops/see.md>

## Notes

- **No OpenFeature provider** in Swift — use `getFlag`. Reference:
  <https://shipeasy-ai.github.io/sdk-swift/pages/openfeature.md>
- **No i18n** in the native client — localize with the platform's own tooling
  (String Catalogs / `Localizable.strings`). Reference:
  <https://shipeasy-ai.github.io/sdk-swift/pages/i18n.md>
- **Persisted anon id** is the point of the SDK: a custom `AnonymousStore` (Keychain
  / app-group / tests) backs it via `configureClient(clientKey:store:)`; also
  `privateAttributes` (stripped from `track`/`see`), `refreshAssignments`,
  `anonymousId`. Reference:
  <https://shipeasy-ai.github.io/sdk-swift/pages/advanced.md>
