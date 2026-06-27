Read a dynamic config (returns `Any?`). Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; optional `default:` — returned when the config key is absent
let value = await client.getConfig("{{RESOURCE_NAME}}", default: ["headline": "Welcome"])
```
