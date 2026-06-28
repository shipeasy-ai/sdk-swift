Check whether the kill switch `{{KILLSWITCH_KEY}}` is engaged (`true` = killed). Assumes `configure()` ran at startup — see Installation.

### Top-level switch

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// name; getKillswitch returns true when the switch is on (the guarded path is killed)
let killed = await client.getKillswitch("{{KILLSWITCH_KEY}}")
```

### Named per-key override switch

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// switchKey: read one named override (e.g. per region); an unset key falls back
// to the kill switch's top-level value
let killedEu = await client.getKillswitch("{{KILLSWITCH_KEY}}", switchKey: "eu_region")
```
