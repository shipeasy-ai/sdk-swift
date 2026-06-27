# Advanced

## Private attributes

Attribute names listed in `privateAttributes` are usable for targeting but are
**stripped from every outbound `track()` payload** — the server evaluates
locally, so private attrs never leave for evaluation; the only egress is
`/collect`, where the listed keys are removed.

```swift
configure(apiKey: serverKey, privateAttributes: ["email", "ssn"])
```

## `bucketBy` — custom bucketing identifier

Experiments and gates bucket on `user_id` (falling back to `anonymous_id`) by
default. When the resource sets a `bucketBy` attribute (e.g. `company_id`),
evaluation buckets on that attribute instead — so every user in a company gets
the same variant. This is driven by the resource config (no SDK call needed);
just make sure the named attribute is present in the user map:

```swift
let r = await client.getExperiment("team_dashboard", defaultParams: nil)
// if the experiment's bucketBy is "company_id", include it in the user map:
let client = try Client(["user_id": "u_123", "company_id": "acme"])
```

## Sticky bucketing

Pass a `StickyBucketStore` to `configure(...)` to **lock a unit to its
first-assigned variant**. Once enrolled, changing the allocation % or weights
won't re-bucket the unit — rotating the experiment salt is the reshuffle lever.
Absent ⇒ deterministic (fully backward compatible).

```swift
let store = InMemoryStickyBucketStore()
configure(apiKey: serverKey, stickyStore: store)
```

`StickyBucketStore` is a protocol (`get` / `set` over `StickyEntry`), so you can
back it with your own persistence (Redis, a DB, etc.). `InMemoryStickyBucketStore`
is provided for tests and single-process use.

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
name + format are a cross-SDK contract (see `18-identity-bucketing.md`).

## Manual exposure

The engine exposes `logExposure(userId:experiment:)` to record an experiment
exposure explicitly (rather than relying on `getExperiment` to log it):

```swift
let engine = globalEngine()!
await engine.logExposure(userId: "u_123", experiment: "checkout_button")
```

## Change listeners

Register a listener that fires after a fetch applies **new** data (HTTP 200, not
304). With the background poll running it fires on each poll bringing new data;
otherwise on the next refresh that applies new data. Listeners never fire in
`forTesting()` / snapshot mode. `onChange` returns an unsubscribe closure:

```swift
let unsubscribe = await client.onChange {
    print("flag/experiment data refreshed")
}
// later…
unsubscribe()
```

## SSR bootstrap

See [i18n](i18n.md) for `bootstrapScriptTag` / `i18nScriptTag` and the
`evaluate(_:)` raw payload (`["flags", "configs", "experiments", "killswitches"]`)
used to hydrate the browser SDK on first paint.
