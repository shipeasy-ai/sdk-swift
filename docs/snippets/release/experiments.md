Enrol a user, branch on the group, and track the conversion event.

```swift
let client = try Client(["user_id": "u_123"])
let r = await client.getExperiment("{{RESOURCE_NAME}}", defaultParams: ["color": "blue"])

if r.inExperiment, r.group == "treatment" {
    // render the treatment variant
}

await client.track("{{SUCCESS_EVENT}}")
```
