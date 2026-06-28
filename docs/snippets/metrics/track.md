Track a metric/conversion event from the bound `Client`. Metrics in the dashboard
are computed from these events. Assumes `configure()` ran at startup — see
Installation.

### Track an event

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

// track(event, properties:)
//   event       — the event your metric is built on (required)
//   properties: — optional payload; numeric/string fields you can sum/filter on
//                 in a metric (private attributes are stripped before egress)
await client.track("{{EVENT_NAME}}", properties: ["amount": 49, "currency": "usd"])
```

Fire-and-forget (never blocks your response) and a no-op under
`configureForTesting` / `configureForOffline`. The unit is the bound user
(`user_id`, else `anonymous_id`); with no unit the call is a no-op.

### Track without properties

```swift
// construct once per callsite (cheap; binds the user)
let client = try Client(["user_id": "u_123"])

await client.track("{{EVENT_NAME}}")   // properties default to [:]
```
