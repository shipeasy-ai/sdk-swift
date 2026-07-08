Check whether the kill switch `{{KILLSWITCH_KEY}}` is engaged (`true` = killed)
from the configured `ShipeasyClient`. Assumes `configureClient(...)` ran at startup
— see Installation.

### Top-level switch

```swift
// name; getKillswitch returns true when the switch is on (the guarded path is killed)
let killed = await shipeasyClient()?.getKillswitch("{{KILLSWITCH_KEY}}") ?? false
```

### Named per-key override switch

```swift
// switchKey: read one named override (e.g. per region); an unset key falls back
// to the kill switch's top-level value
let killedEu = await shipeasyClient()?.getKillswitch("{{KILLSWITCH_KEY}}", switchKey: "eu_region") ?? false
```
