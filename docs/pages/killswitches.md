# Kill switches

A kill switch reports whether a panic/disable switch is engaged. It returns a
`Bool` — `true` means the switch is **on** (the thing it guards is killed). Kill
switches are not user-scoped; they are forwarded straight to the engine.

## Bound `Client` form

```swift
let client = try Client(["user_id": "u_123"])
let killed = await client.getKillswitch("panic_button")
if killed {
    // short-circuit the guarded path
}
```

## Named override switches

A kill switch can carry named per-key override switches (the dashboard
"switches" feature). Pass `switchKey:` to read one named switch:

```swift
let killed = await client.getKillswitch("panic_button", switchKey: "eu_region")
```

## Engine (low-level) form

```swift
let engine = globalEngine()!
let killed = await engine.getKillswitch("panic_button")
let killedEu = await engine.getKillswitch("panic_button", switchKey: "eu_region")
```
