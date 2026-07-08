# Experiments

A **universe** is a mutual-exclusion pool: the device user lands in **at most one**
experiment per universe. You don't read an experiment by name — you ask a universe
for an assignment. `universe(name).assign()` reads the device user's assignment
from the cached `/sdk/evaluate` response and returns an `Assignment`.

## The `Assignment` shape

```swift
public struct Assignment: Sendable {
    public let name: String?        // experiment the unit landed in, or nil when not enrolled
    public let group: String?       // assigned group, e.g. "treatment", or nil when not enrolled
    public var enrolled: Bool       // group != nil
    // Read a resolved param: variant override ?? universe default ?? fallback.
    public func get<T>(_ field: String, _ fallback: T? = nil) -> T?
    public func get(_ field: String) -> Any?   // untyped
}
```

The handle **never throws**. A not-enrolled unit still resolves `get()` — you get
the universe default (or your fallback), so branching code always has a value.

## Assign and branch

```swift
let client = shipeasyClient()!
await client.identify(["user_id": "u_123"])

let a = await client.universe("checkout").assign()

if a.enrolled, a.group == "treatment" {
    let color = a.get("button_color", "blue")   // variant param, else universe default, else "blue"
    // render the treatment
} else {
    let color = a.get("button_color", "blue")   // resolves to the universe default here
    // render the control
}
```

`get(field, fallback)` resolves in order: the variant's override, then the
universe default, then your `fallback`. When not enrolled there is no variant, so
you get the universe default (or `fallback`). Enrolled params are already merged
(universe defaults ⊕ variant) by the edge.

## Exposure — automatic

`assign()` **auto-logs a single exposure** when the unit is enrolled — you don't
call anything separately. There is no `logExposure`. Pass `logExposure: false` to
suppress the auto-exposure (e.g. when you assign to inspect the group but don't yet
present the variant):

```swift
let a = await client.universe("checkout").assign(logExposure: false)
```

Exposure is fire-and-forget and never blocks; it is a no-op when the unit isn't
enrolled or telemetry is disabled.

## Tracking conversions — `track`

Record a conversion event so the analysis pipeline can compute lift. The unit is
derived from the identified user (`user_id`, else the persisted `anonymous_id`),
so no id argument is needed. Fire-and-forget; private attributes are stripped
before egress:

```swift
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
