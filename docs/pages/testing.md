# Testing

For unit tests, configure Shipeasy in **test mode** with `configureForTesting(...)`
— a drop-in sibling of `configure(...)` that does **zero network**, needs **no API
key**, and is immediately ready. Seed the values your code under test should see,
then read them through the ordinary bound `Client`. It **replaces** any previous
configuration, so each test can reconfigure freely.

```swift
import Shipeasy

// no key, no network; seed what the code under test should see
await configureForTesting(
    flags: ["new_checkout": true],                                  // [name: Bool]
    configs: ["billing_copy": ["headline": "50% off"]],             // [name: Any?]
    experiments: ["checkout_button": (group: "treatment",           // [name: (group, params)]
                                      params: ["color": "green"])]
)

// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

await client.getFlag("new_checkout", default: false)   // true
await client.getConfig("billing_copy")                 // ["headline": "50% off"]

let r = await client.getExperiment("checkout_button", defaultParams: nil)
// r.inExperiment == true, r.group == "treatment", r.params == ["color": "green"]

// track()/logExposure() are no-ops in test mode — safe to call, never send.
await client.track("purchase")
```

The seed maps:

- `flags: [String: Bool]` — forced `getFlag` results.
- `configs: [String: Any?]` — forced `getConfig` results.
- `experiments: [String: (group: String, params: Any?)]` — forced enrolments.

## On-the-spot overrides

Layer additional forced values on top of whatever you configured with the
package-level override helpers (all `async`). An override always wins until you
`clearOverrides()`:

```swift
await overrideFlag("FLAG_KEY", true)
await overrideConfig("CONFIG_KEY", ["headline": "hi"])
await overrideExperiment("EXPERIMENT_KEY", group: "treatment", params: ["color": "green"])

// drop every on-the-spot override (and, in test mode, the seed too — test mode has
// no blob beneath, so everything reverts to empty-blob defaults)
await clearOverrides()
```

Under `configureForOffline` (below), `clearOverrides()` leaves the snapshot in
place — evaluations revert to the snapshot rather than empty defaults.

## Offline snapshots

`configureForOffline(...)` evaluates the **real** rules from a snapshot with no
network — a drop-in sibling of `configure(...)` (no API key). Provide exactly one
source: a `path` to a JSON file, or an in-memory `snapshot`. Optional
`flags`/`configs`/`experiments` overrides layer on top.

```swift
// From a JSON file on disk
try await configureForOffline(path: "/path/to/snapshot.json")

// …or an in-memory snapshot: ["flags": <flags blob>, "experiments": <experiments blob>]
try await configureForOffline(snapshot: [
    "flags": ["gates": [:], "configs": [:], "killswitches": [:]],
    "experiments": ["experiments": [:], "universes": [:]]
])

let client = try Client(["user_id": "u_123"])
let on = await client.getFlag("new_checkout")
```

### The snapshot file format

A snapshot file is a single JSON object with a `flags` blob (the body of
`/sdk/flags`) and an `experiments` blob (the body of `/sdk/experiments`):

```json
{
  "flags": {
    "gates": {
      "new_checkout": { "enabled": true, "rolloutPct": 10000, "salt": "s" }
    },
    "configs": {
      "billing_copy": { "headline": "Welcome" }
    },
    "killswitches": {}
  },
  "experiments": {
    "experiments": {},
    "universes": {}
  }
}
```

A gate is `{ "enabled": true, "rolloutPct": 10000, "salt": "s" }` where
`rolloutPct` is in **basis points** — `10000` is 100%, `1000` is 10%, `0` is off.
`configs` maps a config name to its JSON value. Empty `killswitches` /
`experiments` / `universes` objects are valid.
