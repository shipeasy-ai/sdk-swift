# Overview

`Shipeasy` is the **server-side** Swift SDK for [Shipeasy](https://shipeasy.dev) —
feature flags, dynamic configs, kill switches, and A/B experiments. SwiftPM,
iOS 15+ / macOS 12+. It is server-key only; never embed the server key in an iOS
app bundle.

## Mental model: `configure()` once, then a `Client` per user

You `configure(apiKey:)` the package-global engine **once** at startup, then
construct a cheap, **user-bound** `Client` per request. The bound `Client`'s
methods take **no user argument** — the user is bound at construction:

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

let client = try Client(["user_id": "u_123", "plan": "pro"])
let enabled = await client.getFlag("new_checkout")
```

Every evaluation method on the bound `Client` is `async` (the underlying engine
is a Swift `actor`). Constructing a `Client` before `configure(...)` throws
`NotConfiguredError`.

## Engine vs Client

| Type     | Role |
| -------- | ---- |
| `Engine` | The heavyweight `actor`. Owns the API key, HTTP, the blob cache, and the poll timer. Exposes the full low-level surface: `getFlag(_:user:)`, `getConfig`, `getExperiment(_:user:defaultParams:)`, `getKillswitch`, `track`, `logExposure`, `evaluate`, the `override*` setters, snapshots, and `see()`. There is one global engine, built by `configure(...)`. |
| `Client` | A cheap, **user-bound** value over the global engine. Owns no connection, cache, or poll timer — it runs the configured `attributes` transform once at construction and delegates every evaluation to the engine. Build one per user/request. |

Most application code uses `Client`. Reach for the `Engine` directly when you
need the low-level surface (background polling, `track`, overrides, SSR, `see()`).

## Pages

- [installation](installation.md) — SwiftPM dependency, runtime, import.
- [configuration](configuration.md) — `configure(...)`, the `attributes` transform, init/poll vs one-shot, the `Engine` return.
- [flags](flags.md) — `getFlag` (bound + Engine forms), defaults, `getFlagDetail`.
- [configs](configs.md) — `getConfig`, defaults.
- [killswitches](killswitches.md) — `getKillswitch` + named override switches.
- [experiments](experiments.md) — `getExperiment`, `ExperimentResult`, `track`.
- [i18n](i18n.md) — SSR loader/bootstrap tags (translation rendering is client-side).
- [error-reporting](error-reporting.md) — `see()` structured error reporting.
- [testing](testing.md) — `Engine.forTesting()`, `override*`, snapshots.
- [openfeature](openfeature.md) — provider status (not shipped).
- [advanced](advanced.md) — private attributes, `bucketBy`, sticky bucketing, anonymous IDs.
