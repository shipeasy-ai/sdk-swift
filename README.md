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

> Server-key only — never embed in iOS app bundles. A future `ShipeasyClient` package will cover client-key, mobile-friendly use.
