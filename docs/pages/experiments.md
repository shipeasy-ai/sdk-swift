# Experiments

`getExperiment` reads the device user's A/B assignment from the cached
`/sdk/evaluate` response and returns an `ExperimentResult`.

## The `ExperimentResult` shape

```swift
public struct ExperimentResult: Sendable {
    public let inExperiment: Bool   // was the user enrolled?
    public let group: String        // assigned group, e.g. "control" / "treatment"
    public let params: Any?         // the variant params (or your defaultParams)
}
```

When the user is **not** enrolled (or the experiment is absent, or assignments
aren't loaded yet), you get `inExperiment: false` and your `defaultParams` echoed
back as `params`.

## Read and branch

```swift
let client = shipeasyClient()!
await client.identify(["user_id": "u_123"])

let r = await client.getExperiment("checkout_button", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    let color = (r.params as? [String: Any])?["color"] as? String
    // render the treatment
}
```

`defaultParams` is the value returned for `params` whenever the user isn't
enrolled. Pass `nil` if you don't need a fallback.

## Exposure — `logExposure`

Record an exposure explicitly at the point you actually present the variant.
`logExposure` re-evaluates and only emits when the device user is enrolled — it is
a no-op otherwise. Fire-and-forget; never blocks:

```swift
await client.logExposure("checkout_button")
```

## Tracking conversions — `track`

Record a conversion event so the analysis pipeline can compute lift. The unit is
derived from the identified user (`user_id`, else the persisted `anonymous_id`),
so no id argument is needed. Fire-and-forget; private attributes are stripped
before egress:

```swift
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
