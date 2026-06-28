Evaluate the feature gate `{{FLAG_KEY}}` on a user-bound `Client`. Assumes `configure()` ran at startup — see Installation.

### Basic check

```swift
// construct once per callsite (cheap; binds the user + runs the attributes transform)
let client = try Client(["user_id": "u_123"])

// name; getFlag returns false when the rules aren't ready or the flag is absent
let enabled = await client.getFlag("{{FLAG_KEY}}")

// optional `default:` — returned ONLY when the flag can't be evaluated
// (rules not ready / flag not found), never when it evaluates to false
let safe = await client.getFlag("{{FLAG_KEY}}", default: false)
```

### Why it resolved that way — `getFlagDetail`

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// returns a FlagDetail (.value, .reason); reason ∈ RULE_MATCH / DEFAULT / OFF /
// OVERRIDE / FLAG_NOT_FOUND / CLIENT_NOT_READY
let detail = await client.getFlagDetail("{{FLAG_KEY}}")
print("flag={{FLAG_KEY}} value=\(detail.value) reason=\(detail.reason)")
```
