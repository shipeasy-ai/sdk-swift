# Installation & configuration

The Swift SDK is distributed via **SwiftPM**. Requires iOS 15+ / macOS 12+.
This is a **server** SDK — use a server key, never embed it in an iOS app
bundle.

This page is the canonical home for `configure()`. Pick your framework below for
the install + where to call `configure()`; every other page assumes
`configure()` has already run once at startup.

---

## Install

Add the package to your `Package.swift` dependencies:

```bash
.package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.10.0")
```

### SwiftPM — `Package.swift`

The full dependency + target wiring:

```swift
dependencies: [
    .package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.10.0"),
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
rule from `0.10.0`, and add the `Shipeasy` library product to your target.

Then import it anywhere:

```swift
import Shipeasy
```

---

## Configure (`configure()`)

`configure(...)` wires the API key, HTTP, the rules cache, and (optionally) the
background poll. Call it **exactly once** at startup, before any `Client` is
constructed. It is idempotent — the first call wins; later calls are a no-op.
Constructing a `Client` before `configure(...)` throws `NotConfiguredError`.

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

// then, per request/user:
let client = try Client(["user_id": "u_123"])
let on = await client.getFlag("new_checkout")
```

### `configure()` options

| Param               | Default | Purpose |
| ------------------- | ------- | ------- |
| `apiKey`            | —       | Your **server** key. Required. Pass it explicitly — there are no auto-read env vars. |
| `attributes`        | identity | A transform mapping *your* user object → the Shipeasy attribute map. Runs once, in the `Client` constructor. See below. |
| `baseURL`           | `https://edge.shipeasy.dev` | The edge endpoint. |
| `env`               | `"prod"` | Deployment env tag; stamped onto `see()` error events. |
| `disableTelemetry`  | `false` | Suppress outbound telemetry (`track` / exposures / `see()`). |
| `telemetryURL`      | `https://t.shipeasy.ai` | Where telemetry POSTs go. |
| `privateAttributes` | `[]`    | Attribute names usable for targeting but stripped from outbound `track()` payloads. See [advanced](advanced.md). |
| `stickyStore`       | `nil`   | Optional `StickyBucketStore` to lock units to their first-assigned experiment variant. See [advanced](advanced.md). |
| `init`              | `true`  | `true`: kick off a one-shot fetch fire-and-forget so the first evaluation resolves against real rules. Pass `false` when you set `poll: true`. |
| `poll`              | `false` | `true`: run the initial fetch **and** a periodic background refresh (long-running servers). The poll lifecycle is owned internally — you never start it yourself. |

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
that wants the background poll (periodic refresh) instead, pass `poll: true`:

```swift
configure(apiKey: serverKey, poll: true) // initial fetch + periodic background refresh
```

The poll lifecycle is owned internally — you never start, stop, or touch it
yourself. To react to a poll bringing new data, register an `onChange` listener
(see [advanced](advanced.md)).

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
        apiKey: Environment.get("SHIPEASY_SERVER_KEY") ?? "",
        poll: true
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
        apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? "",
        poll: true
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
top of `main`, then construct a `Client` wherever you evaluate. A short-lived
process can keep the default `init: true` (one-shot fetch); a long-running one
should pass `poll: true`:

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
