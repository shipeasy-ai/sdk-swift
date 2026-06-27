# Installation

The Swift SDK is distributed via **SwiftPM**. Requires iOS 15+ / macOS 12+.

Add it to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.8.0"),
]
```

…and to your target:

```swift
.target(
    name: "YourServer",
    dependencies: [
        .product(name: "Shipeasy", package: "sdk-swift"),
    ]
)
```

Then import it:

```swift
import Shipeasy
```

## Server-key only

This is a server SDK. Use a **server** key (e.g. from
`ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]`). Never embed the
server key in an iOS app bundle — a future `ShipeasyClient` package will cover
client-key, mobile-friendly use.
