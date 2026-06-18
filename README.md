# Shipeasy (Swift)

Server SDK for [Shipeasy](https://shipeasy.dev). SwiftPM, iOS 15+/macOS 12+.

```swift
dependencies: [
    .package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.1.0"),
]
```

```swift
import Shipeasy

let client = Client(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)
try await client.initialize()

let enabled = await client.getFlag("new_checkout", user: ["user_id": "u_123"])
let cfg = await client.getConfig("billing_copy")
let r = await client.getExperiment("checkout_button", user: ["user_id": "u_123"], defaultParams: ["color": "blue"])
await client.track(userId: "u_123", eventName: "purchase", properties: ["amount": 49])
```

## Anonymous visitors

For logged-out traffic you need a *stable* unit so a fractional rollout buckets
the same on the server and in the browser. `AnonId` provides the cross-SDK
`__se_anon_id` cookie primitives (this SDK is framework-agnostic, so it ships
helpers rather than a middleware). In a server handler, resolve the id off the
request `Cookie` header and echo it back on the response:

```swift
let resolved = AnonId.resolve(cookieHeader: req.headers["cookie"].first)
let on = await client.getFlag("new_checkout", user: ["anonymous_id": resolved.id])
if resolved.minted {
    res.headers.add(name: "set-cookie", value: AnonId.setCookieHeader(resolved.id, secure: true))
}
```

The cookie is non-`HttpOnly` by design so the browser SDK buckets identically; a
request with **no** unit still resolves a fully-rolled (100%) gate as on. Cookie
name + format are a cross-SDK contract — see `18-identity-bucketing.md`.

> Server-key only — never embed in iOS app bundles. A future `ShipeasyClient` package will cover client-key, mobile-friendly use.

## Testing

For unit tests, build a client with `Client.forTesting()`. It does **zero
network**, needs **no API key**, is immediately ready (`initialize()` /
`initializeOnce()` are no-ops), and `track(...)` is a no-op. Seed each entity
with the `override*` setters — an override always wins over live evaluation, so
your tests are deterministic:

```swift
import Shipeasy

let client = Client.forTesting() // no key, no network, ready to use

// Flags
await client.overrideFlag("new_checkout", true)
let enabled = await client.getFlag("new_checkout", user: ["user_id": "u_123"])
// enabled == true

// Dynamic configs
await client.overrideConfig("billing_copy", ["headline": "50% off"])
let cfg = await client.getConfig("billing_copy")
// cfg == ["headline": "50% off"]

// Experiments — forces inExperiment: true with your group + params
await client.overrideExperiment("checkout_button", group: "treatment", params: ["color": "green"])
let r = await client.getExperiment("checkout_button", user: ["user_id": "u_123"], defaultParams: nil)
// r.inExperiment == true, r.group == "treatment", r.params == ["color": "green"]

// track() is a no-op in test mode — safe to call, never sends.
await client.track(userId: "u_123", eventName: "purchase")

// Reset everything back to default evaluation.
await client.clearOverrides()
```

The `override*` setters and `clearOverrides()` also work on a normal,
network-backed `Client` if you want to pin a value at runtime.
