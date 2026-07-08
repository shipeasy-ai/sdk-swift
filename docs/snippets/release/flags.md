Evaluate the feature gate `{{FLAG_KEY}}` from the configured `ShipeasyClient`
(cached `/sdk/evaluate` read). Assumes `configureClient(...)` ran at startup — see
Installation.

```swift
// name; getFlag returns the default when assignments aren't loaded or the flag is absent
let enabled = await shipeasyClient()?.getFlag("{{FLAG_KEY}}") ?? false

// optional `default:` — returned ONLY when the flag can't be evaluated
// (assignments not loaded / flag not found), never when it evaluates to false
let safe = await shipeasyClient()?.getFlag("{{FLAG_KEY}}", default: false) ?? false
```
