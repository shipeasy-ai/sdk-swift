# Installation & configuration

The Swift SDK is a **native client** SDK, distributed via **SwiftPM**. It uses a
**public client key** (`pk_…`, safe to embed in a shipped app). Requires
iOS 15+ / macOS 12+ / tvOS 15+ / watchOS 8+.

This page is the canonical home for where and how to call `configureClient()`;
every other page assumes it has already run once at app launch.

---

## Install

Add the package to your `Package.swift` dependencies:

```bash
.package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "1.0.0")
```

### SwiftPM — `Package.swift`

The full dependency + target wiring:

```swift
dependencies: [
    .package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "1.0.0"),
]
```

…and to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Shipeasy", package: "sdk-swift"),
    ]
)
```

### SwiftPM — Xcode (Add Package)

In Xcode: **File ▸ Add Package Dependencies…**, paste
`https://github.com/shipeasy-ai/sdk-swift.git`, choose the **Up to Next Major**
rule from `1.0.0`, and add the `Shipeasy` library product to your app target.

Then import it anywhere:

```swift
import Shipeasy
```

---

## Where to call `configureClient()`

Call `configureClient(clientKey:)` **once**, as early as possible at app launch —
in your SwiftUI `App` initializer, your `@main` entry, or `AppDelegate` /
`SceneDelegate`. It returns the `ShipeasyClient` and registers it as the
process-global one (`shipeasyClient()`). First-config-wins: later calls return
the already-configured client and are a no-op. On first config it fire-and-forgets
an anonymous `identify([:])` so `getFlag` resolves for logged-out users even
before you call `identify` explicitly.

### SwiftUI `App`

```swift
import SwiftUI
import Shipeasy

@main
struct MyApp: App {
    init() {
        configureClient(clientKey: "pk_live_…")
        // Bind the user as soon as you know it (or [:] for a logged-out visitor):
        Task { await shipeasyClient()?.identify(["user_id": "u_123"]) }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### UIKit `AppDelegate`

```swift
import UIKit
import Shipeasy

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureClient(clientKey: "pk_live_…")
        Task { await shipeasyClient()?.identify([:]) }   // logged-out until sign-in
        return true
    }
}
```

Call `identify` again on login (with `user_id` and any targeting attributes), and
`reset()` on logout — see [configuration](configuration.md).

---

## Custom anon-id persistence (`AnonymousStore`)

The persisted device `anonymous_id` is what makes bucketing stable across cold
starts — without it a fresh UUID every launch silently re-buckets every fractional
rollout and experiment. By default it lives in `UserDefaults`
(`UserDefaultsAnonymousStore`).

Supply your own `AnonymousStore` to `configureClient(clientKey:store:)` to back the
id with the **Keychain** (survives reinstalls), an **app-group** container (shared
with extensions), or an **in-memory** map (tests):

```swift
struct KeychainAnonStore: AnonymousStore {
    func get(_ key: String) -> String? { Keychain.read(key) }
    func set(_ key: String, _ value: String) { Keychain.write(key, value) }
}

configureClient(clientKey: "pk_live_…", store: KeychainAnonStore())
```

`get`/`set` are synchronous and best-effort — a throwing or slow backing store
degrades gracefully and never crashes a read. See
[advanced](advanced.md#anonymous-id-persistence-anonymousstore) for the full detail.

---

## Next

Head to [configuration](configuration.md) for every `configureClient` option, or
straight to [flags](flags.md) / [experiments](experiments.md) to start reading.
