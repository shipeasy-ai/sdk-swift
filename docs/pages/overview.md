# Overview

`Shipeasy` is the **native client** Swift SDK for [Shipeasy](https://shipeasy.ai) —
feature flags, dynamic configs, kill switches, and A/B experiments for an
iOS / macOS / tvOS / watchOS app. It uses a **public client key** (`pk_…`, safe
to embed in a shipped app), evaluates one device user server-side over
`POST /sdk/evaluate`, and serves cheap local reads from the cached response.

## Mental model: `configureClient()` once, then `identify` + read

You call `configureClient(clientKey:)` **once** at app launch. It returns a
`ShipeasyClient` and registers it as the process-global one (fetch it later with
`shipeasyClient()`). Then you `identify(...)` the device user (which evaluates and
caches assignments) and read flags/configs/experiments from the cache:

```swift
import Shipeasy

// Once, at app launch — PUBLIC client key (pk_…), safe to embed:
let client = configureClient(clientKey: "pk_live_…")

// Bind the user (pass [:] for a logged-out visitor). Awaiting the first identify
// guarantees the first reads see assignments:
await client.identify(["user_id": "u_123", "plan": "pro"])

// Reads serve the cached /sdk/evaluate response (no per-call network):
let enabled = await client.getFlag("new_checkout")
```

`ShipeasyClient` is a Swift `actor`, so its methods are `async` — you `await`
them. Reads are served from a **local cache** of the last `/sdk/evaluate`
response, so they never hit the network and are safe from any thread. Before the
first `identify`, reads return the supplied defaults.

The **persisted device `anonymous_id`** is the whole point of the client SDK: it
survives cold starts so a logged-out visitor buckets identically into every
fractional rollout and experiment on every launch. See
[configuration](configuration.md) and [advanced](advanced.md#anonymous-id-persistence-anonymousstore).

## The things you use

| Function / type            | Role |
| -------------------------- | ---- |
| `configureClient(...)`     | Called **once** at app launch. Wires the client key, HTTP, and the anon-id store; returns the `ShipeasyClient` and registers it globally. First-config-wins (idempotent). See [configuration](configuration.md). |
| `shipeasyClient()`         | Fetch the configured client (`ShipeasyClient?`), or `nil` if `configureClient` hasn't run. |
| `client.identify(_:)`      | Bind the device user + refresh assignments over `/sdk/evaluate`. Call at launch, on login, and whenever targeting attributes change. |
| `client.reset()`           | Logout: clear `user_id`, keep the device `anonymous_id`, re-evaluate as anonymous. |
| `client.getFlag/getConfig/getExperiment/getKillswitch` | Cached reads for the current user. |
| `client.track(_:properties:)` / `client.logExposure(_:)` | Conversion + exposure telemetry (fire-and-forget). |
| `see(_:)` family           | Structured error reporting. See [error-reporting](error-reporting.md). |

## Pages

- [installation](installation.md) — SwiftPM dependency, platforms, where to call `configureClient`, and custom anon-id stores.
- [configuration](configuration.md) — `configureClient(...)`, every option, the persisted anon-id, `shipeasyClient()`.
- [flags](flags.md) — `getFlag`, defaults.
- [configs](configs.md) — `getConfig`, defaults, typed reads.
- [killswitches](killswitches.md) — `getKillswitch` + named override switches.
- [experiments](experiments.md) — `getExperiment`, `ExperimentResult`, `track`, `logExposure`.
- [i18n](i18n.md) — not part of the native client SDK.
- [error-reporting](error-reporting.md) — `see()` structured error reporting.
- [testing](testing.md) — hermetic tests with an in-memory store + a stub transport.
- [openfeature](openfeature.md) — provider status (not shipped).
- [advanced](advanced.md) — private attributes, custom `AnonymousStore`, `anonymousId`, `refreshAssignments`.
