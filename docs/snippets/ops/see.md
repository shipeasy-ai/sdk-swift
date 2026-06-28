Report a caught, handled error (or a non-exception "violation") to Shipeasy with
`see()` — fire-and-forget, never re-throws. Package-level, so it reports against
the configuration from `configure()`. Assumes `configure()` ran at startup — see
Installation.

### Report a handled exception

```swift
do {
    try charge(order)
} catch {
    // .causesThe(subject)   what the error affects (e.g. "checkout")
    // .to(outcome)          the terminal — what you do about it; builds + fires once
    see(error).causesThe("checkout").to("use the backup processor")
    try? fallbackCharge(order)
}
```

### Attach context with `.extras(...)`

```swift
do {
    try charge(order)
} catch {
    // .extras(dict)         structured fields attached to the report
    see(error).causesThe("checkout").extras(["order_id": orderId]).to("use cached prices")
}
```

### Report a non-exception violation

```swift
// a bad state that isn't an exception — the name is a STABLE fingerprint; put
// variable data in .extras, never the name. .to() is the terminal.
seeViolation("missing_invoice").causesThe("billing").to("skip the dunning email")
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
