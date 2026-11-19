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

### Attach context inline on `.to(_:extras:)`

```swift
do {
    try charge(order)
} catch {
    // .to(outcome, extras:) PREFERRED: terminal + extras in one call (private
    //                       attributes are stripped before egress). The
    //                       consequence sentence stays whole and there is no
    //                       ordering to remember.
    see(error).causesThe("checkout").to("use cached prices", extras: ["order_id": orderId])

    // .to returns Void, so extras cannot trail the terminal in Swift.

    // NEVER: extras wedged between the subject and the outcome — it splits the
    // consequence sentence in half and is hard to read.
    // see(error).causesThe("checkout").extras(["order_id": orderId]).to("use cached prices")
}
```

### Link an app error to the server exception behind it

```swift
// correlate(_:) adds a fresh X-SE-Correlation header (read by the server SDKs)
// and returns the token; .correlated(with:) puts it on the report as
// correlation_id so the backend exception is recorded as this error's cause.
let (request, correlationId) = correlate(URLRequest(url: feedURL))
do {
    let (data, _) = try await URLSession.shared.data(for: request)
    feed = try decode(data)
} catch {
    see(error).correlated(with: correlationId).causesThe("feed").to("show the cached feed")
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
