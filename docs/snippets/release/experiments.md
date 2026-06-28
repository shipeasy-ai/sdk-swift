Enrol a user into `{{EXPERIMENT_KEY}}`, branch on the group, and track the conversion event. Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; defaultParams: params returned when the user isn't enrolled (nil for none)
let r = await client.getExperiment("{{EXPERIMENT_KEY}}", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    // r.params holds the variant params — cast to your shape
    let color = (r.params as? [String: Any])?["color"] as? String
    // render the treatment variant
}

// Client-only conversion event — the unit is the bound user (no id argument);
// event name; optional `properties:` bag (default [:])
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
