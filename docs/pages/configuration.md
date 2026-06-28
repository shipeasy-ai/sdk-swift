# Configuration

`configure(...)` wires the API key, HTTP, the rules cache, and (optionally) the
background poll. Call it **once** at startup. It is idempotent — the first call
wins; later calls are a no-op. See [installation](installation.md) for the full
options table and per-framework wiring; this page covers the `attributes`
transform and the one-shot-vs-poll choice.

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)
```

The configure params, briefly:

| Param               | Purpose |
| ------------------- | ------- |
| `apiKey`            | Your **server** key. Required. |
| `attributes`        | A transform mapping *your* user object → the Shipeasy attribute map. Default is identity. See below. |
| `baseURL`           | The edge endpoint. Defaults to `https://edge.shipeasy.dev`. |
| `env`               | Deployment env tag (`"prod"` by default); stamped onto `see()` error events. |
| `disableTelemetry`  | Suppress outbound telemetry (`track` / exposures / `see()`). |
| `telemetryURL`      | Where telemetry POSTs go. |
| `privateAttributes` | Attribute names usable for targeting but stripped from outbound `track()` payloads. See [advanced](advanced.md). |
| `stickyStore`       | Optional `StickyBucketStore` to lock units to their first-assigned experiment variant. See [advanced](advanced.md). |
| `init`              | When `true` (default), kick off a one-shot fetch fire-and-forget so the first evaluation resolves against real rules. |
| `poll`              | When `true`, run the initial fetch **and** a periodic background refresh (long-running servers). |

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
that wants the background poll (periodic refresh) instead, pass `poll: true`:

```swift
configure(apiKey: serverKey, poll: true) // initial fetch + periodic background refresh
```

The poll lifecycle is owned internally — you never start, stop, or touch it
yourself. To react to a poll bringing new data, register an `onChange` listener
(see [advanced](advanced.md)). Everything after configuration — flags, configs,
experiments, `track`, `logExposure` — happens through the bound `Client`.

## Environment variables

There are no auto-read env vars — pass the key explicitly. Conventionally it
lives in `SHIPEASY_SERVER_KEY`:

```swift
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"] ?? "")
```
