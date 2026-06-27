Configure once, then read a flag on a user-bound `Client`.

```swift
import Shipeasy

configure(apiKey: ProcessInfo.processInfo.environment["SHIPEASY_SERVER_KEY"]!)

let client = try Client(["user_id": "u_123"])
let enabled = await client.getFlag("{{RESOURCE_NAME}}")
```
