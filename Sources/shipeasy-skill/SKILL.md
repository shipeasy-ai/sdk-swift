---
name: shipeasy-swift
description: Use Shipeasy (feature flags, configs, kill switches, A/B experiments, i18n) from Swift. Covers configure() + Client(user), getFlag/getConfig/getExperiment/getKillswitch, track, testing, see() error reporting. Server-side SwiftPM SDK (iOS 15+/macOS 12+).
---

# Shipeasy Swift SDK

Server-side SDK (SwiftPM, iOS 15+/macOS 12+). Server-key only — never embed in a
shipped app bundle. All evaluation methods are `async` (the engine is a Swift
`actor`).

> The documented surface is exactly **`configure()`** (setup) and the bound
> **`Client(user)`** (use), plus the package-level helpers below. For deeper docs,
> fetch any page/snippet from the manifest at
> <https://shipeasy-ai.github.io/sdk-swift/manifest.json> (raw URLs below).

## Install

```swift
// Package.swift
.package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.10.0"),
```

```swift
import Shipeasy
```

## Configure once, then a Client per user

```swift
// Once at startup. Builds the global engine + kicks off a one-shot fetch.
// Optionally map YOUR user object → the attribute map (runs in the Client ctor).
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!) { user in
    let u = user as! AppUser
    return ["user_id": u.id, "country": u.region]
}
// Long-running server: configure(apiKey: key, poll: true) keeps flags fresh with
// a background poll — you never call initialize() yourself.

// Per request — methods take NO user arg (the user is bound). Throws
// NotConfiguredError if configure() hasn't run.
let client = try Client(["user_id": "u_123", "plan": "pro"]) // construct once per callsite
```

## Evaluate

```swift
let client = try Client(["user_id": "u_123"])                 // construct once per callsite
let enabled = await client.getFlag("new_checkout")             // Bool
let on      = await client.getFlag("new_checkout", default: true) // default only when unevaluable
let detail  = await client.getFlagDetail("new_checkout")       // .value + .reason
let cfg      = await client.getConfig("billing_copy", default: ["headline": "Hi"]) // Any?
let killed  = await client.getKillswitch("panic_button")       // true = killed
// Named switch: getKillswitch(name, switchKey:) — an unconfigured key falls back
// to the kill switch's top-level value.
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/configuration.md> ·
<https://shipeasy-ai.github.io/sdk-swift/pages/flags.md>

## Experiments + track (Client-only, end to end)

```swift
let client = try Client(["user_id": "u_123"])                 // construct once per callsite
let r = await client.getExperiment("checkout_button", defaultParams: ["color": "blue"])
// r.inExperiment: Bool, r.group: String, r.params: Any?

await client.logExposure("checkout_button")                   // record where you present it
await client.track("purchase", properties: ["amount": 49])    // conversion for the bound user
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/experiments.md> · track
snippet <https://shipeasy-ai.github.io/sdk-swift/snippets/metrics/track.md>

## Testing (no network, no key)

```swift
// Seed values up front; reads go through the ordinary Client(user). Replaces
// prior config, so each test can reconfigure freely.
await configureForTesting(
    flags: ["new_checkout": true],
    configs: ["billing_copy": ["headline": "50% off"]],
    experiments: ["checkout_button": (group: "treatment", params: ["color": "green"])]
)
let client = try Client(["user_id": "u_1"])
_ = await client.getFlag("new_checkout", default: false)      // true

await overrideFlag("new_checkout", false)                     // flip on the spot
await clearOverrides()                                        // drop every override (incl. the seed)

// Offline: evaluate the REAL rules from a snapshot or JSON file, no network.
try await configureForOffline(path: "shipeasy-snapshot.json")
```

Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/testing.md>

## Error reporting — see()

```swift
do {
    try chargeCard(order)
} catch {
    see(error).causesThe("checkout").to("use the backup processor")
}

seeViolation("inventory_negative").extras(["sku": sku]).to("clamp to zero")
controlFlowException(error).because("expected — token expiry is normal") // reports nothing
```

Package-level `see(_:)` / `seeViolation(_:)` use the configured engine. Reference:
<https://shipeasy-ai.github.io/sdk-swift/pages/error-reporting.md> · snippet
<https://shipeasy-ai.github.io/sdk-swift/snippets/ops/see.md>

## Notes

- **No OpenFeature provider** in Swift — use `getFlag` / `getFlagDetail`.
  Reference: <https://shipeasy-ai.github.io/sdk-swift/pages/openfeature.md>
- **i18n**: the server SDK has no `t()`. It emits SSR tags via package-level
  `bootstrapScriptTag(_:...)` / `i18nScriptTag(_:profile:)`; the browser client
  SDK renders translations. Reference:
  <https://shipeasy-ai.github.io/sdk-swift/pages/i18n.md>
- Advanced: `privateAttributes`, `bucketBy`, sticky bucketing
  (`StickyBucketStore`), `AnonId` helpers, package-level `onChange` (requires
  `poll: true`), `logExposure`. Reference:
  <https://shipeasy-ai.github.io/sdk-swift/pages/advanced.md>
