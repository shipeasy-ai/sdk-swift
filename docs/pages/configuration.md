# Configuration

`configureClient(...)` wires the client key, HTTP, and the anon-id store. Call it
**once** at app launch. It returns the `ShipeasyClient` and registers it as the
process-global one, fetchable with `shipeasyClient()`. It is **first-config-wins**
(idempotent) — the first call configures; later calls return the same client and
change nothing. See [installation](installation.md) for where to place the call.

```swift
import Shipeasy

let client = configureClient(clientKey: "pk_live_…")
```

On first config it fire-and-forgets an anonymous `identify([:])`, so `getFlag`
resolves for logged-out users without an explicit `identify`.

## `configureClient()` options

| Param               | Default | Purpose |
| ------------------- | ------- | ------- |
| `clientKey`         | —       | Your **public client** key (`pk_…`). Safe to embed in a shipped app. Required. |
| `baseURL`           | `https://api.shipeasy.ai` | The edge endpoint that evaluates and returns assignments. |
| `env`               | `"prod"` | Deployment env; selects which environment's rules the edge evaluates, and is stamped onto `see()` error events. |
| `isNetworkEnabled`  | env-derived (see below) | Master egress switch. When `false` the client is fully **offline** — no `/sdk/evaluate`, no `/collect` (`track` / exposures / `see()`), no telemetry; reads serve the cache / supplied defaults. Leave `nil` to use the environment default; pass `true` / `false` to force it. |
| `isTrackingEnabled` | env-derived (see below) | Usage telemetry on/off (the per-evaluation usage beacon). Leave `nil` for the environment default; pass `false` to keep it off while the network stays on. Forced off whenever `isNetworkEnabled` is off. |
| `telemetryURL`      | `https://t.shipeasy.ai` | Where telemetry POSTs go. |
| `store`             | `UserDefaultsAnonymousStore()` | Where the persistent `anonymous_id` lives. Supply your own `AnonymousStore` for the Keychain / app-group / tests — see [advanced](advanced.md#anonymous-id-persistence-anonymousstore). |
| `privateAttributes` | `[]`    | Attribute names usable for targeting but stripped from outbound `track()` / `see()` payloads. See [advanced](advanced.md#private-attributes). |
| `session`           | shared `URLSession` | Optional `URLSession` for the HTTP calls. |
| `transport`         | `URLSession`-backed | Optional low-level request transport. Injecting a stub is how tests run hermetically — see [testing](testing.md). |

## Environment-derived egress defaults

By default the SDK is **quiet outside production**: on a dev machine or in CI it
makes **no** outbound request unless you opt in. Both `isNetworkEnabled` and
`isTrackingEnabled` default to **on in production and off in every other
environment**, so an app embedding the SDK never phones home from a local build.

"Production" is decided in this order:

1. The native env var `SHIPEASY_ENV`, then `APP_ENV`, then `ENV`. A value of
   `production` or `prod` (case-insensitive) means production; any other present
   value (`development`, `staging`, `test`, …) means not production.
2. If none is set (the common case for a shipped app), the `#if DEBUG` build
   flag: a debug build is **not** production, a release build **is**.
3. If still undecided, the `env:` option you pass (which itself defaults to
   `"prod"`), so a real production deploy stays on.

An explicitly-passed value **always** overrides the environment default:

```swift
// Force the client fully offline (e.g. a preview build), even in production:
configureClient(clientKey: "pk_live_…", isNetworkEnabled: false)

// Force it on in a non-production build (e.g. a staging QA app):
configureClient(clientKey: "pk_live_…", isNetworkEnabled: true)
```

> **Behaviour change (2.1.0):** earlier versions always made network calls. To
> restore that everywhere, either set `SHIPEASY_ENV=production` in the app's
> environment or pass `isNetworkEnabled: true`.

## The configured client — `shipeasyClient()`

`configureClient(...)` returns the client **and** stores it globally. Anywhere in
the app, fetch it with `shipeasyClient()` (returns `ShipeasyClient?`, or `nil`
before configuration):

```swift
let flag = await shipeasyClient()?.getFlag("new_checkout") ?? false
```

## Binding the user — `identify`

`identify(_:)` binds the device user and refreshes assignments over
`POST /sdk/evaluate`. Pass your targeting attribute map; the persisted
`anonymous_id` is always attached automatically:

```swift
await shipeasyClient()?.identify(["user_id": "u_123", "plan": "pro"])
```

Call `identify`:

- **at launch** (or `[:]` for a logged-out visitor — the anonymous `identify` on
  first config already covers this if you don't need attributes),
- **on login**, with `user_id` and any targeting attributes,
- **whenever targeting attributes change** (plan upgrade, opted-in setting, etc.).

Awaiting `identify` guarantees the first reads see the fresh assignments. A failed
evaluate is non-fatal — reads simply fall back to the supplied defaults.

### Logout — `reset`

`reset()` clears the bound `user_id` but **keeps** the device `anonymous_id`, then
re-evaluates as an anonymous visitor:

```swift
await shipeasyClient()?.reset()
```

### Re-evaluate — `refreshAssignments`

`refreshAssignments()` re-evaluates for the current user without changing identity
— e.g. to pick up a just-published flag:

```swift
await shipeasyClient()?.refreshAssignments()
```

## The persisted `anonymous_id`

The stable device id is exposed as `await shipeasyClient()?.anonymousId`. It is
minted once and **persisted** via the `store` so it survives cold starts. This is
what keeps a logged-out visitor in the same bucket for every fractional rollout
and experiment on every launch. See
[advanced](advanced.md#anonymous-id-persistence-anonymousstore) to back it with
the Keychain or an app-group container.
