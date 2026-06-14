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
