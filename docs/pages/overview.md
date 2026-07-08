# Overview

`Shipeasy` is the **server-side** Swift SDK for [Shipeasy](https://shipeasy.dev) —
feature flags, dynamic configs, kill switches, and A/B experiments. SwiftPM,
iOS 15+ / macOS 12+. It is server-key only; never embed the server key in an iOS
app bundle.

## Mental model: `configure()` once, then a `Client` per user

You `configure(apiKey:)` **once** at startup, then construct a cheap,
**user-bound** `Client` per request. The bound `Client`'s methods take **no user
argument** — the user is bound at construction:

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

let client = try Client(["user_id": "u_123", "plan": "pro"])
let enabled = await client.getFlag("new_checkout")
```

Every evaluation method on the bound `Client` is `async` (the SDK is backed by a
Swift `actor`). Constructing a `Client` before `configure(...)` throws
`NotConfiguredError`.

## The two things you use

| Function / type       | Role |
| --------------------- | ---- |
| `configure(...)`      | Called **once** at startup. Wires the API key, HTTP, the rules cache, and (optionally) the background poll. Siblings `configureForTesting(...)` and `configureForOffline(...)` wire the same surface with no network. See [installation](installation.md). |
| `try Client(_ user:)` | A cheap, **user-bound** value. Runs the configured `attributes` transform once at construction and binds the result. Build one per user/request. Exposes `getFlag`, `getFlagDetail`, `getConfig`, `getExperiment`, `getKillswitch`, plus `track(_:properties:)` and `logExposure(_:)` (the unit is derived from the bound user), so experiments are end-to-end Client-only. |

Everything application code needs lives on the bound `Client` — including
recording conversions via `client.track(...)` and exposures via
`client.logExposure(...)`. The package-level helpers (`overrideFlag`,
`clearOverrides`, `onChange`, `bootstrapScriptTag`, `i18nScriptTag`) cover the
remaining cross-cutting needs.

## Shipping in a mobile app? Use `ShipeasyClient`

`configure()` / `Client(user)` is the **server** SDK — it holds a server key and
evaluates rules locally. **Never embed a server key in a shipped app.** For an
iOS / macOS / tvOS / watchOS app, use `configureClient(clientKey:)` +
`ShipeasyClient`: a **public client key**, server-side evaluation over
`POST /sdk/evaluate`, and a **persisted device `anonymous_id`** so logged-out
users bucket identically across launches. See [installation](installation.md#native-mobile-client--shipped-apps-shipeasyclient).

## Pages

- [installation](installation.md) — SwiftPM dependency, runtime, import, and the canonical `configure()` reference.
- [configuration](configuration.md) — `configure(...)`, the `attributes` transform, one-shot fetch vs. background poll.
- [flags](flags.md) — `getFlag`, defaults, `getFlagDetail`.
- [configs](configs.md) — `getConfig`, defaults.
- [killswitches](killswitches.md) — `getKillswitch` + named override switches.
- [experiments](experiments.md) — `getExperiment`, `ExperimentResult`, `track`, `logExposure`.
- [i18n](i18n.md) — SSR loader/bootstrap tags (translation rendering is client-side).
- [error-reporting](error-reporting.md) — `see()` structured error reporting.
- [testing](testing.md) — `configureForTesting`, `configureForOffline`, the override helpers.
- [openfeature](openfeature.md) — provider status (not shipped).
- [advanced](advanced.md) — private attributes, `bucketBy`, sticky bucketing, anonymous IDs, change listeners.
