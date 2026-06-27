# Experiments

`getExperiment` enrols the bound user into an A/B experiment and returns an
`ExperimentResult`.

## The `ExperimentResult` shape

```swift
public struct ExperimentResult: Sendable {
    public let inExperiment: Bool   // was the user enrolled?
    public let group: String        // assigned group, e.g. "control" / "treatment"
    public let params: Any?         // the variant params (or your defaultParams)
}
```

When the user is **not** enrolled, you get `inExperiment: false`, `group:
"control"`, and your `defaultParams` echoed back as `params`.

## Bound `Client` form

```swift
let client = try Client(["user_id": "u_123"])
let r = await client.getExperiment("checkout_button", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    let color = (r.params as? [String: Any])?["color"] as? String
    // render the treatment
}
```

`defaultParams` is the value returned for `params` whenever the user isn't
enrolled (or the experiment is absent). Pass `nil` if you don't need a fallback.

## Engine (low-level) form

```swift
let engine = globalEngine()!
let r = await engine.getExperiment(
    "checkout_button",
    user: ["user_id": "u_123"],
    defaultParams: ["color": "blue"]
)
```

## Tracking conversions

Record a conversion event so the analysis pipeline can compute lift. You already
hold a bound `Client` from `getExperiment`, so call `track` straight on it — the
unit is derived from the bound user (`user_id`, else `anonymous_id`), no id
argument needed. Experiments are end-to-end Client-only:

```swift
let client = try Client(["user_id": "u_123"])
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```

`logExposure` is on the bound `Client` too — record an exposure explicitly at the
point you present the treatment (re-evaluates and only emits when the bound user
is enrolled):

```swift
await client.logExposure("checkout_button")
```

### Engine (low-level) form

The unit-explicit forms remain on the `Engine` for advanced callers that don't
have a bound `Client` (both are a no-op in test/snapshot mode):

```swift
let engine = globalEngine()!
await engine.track(
    userId: "u_123",
    eventName: "{{SUCCESS_EVENT}}",
    properties: ["amount": 49]
)
await engine.logExposure(userId: "u_123", experiment: "checkout_button")
```
