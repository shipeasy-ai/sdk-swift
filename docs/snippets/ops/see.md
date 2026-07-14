Report a caught, handled error (or a non-exception "violation") to Shipeasy with
`see()` — fire-and-forget, never re-throws, tagged with the side `"client"`.
Package-level, so it reports against the client from `configureClient(...)`. Assumes
`configureClient(...)` ran at startup — see Installation.

### Report a handled exception

```swift
do {
    try charge(order)
} catch {
    // .causesThe(subject)   what the error affects (e.g. "checkout")
    // .to(outcome)          the terminal — what you do about it; builds + fires once
    see(error).causesThe("checkout").to("use cached prices")
    try? fallbackCharge(order)
}
```

### Attach context with `.extras(...)`

```swift
do {
    try charge(order)
} catch {
    // .extras(dict)         structured fields attached to the report; call it
    //                       BEFORE .to, or pass inline as .to(outcome, extras:).
    //                       (private attributes are stripped before egress)
    see(error).causesThe("checkout").extras(["order_id": orderId]).to("use cached prices")

    // equivalent — extras folded into the terminal, no ordering to remember:
    see(error).causesThe("checkout").to("use cached prices", extras: ["order_id": orderId])
}
```

### Report a non-exception violation

```swift
// a bad state that isn't an exception — the name is a STABLE fingerprint; put
// variable data in .extras, never the name. .to() is the terminal.
seeViolation("large query").causesThe("search results").to("be trimmed")
```

### Mark an expected exception — report NOTHING

```swift
do {
    try parse(token)
} catch {
    // transmits nothing; .because(...) / .extras() are local-debug only
    controlFlowException(error).because("end of stream is expected")
}
```
