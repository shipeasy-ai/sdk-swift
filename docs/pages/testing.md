# Testing

For unit tests, build an engine with `Engine.forTesting()`. It does **zero
network**, needs **no API key**, is immediately ready
(`initialize()` / `initializeOnce()` are no-ops), and `track(...)` is a no-op.
Seed each entity with the `override*` setters — an override always wins over live
evaluation, so your tests are deterministic.

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

## Offline snapshots

Build a fully offline engine from a JSON file or in-memory blobs — no network,
immediately ready, telemetry off; `initialize()` / `initializeOnce()` /
`track(...)` are no-ops. Evaluations run the **real** eval against the snapshot,
and `override*` values apply on top.

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
