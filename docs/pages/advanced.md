# Advanced

## Private attributes

Attribute names listed in `privateAttributes` on `configureClient(...)` are usable
for targeting but are **stripped from every outbound telemetry payload** — the
`track()` properties bag and the `see()` `.extras()` map. Targeting still works
(the edge evaluates on the identified attributes); the private keys just never
reach `/collect`:

```swift
configureClient(clientKey: "pk_live_…", privateAttributes: ["email", "ssn"])
```

## Anonymous id persistence — `AnonymousStore`

Persisting the device `anonymous_id` across launches is **the whole point** of the
client SDK: without it a fresh UUID every cold start silently re-buckets every
fractional rollout and experiment. By default the id lives in `UserDefaults`
(`UserDefaultsAnonymousStore`).

`AnonymousStore` is a two-method protocol:

```swift
public protocol AnonymousStore {
    func get(_ key: String) -> String?
    func set(_ key: String, _ value: String)
}
```

Supply your own to `configureClient(clientKey:store:)` to back the id with the
**Keychain** (survives app reinstalls), an **app-group** container (shared with
extensions / widgets), or an **in-memory** map (tests):

```swift
struct KeychainAnonStore: AnonymousStore {
    func get(_ key: String) -> String? { Keychain.read(key) }
    func set(_ key: String, _ value: String) { Keychain.write(key, value) }
}

configureClient(clientKey: "pk_live_…", store: KeychainAnonStore())
```

`get`/`set` are synchronous and best-effort — a throwing or slow backing store
degrades gracefully and never crashes a read. The stable id is readable as
`await shipeasyClient()?.anonymousId`.

The client also transparently persists and echoes back its **sticky** experiment
state through the same store, so a unit stays on its first-assigned variant across
launches — there is nothing to configure for that.

## Reading the stable device id — `anonymousId`

`anonymousId` is the persisted device bucketing id. Read it to correlate your own
analytics with Shipeasy bucketing, or to seed a support ticket:

```swift
let id = await shipeasyClient()?.anonymousId
```

## Re-evaluating — `refreshAssignments`

`refreshAssignments()` re-evaluates for the **current** user (no identity change)
over `/sdk/evaluate`, updating the local cache — e.g. to pick up a flag you just
published:

```swift
await shipeasyClient()?.refreshAssignments()
```

For an identity change (login) use `identify(...)`; for logout use `reset()`. See
[configuration](configuration.md).

## Manual exposure

`logExposure` records an experiment exposure explicitly at the point you present
the variant, rather than relying on `getExperiment` alone. It re-evaluates and only
emits when the device user is enrolled — a no-op otherwise:

```swift
await shipeasyClient()?.logExposure("checkout_button")
```
