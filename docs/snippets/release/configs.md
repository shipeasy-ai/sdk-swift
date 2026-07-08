Read the dynamic config `{{CONFIG_KEY}}` from the configured `ShipeasyClient`
(returns `Any?`). Assumes `configureClient(...)` ran at startup — see Installation.

```swift
// name; returns nil when the key is absent (or assignments aren't loaded)
let value = await shipeasyClient()?.getConfig("{{CONFIG_KEY}}")

// optional `default:` — returned when the config key is absent
let copy = await shipeasyClient()?.getConfig("{{CONFIG_KEY}}", default: ["headline": "Welcome"])

// the value is Any? — cast to the shape your config defines
let headline = (copy as? [String: Any])?["headline"] as? String
```
