# Error reporting — `see()`

The Swift SDK ships the full `see()` structured-error surface. Every handled
exception documents its product **consequence**, not just its stack. Reports are
fire-and-forget POSTs; `see()` never blocks or throws into your code, and every
event is tagged with the side `"client"`.

## The chain

`see(error).causesThe(subject).to(outcome)` — `to(_:)` is the **terminal**: it
builds the wire event and fire-and-forgets the report. Nothing sends without it.
`causesThe(_:)` and `extras(_:)` are chainable setters callable in any order
*before* `to(_:)`.

The package-level `see(_:)` reports against the client built by
`configureClient(...)`:

```swift
do {
    try chargeCard(order)
} catch {
    see(error)
        .causesThe("checkout")
        .extras(["order_id": order.id])
        .to("use cached prices")
}
```

You can also fold the extras into the terminal as `to(_:extras:)`, so there is no
ordering to remember — the inline extras merge like a final `.extras(...)` (later
wins on a shared key):

```swift
see(error).causesThe("checkout").to("use cached prices", extras: ["order_id": order.id])
```

If `see()` is called before `configureClient(...)` has run, the error is dropped
(with a note to stderr).

## Non-exception problems — `seeViolation`

Report a problem that isn't an `Error`. The `name` is a **stable fingerprint key**
— put variable data in `.extras()`, never in the name:

```swift
seeViolation("large query")
    .causesThe("search results")
    .extras(["row_count": rows.count])
    .to("be trimmed")
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
