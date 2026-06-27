Read a flag on a user-bound `Client`. Assumes `configure()` ran at startup — see Installation.

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; getFlag returns false when the engine isn't ready or the flag is absent
let enabled = await client.getFlag("{{RESOURCE_NAME}}")

// optional `default:` — returned ONLY when the flag can't be evaluated
// (engine not ready / flag not found), never when it evaluates to false
let safe = await client.getFlag("{{RESOURCE_NAME}}", default: false)
```
