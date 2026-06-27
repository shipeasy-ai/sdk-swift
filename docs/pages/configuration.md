# Configuration

`configure(...)` builds the single package-global `Engine` and returns it. Call
it **once** at startup. It is idempotent — the first call wins; later calls
return the same engine.

```swift
@discardableResult
public func configure(
    apiKey: String,
    attributes: AttributesFn? = nil,
    baseURL: URL = URL(string: "https://edge.shipeasy.dev")!,
    session: URLSession = .shared,
    env: String = "prod",
    disableTelemetry: Bool = false,
    telemetryURL: String = "https://t.shipeasy.ai",
    privateAttributes: [String] = [],
    stickyStore: StickyBucketStore? = nil,
    `init`: Bool = true
) -> Engine
```

| Param               | Purpose |
| ------------------- | ------- |
| `apiKey`            | Your **server** key. Required. |
| `attributes`        | A transform mapping *your* user object → the Shipeasy attribute map. Default is identity. See below. |
| `baseURL`           | The edge endpoint. Defaults to `https://edge.shipeasy.dev`. |
| `env`               | Deployment env tag (`"prod"` by default); stamped onto `see()` error events. |
| `privateAttributes` | Attribute names usable for targeting but stripped from outbound `track()` payloads. See [advanced](advanced.md). |
| `stickyStore`       | Optional `StickyBucketStore` to lock units to their first-assigned experiment variant. See [advanced](advanced.md). |
| `init`              | When `true` (default), kick off a one-shot fetch (`initializeOnce()`) fire-and-forget so `Client(user).getFlag(...)` resolves against real rules without an explicit init. Pass `false` for the long-running poll path (see below). |

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)
```

## The `attributes` transform

`attributes` maps your user object (any shape) to the Shipeasy attribute map
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

## One-shot fetch vs. the background poll

The default (`init: true`) kicks off a single fire-and-forget fetch so the first
`Client` evaluation resolves against real rules. For a **long-running server**
that wants the background poll instead, pass `init: false` and call
`initialize()` on the returned `Engine`:

```swift
let engine = configure(apiKey: serverKey, init: false)
try await engine.initialize() // starts the background poll
await engine.track(userId: "u_123", eventName: "purchase", properties: ["amount": 49])
```

`Engine` is the heavyweight type — keep the returned reference if you need
`track`, `logExposure`, overrides, snapshots, or `see()` directly. Retrieve the
configured engine anywhere via `globalEngine()`.

## Environment variables

There are no auto-read env vars — pass the key explicitly. Conventionally it
lives in `SHIPEASY_SERVER_KEY`:

```swift
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? "")
```
