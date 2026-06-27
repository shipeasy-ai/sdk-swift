---
name: shipeasy-swift
description: Use Shipeasy (feature flags, configs, kill switches, A/B experiments, i18n) from Swift. Covers configure() + Client(user), getFlag/getConfig/getExperiment/getKillswitch, track, testing, see() error reporting. Server-side SwiftPM SDK (iOS 15+/macOS 12+).
---

# Shipeasy Swift SDK

Server-side SDK (SwiftPM, iOS 15+/macOS 12+). Server-key only — never embed in an
iOS app bundle. All evaluation methods are `async` (the engine is a Swift `actor`).

## Install

```swift
// Package.swift
.package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.8.0"),
```

```swift
import Shipeasy
```

## Configure once, then a Client per user

```swift
// Once at startup. Builds the global Engine + kicks off a one-shot fetch.
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

// Optionally map YOUR user object → the attribute map (runs in the Client ctor):
configure(apiKey: serverKey) { user in
    let u = user as! AppUser
    return ["user_id": u.id, "country": u.region]
}

// Per request — methods take NO user arg (the user is bound). Throws
// NotConfiguredError if configure() hasn't run.
let client = try Client(["user_id": "u_123", "plan": "pro"])
```

## Evaluate

```swift
let enabled = await client.getFlag("new_checkout")             // Bool
let on      = await client.getFlag("new_checkout", default: true) // default only when unevaluable
let detail  = await client.getFlagDetail("new_checkout")       // .value + .reason
let cfg     = await client.getConfig("billing_copy", default: ["headline": "Hi"]) // Any?
let killed  = await client.getKillswitch("panic_button")       // true = killed
```

## Experiment + track

```swift
let r = await client.getExperiment("checkout_button", defaultParams: ["color": "blue"])
// r.inExperiment: Bool, r.group: String, r.params: Any?
if r.inExperiment, r.group == "treatment" { /* … */ }

// track() lives on the Engine:
await globalEngine()!.track(userId: "u_123", eventName: "purchase", properties: ["amount": 49])
```

## Long-running server (background poll)

```swift
let engine = configure(apiKey: serverKey, init: false)
try await engine.initialize() // start the poll
```

## Testing

```swift
let client = Engine.forTesting() // no key, no network, instantly ready
await client.overrideFlag("new_checkout", true)
await client.overrideConfig("billing_copy", ["headline": "50% off"])
await client.overrideExperiment("checkout_button", group: "treatment", params: ["color": "green"])
let enabled = await client.getFlag("new_checkout", user: ["user_id": "u_123"]) // true
await client.clearOverrides()

// Offline snapshot from a real /sdk/flags + /sdk/experiments dump:
let snap = try Engine.fromFile("/path/to/snapshot.json")
```

## Error reporting — see()

```swift
do {
    try chargeCard(order)
} catch {
    client.see(error).causesThe("checkout").to("use the backup processor")
}

client.seeViolation("inventory_negative").extras(["sku": sku]).to("clamp to zero")
controlFlowException(error).because("expected — token expiry is normal") // reports nothing
```

Package-level `see(_:)` / `seeViolation(_:)` use the last-constructed engine.

## Notes

- **No OpenFeature provider** — use `getFlag` / `getFlagDetail`.
- **i18n**: server SDK has no `t()`. It emits SSR tags
  (`bootstrapScriptTag`, `i18nScriptTag(clientKey, profile:)`); the browser
  client SDK renders translations.
- Advanced: `privateAttributes`, `bucketBy`, sticky bucketing
  (`StickyBucketStore`), `AnonId` cookie helpers, `onChange` listeners,
  `logExposure`.
