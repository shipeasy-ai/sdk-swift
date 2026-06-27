Enrol a user, branch on the group, and track the conversion event. Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; defaultParams: params returned when the user isn't enrolled (nil for none)
let r = await client.getExperiment("{{RESOURCE_NAME}}", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    // render the treatment variant
}

// Client-only conversion event — event name; optional `properties:` bag (default [:])
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
