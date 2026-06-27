# Installation & configuration

The Swift SDK is distributed via **SwiftPM**. Requires iOS 15+ / macOS 12+.
This is a **server** SDK — use a server key, never embed it in an iOS app
bundle.

This page is the canonical home for `configure()`. Pick your framework below for
the install + where to call `configure()`; every other page assumes
`configure()` has already run once at startup.

---

## Install

### SwiftPM — `Package.swift`

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

### SwiftPM — Xcode (Add Package)

In Xcode: **File ▸ Add Package Dependencies…**, paste
`https://github.com/shipeasy-ai/sdk-swift.git`, choose the **Up to Next Major**
rule from `0.8.0`, and add the `Shipeasy` library product to your target.

Then import it anywhere:

```swift
import Shipeasy
```

---

## Configure (`configure()`)

`configure(...)` builds the single package-global `Engine` and returns it. Call
it **exactly once** at startup, before any `Client` is constructed. It is
idempotent — the first call wins; later calls return the same engine.
Constructing a `Client` before `configure(...)` throws `NotConfiguredError`.

```swift
@discardableResult
public func configure(
    apiKey: String,                       // your SERVER key (required)
    attributes: AttributesFn? = nil,      // your user object -> attribute map (default: identity)
    baseURL: URL = URL(string: "https://edge.shipeasy.dev")!,
    session: URLSession = .shared,
    env: String = "prod",                 // env tag stamped on see() events
    disableTelemetry: Bool = false,
    telemetryURL: String = "https://t.shipeasy.ai",
    privateAttributes: [String] = [],     // targeting-only attrs stripped from track() payloads
    stickyStore: StickyBucketStore? = nil,// lock units to first-assigned variant
    `init`: Bool = true                   // true: fire-and-forget one-shot fetch; false: long-running poll
) -> Engine
```

| Param               | Purpose |
| ------------------- | ------- |
| `apiKey`            | Your **server** key. Required. Pass it explicitly — there are no auto-read env vars. |
| `attributes`        | A transform mapping *your* user object → the Shipeasy attribute map. Runs once, in the `Client` constructor. Default is identity. |
| `baseURL`           | The edge endpoint. Defaults to `https://edge.shipeasy.dev`. |
| `env`               | Deployment env tag (`"prod"` by default); stamped onto `see()` error events. |
| `privateAttributes` | Attribute names usable for targeting but stripped from outbound `track()` payloads. |
| `stickyStore`       | Optional `StickyBucketStore` to lock units to their first-assigned experiment variant. |
| `init`              | `true` (default): kick off a one-shot fetch fire-and-forget so the first `Client` evaluation resolves against real rules. `false`: long-running poll — call `initialize()` on the returned `Engine` yourself. |

### Identity: the `attributes` transform

`attributes` maps your user object (any shape) → the Shipeasy attribute map
(`["user_id": ..., "anonymous_id": ..., <targeting attrs>]`). It runs **once**,
in the `Client` constructor. The default is identity — the user value is assumed
to already BE the attribute map.

```swift
struct AppUser { let id: String; let region: String }

configure(apiKey: serverKey) { user in
    let u = user as! AppUser
    return ["user_id": u.id, "country": u.region]
}

let on = await (try Client(AppUser(id: "u_123", region: "US"))).getFlag("us_only")
```

### Environment variables

There are no auto-read env vars — pass the key explicitly. Conventionally it
lives in `SHIPEASY_SERVER_KEY`:

```swift
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? "")
```

### One-shot fetch vs. the background poll

The default (`init: true`) kicks off a single fire-and-forget fetch so the first
`Client` evaluation resolves against real rules. For a **long-running server**
that wants the background poll instead, pass `init: false` and call
`initialize()` on the returned `Engine`:

```swift
let engine = configure(apiKey: serverKey, init: false)
try await engine.initialize() // starts the background poll
```

`Engine` is the heavyweight type — keep the returned reference if you need
`track`, `logExposure`, overrides, snapshots, or `see()` directly. Retrieve the
configured engine anywhere via `globalEngine()`.

---

## Framework wiring

`configure()` is called **once** at process startup; after that you construct a
cheap, user-bound `Client` per request.

### Vapor

Call `configure()` in `configure(_ app:)` (Vapor's boot hook). Construct a
`Client` per request inside route handlers (handlers are already `async`):

```swift
// configure.swift
import Vapor
import Shipeasy

public func configure(_ app: Application) throws {
    Shipeasy.configure(
        apiKey: Environment.get("SHIPEASY_SERVER_KEY") ?? ""
    ) { user in
        let req = user as! Request
        return ["user_id": req.headers.first(name: "x-user-id") ?? "anon"]
    }

    try routes(app)
}

// routes.swift
func routes(_ app: Application) throws {
    app.get("checkout") { req async throws -> String in
        // construct once per request (cheap; binds the user)
        let client = try Shipeasy.Client(req)
        return await client.getFlag("new_checkout") ? "new" : "old"
    }
}
```

For anonymous (logged-out) traffic, resolve the cross-SDK `__se_anon_id` cookie
off the request and echo it back so the browser SDK buckets identically:

```swift
app.get("home") { req async throws -> Response in
    let resolved = AnonId.resolve(cookieHeader: req.headers.first(name: "cookie"))
    let client = try Shipeasy.Client(["anonymous_id": resolved.id])
    let on = await client.getFlag("new_home")

    let res = Response(body: .init(string: on ? "new" : "old"))
    if resolved.minted {
        res.headers.add(name: "set-cookie", value: AnonId.setCookieHeader(resolved.id, secure: true))
    }
    return res
}
```

### Hummingbird

Call `configure()` once when you build the application/router, then construct a
`Client` per request in handlers:

```swift
import Hummingbird
import Shipeasy

func buildApplication() -> some ApplicationProtocol {
    Shipeasy.configure(
        apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? ""
    )

    let router = Router()
    router.get("checkout") { request, _ -> String in
        // construct once per request (cheap; binds the user)
        let userId = request.headers[.init("x-user-id")!] ?? "anon"
        let client = try Shipeasy.Client(["user_id": userId])
        return await client.getFlag("new_checkout") ? "new" : "old"
    }
    return Application(router: router)
}
```

### Plain Swift (`main`)

For a CLI, daemon, or any non-framework process, call `configure()` once at the
top of `main`, then construct a `Client` wherever you evaluate:

```swift
import Shipeasy

@main
struct Server {
    static func main() async throws {
        configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? "")

        // construct once per callsite (cheap; binds the user)
        let client = try Client(["user_id": "u_123"])
        let enabled = await client.getFlag("new_checkout")
        print("new_checkout = \(enabled)")
    }
}
```

---

## Server-key only

Use a **server** key (e.g. from
`ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]`). Never embed the
server key in an iOS app bundle — a future `ShipeasyClient` package will cover
client-key, mobile-friendly use.
