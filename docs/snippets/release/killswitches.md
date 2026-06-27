Check whether a kill switch is engaged (`true` = killed).

```swift
let client = try Client(["user_id": "u_123"])
let killed = await client.getKillswitch("{{RESOURCE_NAME}}")
```
