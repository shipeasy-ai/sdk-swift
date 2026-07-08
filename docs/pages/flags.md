# Flags

A flag (a.k.a. *gate*) evaluates to a `Bool` for the identified device user.
Reads are served from the local cache of the last `/sdk/evaluate` response — no
per-call network, safe from any thread.

```swift
let client = shipeasyClient()!
await client.identify(["user_id": "u_123", "plan": "pro"])
let enabled = await client.getFlag("new_checkout")
```

`getFlag` returns the supplied `default` when the assignments aren't loaded yet
(before the first `identify`/evaluate, or after a failed evaluate) or the gate is
absent.

## Default / fallback behaviour

`getFlag` takes an optional `default` (defaults to `false`) returned **only when
the value cannot be evaluated** (assignments not loaded, or the gate doesn't
exist) — never when the gate simply evaluates to `false`:

```swift
let on = await client.getFlag("new_checkout", default: true)
```

A flag that exists and evaluates to `false` still returns `false`; the default is
purely a "can't decide yet" fallback.

## Picking up a change

To re-evaluate for the current user (e.g. after you publish a flag), call
`refreshAssignments()` and read again:

```swift
await client.refreshAssignments()
let on = await client.getFlag("new_checkout")
```
