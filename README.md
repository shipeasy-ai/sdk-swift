# Shipeasy (Swift)

Server SDK for [Shipeasy](https://shipeasy.dev). SwiftPM, iOS 15+/macOS 12+.

```swift
dependencies: [
    .package(url: "https://github.com/shipeasy-ai/sdk-swift.git", from: "0.8.0"),
]
```

## Quickstart — `configure` once, then a `Client` per user

Configure the package-global engine once at startup, then construct a cheap,
**user-bound** `Client` per request. The bound `Client`'s methods take **no user
argument** — the user is bound at construction:

```swift
import Shipeasy

// Once, at startup. Builds the single global Engine and kicks off its one-shot
// fetch (fire-and-forget). Optionally map YOUR user object → the attribute map.
configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

// Per user / request. The configured `attributes` transform runs once here.
let client = try Client(["user_id": "u_123", "plan": "pro"])

let enabled = await client.getFlag("new_checkout")
let cfg = await client.getConfig("billing_copy")
let r = await client.getExperiment("checkout_button", defaultParams: ["color": "blue"])
let killed = await client.getKillswitch("panic_button")
```

`Client(user)` is cheap: it owns no connection, cache, or poll timer — it
delegates every evaluation to the single configured `Engine`. Constructing a
`Client` before `configure(...)` throws `NotConfiguredError`.

### `attributes` transform

Pass `attributes` to map *your* user object (any shape) to the Shipeasy
attribute map (`["user_id": ..., "anonymous_id": ..., <targeting attrs>]`). It
runs once, in the `Client` constructor. The default is identity — the user value
is assumed to already BE the attribute map.

```swift
struct AppUser { let id: String; let region: String }

configure(apiKey: serverKey) { user in
    let u = user as! AppUser
    return ["user_id": u.id, "country": u.region]
}

let on = await (try Client(AppUser(id: "u_123", region: "US"))).getFlag("us_only")
```

### Long-running servers: the `Engine`

For background polling (instead of the one-shot fetch), keep the returned
`Engine` and call `initialize()` on it. The `Engine` is the heavyweight type
(formerly `Client`) that owns the API key, HTTP, the blob cache and the poll
timer, with the full lower-level surface (`getFlag(_:user:)`, `track`,
`logExposure`, `evaluate`, overrides, snapshots, `see()`):

```swift
let engine = configure(apiKey: serverKey, init: false)
try await engine.initialize() // starts the background poll
await engine.track(userId: "u_123", eventName: "purchase", properties: ["amount": 49])
```

## Server-side rendering (SSR)

Emit the request's evaluated flags as a declarative `<script>` tag so the
browser SDK has them on first paint. `bootstrapScriptTag` carries the payload in
`data-*` attributes (**no key**); the static `se-bootstrap.js` loader hydrates
`window.__SE_BOOTSTRAP` and writes the `__se_anon_id` cookie so the browser
buckets identically to the server.

```swift
let user = ["user_id": "u_123"]

// Two tags for the document <head>. The PUBLIC client key (not the server
// key) goes on the i18n loader tag. (`Engine` is an actor, so `await`.)
let bootstrap = await client.bootstrapScriptTag(user, anonId: anonId)
let i18n = await client.i18nScriptTag(clientKey, profile: "en:prod")
let head = bootstrap + i18n

// …or get the raw payload (["flags", "configs", "experiments", "killswitches"]):
let boot = await client.evaluate(user)
```

`bootstrapScriptTag` also accepts `i18nProfile:` and `baseURL:`
(defaults to `https://cdn.shipeasy.ai`).

## Default values

`getFlag` and `getConfig` take an optional `default` that is returned **only
when the value cannot be evaluated** — never when it simply evaluates to
`false`/absent-but-evaluable:

```swift
// Returns the default ONLY if the client isn't ready yet or the flag doesn't
// exist; a flag that evaluates to false still returns false.
let on = await client.getFlag("new_checkout", user: ["user_id": "u_123"], default: true)

// Returns the default when the config key is absent.
let copy = await client.getConfig("billing_copy", default: ["headline": "Welcome"])
```

The original two-argument forms (`getFlag(_:user:)`, `getConfig(_:)`) are
unchanged.

## Evaluation detail

`getFlagDetail` returns both the value and the reason it resolved that way,
useful for debugging targeting and rollout:

```swift
let d = await client.getFlagDetail("new_checkout", user: ["user_id": "u_123"])
// d.value  -> Bool
// d.reason -> one of the FlagReason raw values
```

`reason` is one of:

| Reason             | Meaning                                              |
| ------------------ | ---------------------------------------------------- |
| `OVERRIDE`         | A local `overrideFlag` supplied the value            |
| `CLIENT_NOT_READY` | No live blob yet (client hasn't fetched)             |
| `FLAG_NOT_FOUND`   | The gate name isn't in the flags blob                |
| `OFF`              | The gate exists but is disabled / killed             |
| `RULE_MATCH`       | The gate evaluated to `true` (rules + rollout match) |
| `DEFAULT`          | The gate evaluated to `false` (not targeted)         |

`getFlag` delegates to `getFlagDetail` and returns `.value`.

## Change listeners

Register a listener that fires after a fetch applies **new** data (an HTTP 200,
not a 304). When the background poll is running (after `initialize()`), it fires
on each poll that brings new data; otherwise it fires on the next refresh that
applies new data. Listeners never fire in `forTesting()`/snapshot (local) mode.
`onChange` returns an unsubscribe closure:

```swift
let unsubscribe = await client.onChange {
    print("flag/experiment data refreshed")
}
// later…
unsubscribe()
```

## Offline snapshot

Build a fully offline client from a JSON file or in-memory blobs — no network,
immediately ready, telemetry off, `initialize()`/`initializeOnce()`/`track(...)`
are no-ops. Evaluations run the **real** eval against the snapshot, and
`override*` values apply on top:

```swift
// From a file: { "flags": <body of /sdk/flags>, "experiments": <body of /sdk/experiments> }
let client = try Engine.fromFile("/path/to/snapshot.json")

// Or from in-memory blobs:
let client2 = Engine.fromSnapshot(
    flags: ["gates": [/* … */], "configs": [/* … */]],
    experiments: ["experiments": [/* … */], "universes": [/* … */]]
)

let on = await client.getFlag("new_checkout", user: ["user_id": "u_123"])
```

## Anonymous visitors

For logged-out traffic you need a *stable* unit so a fractional rollout buckets
the same on the server and in the browser. `AnonId` provides the cross-SDK
`__se_anon_id` cookie primitives (this SDK is framework-agnostic, so it ships
helpers rather than a middleware). In a server handler, resolve the id off the
request `Cookie` header and echo it back on the response:

```swift
let resolved = AnonId.resolve(cookieHeader: req.headers["cookie"].first)
let on = await client.getFlag("new_checkout", user: ["anonymous_id": resolved.id])
if resolved.minted {
    res.headers.add(name: "set-cookie", value: AnonId.setCookieHeader(resolved.id, secure: true))
}
```

The cookie is non-`HttpOnly` by design so the browser SDK buckets identically; a
request with **no** unit still resolves a fully-rolled (100%) gate as on. Cookie
name + format are a cross-SDK contract — see `18-identity-bucketing.md`.

> Server-key only — never embed in iOS app bundles. A future `ShipeasyClient` package will cover client-key, mobile-friendly use.

## Testing

For unit tests, build an engine with `Engine.forTesting()`. It does **zero
network**, needs **no API key**, is immediately ready (`initialize()` /
`initializeOnce()` are no-ops), and `track(...)` is a no-op. Seed each entity
with the `override*` setters — an override always wins over live evaluation, so
your tests are deterministic:

```swift
import Shipeasy

let client = Engine.forTesting() // no key, no network, ready to use

// Flags
await client.overrideFlag("new_checkout", true)
let enabled = await client.getFlag("new_checkout", user: ["user_id": "u_123"])
// enabled == true

// Dynamic configs
await client.overrideConfig("billing_copy", ["headline": "50% off"])
let cfg = await client.getConfig("billing_copy")
// cfg == ["headline": "50% off"]

// Experiments — forces inExperiment: true with your group + params
await client.overrideExperiment("checkout_button", group: "treatment", params: ["color": "green"])
let r = await client.getExperiment("checkout_button", user: ["user_id": "u_123"], defaultParams: nil)
// r.inExperiment == true, r.group == "treatment", r.params == ["color": "green"]

// track() is a no-op in test mode — safe to call, never sends.
await client.track(userId: "u_123", eventName: "purchase")

// Reset everything back to default evaluation.
await client.clearOverrides()
```

The `override*` setters and `clearOverrides()` also work on a normal,
network-backed `Engine` if you want to pin a value at runtime.
