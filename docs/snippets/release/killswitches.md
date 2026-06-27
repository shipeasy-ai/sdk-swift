Check whether a kill switch is engaged (`true` = killed). Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; optional `switchKey:` reads one named per-key override (nil = the kill switch itself)
let killed = await client.getKillswitch("{{RESOURCE_NAME}}", switchKey: nil)
```
