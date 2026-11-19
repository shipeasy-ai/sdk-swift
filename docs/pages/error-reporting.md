# Error reporting — `see()`

The Swift SDK ships the full `see()` structured-error surface. Every handled
exception documents its product **consequence**, not just its stack. Reports are
fire-and-forget POSTs; `see()` never blocks or throws into your code, and every
event is tagged with the side `"client"`.

## The chain

`see(error).causesThe(subject).to(outcome, extras:)` — `to(_:extras:)` is the
**terminal**: it builds the wire event and fire-and-forgets the report. Nothing
sends without it.

The package-level `see(_:)` reports against the client built by
`configureClient(...)`:

```swift
do {
    try chargeCard(order)
} catch {
    see(error)
        .causesThe("checkout")
        .to("use cached prices", extras: ["order_id": order.id])
}
```

### Where extras go in the chain

`causesThe(_:)` and `to(_:)` are two halves of one sentence and must stay
adjacent, so fold the extras into the terminal (they merge like a final
`.extras(...)`, later wins on a shared key):

```swift
// PREFERRED — the consequence reads as one sentence:
see(error).causesThe("checkout").to("use cached prices", extras: ["order_id": order.id])
```

`to(_:)` returns `Void`, so extras cannot trail the terminal in Swift. And never
split the sentence with `extras(_:)` — the standalone setter still exists, but
reach for it only when you genuinely cannot pass the context inline:

```swift
// WON'T COMPILE — to(_:) returns Void:
// see(error).causesThe("checkout").to("use cached prices").extras(["order_id": order.id])

// WRONG — extras wedged between the subject and the outcome. You read
// "checkout … order_id … use cached prices" and lose the consequence.
// see(error).causesThe("checkout").extras(["order_id": order.id]).to("use cached prices")
```

If `see()` is called before `configureClient(...)` has run, the error is dropped
(with a note to stderr).

## Linking an app error to the server exception behind it

When a request to your own backend fails, the app's report and the server's
report can be joined so the server exception shows up as the app error's cause.
`correlate(_:)` returns a copy of a `URLRequest` carrying a fresh
`X-SE-Correlation` UUID header (the header the Shipeasy server SDKs read) plus
that token; pass the token to `.correlated(with:)` on the chain and the event
carries `correlation_id`:

```swift
let (request, correlationId) = correlate(URLRequest(url: apiURL.appendingPathComponent("feed")))
do {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FeedError.badStatus }
    feed = try decode(data)
} catch {
    see(error)
        .correlated(with: correlationId)
        .causesThe("feed")
        .to("show the cached feed")
}
```

The SDK does not patch `URLSession` — correlate only the requests you choose, and
only to your own backend (never third-party hosts). One token per request: call
`correlate(_:)` again for each one. A nil or malformed token (anything not
matching `^[A-Za-z0-9-]{8,64}$`) is dropped and the report is sent uncorrelated;
`correlation_id` is omitted unless a valid token was set.

## Non-exception problems — `seeViolation`

Report a problem that isn't an `Error`. The `name` is a **stable fingerprint key**
— put variable data in `.extras()`, never in the name:

```swift
seeViolation("large query")
    .causesThe("search results")
    .to("be trimmed", extras: ["row_count": rows.count])
```

## Expected control flow — reports nothing

`controlFlowException(error).because("...")` marks an exception as *expected* and
reports **nothing** — use it to document a deliberate catch so it isn't mistaken
for an unhandled error. `extras` on the tail is stored for local debugging only,
never transmitted:

```swift
do {
    try parse(token)
} catch {
    controlFlowException(error)
        .because("an expired token is normal — we re-issue below")
        .extras(["path": "/refresh"])
    // …re-issue
}
```

## Private attributes

Keys listed in `privateAttributes` on `configureClient(...)` are **stripped from
`.extras()`** before the report leaves the device (as they are from `track()`
payloads). See [advanced](advanced.md#private-attributes).

## Limits & spam guard

Reports are bounded per process: identical events within a 30s window collapse to
one send, and there's a hard cap on total sends per process. Messages, stacks,
subjects, and extras are truncated; extras are capped at 20 keys and limited to
String / finite-number / Bool values. Swift has no per-throw stack, so the stack
is captured best-effort at report time (it points at the `see()` call site).
`see()` is idempotent — calling `.to(...)` twice on the same chain sends once.
