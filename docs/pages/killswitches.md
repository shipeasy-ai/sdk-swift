# Kill switches

A kill switch reports whether a panic/disable switch is engaged. It returns a
`Bool` — `true` means the switch is **on** (the thing it guards is killed). Kill
switches are not user-scoped; they resolve the same for any bound user.

```swift
let client = try Client(["user_id": "u_123"])
let killed = await client.getKillswitch("panic_button")
if killed {
    // short-circuit the guarded path
}
```

## Named override switches

A kill switch can carry **named per-key override switches** (the dashboard
"switches" feature) — e.g. one switch per region. Pass `switchKey:` to read a
named switch:

```swift
let killedEu = await client.getKillswitch("panic_button", switchKey: "eu_region")
```

When the named key has no explicit override configured, the result **falls back
to the kill switch's top-level value** — so a key you haven't set behaves exactly
like the un-keyed `getKillswitch("panic_button")` call.
