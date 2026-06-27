Read a dynamic config (returns `Any?`; pass `default` for a fallback).

```swift
let client = try Client(["user_id": "u_123"])
let value = await client.getConfig("{{RESOURCE_NAME}}", default: ["headline": "Welcome"])
```
