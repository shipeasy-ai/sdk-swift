# Flags

A flag (a.k.a. *gate*) evaluates to a `Bool` for the bound user.

## Bound `Client` form

```swift
let client = try Client(["user_id": "u_123", "plan": "pro"])
let enabled = await client.getFlag("new_checkout")
```

`getFlag` returns `false` when the engine isn't ready or the gate is absent.

## Engine (low-level) form

The bound `Client` delegates to `Engine.getFlag(_:user:)`, which takes the
attribute map explicitly:

```swift
let engine = globalEngine()!
let enabled = await engine.getFlag("new_checkout", user: ["user_id": "u_123"])
```

## Default / fallback behaviour

`getFlag` takes an optional `default` returned **only when the value cannot be
evaluated** (engine not ready, or the gate doesn't exist) — never when the gate
simply evaluates to `false`:

```swift
// Bound form
let on = await client.getFlag("new_checkout", default: true)

// Engine form
let on2 = await engine.getFlag("new_checkout", user: ["user_id": "u_123"], default: true)
```

A flag that exists and evaluates to `false` still returns `false`; the default
is purely a "can't decide yet" fallback.

## Evaluation detail

`getFlagDetail` returns both the value and the reason it resolved that way —
useful for debugging targeting and rollout. `getFlag` is `getFlagDetail().value`.

```swift
let d = await client.getFlagDetail("new_checkout")
// d.value  -> Bool
// d.reason -> one of the FlagReason raw values (String)
```

| Reason             | Meaning                                              |
| ------------------ | ---------------------------------------------------- |
| `OVERRIDE`         | A local `overrideFlag` supplied the value            |
| `CLIENT_NOT_READY` | No live blob yet (client hasn't fetched)             |
| `FLAG_NOT_FOUND`   | The gate name isn't in the flags blob                |
| `OFF`              | The gate exists but is disabled / killed             |
| `RULE_MATCH`       | The gate evaluated to `true` (rules + rollout match) |
| `DEFAULT`          | The gate evaluated to `false` (not targeted)         |

The Engine form is `engine.getFlagDetail(_:user:)`.
