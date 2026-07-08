Read the assignment for `{{EXPERIMENT_KEY}}`, branch on the group, and track the
conversion event — all from the configured `ShipeasyClient`. Assumes
`configureClient(...)` ran at startup — see Installation.

```swift
let client = shipeasyClient()!   // configured once at app launch

// name; defaultParams: params returned when the user isn't enrolled (nil for none)
let r = await client.getExperiment("{{EXPERIMENT_KEY}}", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    // r.params holds the variant params — cast to your shape
    let color = (r.params as? [String: Any])?["color"] as? String
    // render the treatment variant
}

// record the exposure at the point you present the variant (no-op when not enrolled)
await client.logExposure("{{EXPERIMENT_KEY}}")

// conversion event — the unit is the identified user (no id argument);
// event name; optional `properties:` bag (default [:])
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
