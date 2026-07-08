Assign the device user within the `{{EXPERIMENT_KEY}}` universe (a mutual-exclusion
pool → ≤1 experiment), branch on the group, and track the conversion event — all
from the configured `ShipeasyClient`. Assumes `configureClient(...)` ran at startup
— see Installation.

```swift
let client = shipeasyClient()!   // configured once at app launch

// universe name; assign() auto-logs one exposure when enrolled
let a = await client.universe("{{EXPERIMENT_KEY}}").assign()

if a.enrolled, a.group == "treatment" {
    // get(field, fallback): variant override ?? universe default ?? fallback
    let color = a.get("button_color", "blue")
    // render the treatment variant
}

// conversion event — the unit is the identified user (no id argument);
// event name; optional `properties:` bag (default [:])
await client.track("{{SUCCESS_EVENT}}", properties: ["amount": 49])
```
