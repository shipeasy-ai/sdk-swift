Track a metric/conversion event from the configured `ShipeasyClient`. Metrics in
the dashboard are computed from these events. Assumes `configureClient(...)` ran at
startup — see Installation.

### Track an event

```swift
// track(event, properties:)
//   event       — the event your metric is built on (required)
//   properties: — optional payload; numeric/string fields you can sum/filter on
//                 in a metric (private attributes are stripped before egress)
await shipeasyClient()?.track("{{EVENT_NAME}}", properties: ["amount": 49, "currency": "usd"])
```

Fire-and-forget (never blocks). The unit is the identified user (`user_id`, else
the persisted `anonymous_id`), attached automatically.

### Track without properties

```swift
await shipeasyClient()?.track("{{EVENT_NAME}}")   // properties default to [:]
```
