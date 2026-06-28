Read the dynamic config `{{CONFIG_KEY}}` (returns `Any?`). Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; returns nil when the key is absent (or the rules aren't ready)
let value = await client.getConfig("{{CONFIG_KEY}}")

// optional `default:` — returned when the config key is absent
let copy = await client.getConfig("{{CONFIG_KEY}}", default: ["headline": "Welcome"])

// the value is Any? — cast to the shape your config defines
let headline = (copy as? [String: Any])?["headline"] as? String
```
