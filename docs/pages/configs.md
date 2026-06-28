# Dynamic configs

A dynamic config is a typed JSON value (string, number, bool, array, or object)
fetched by name. Configs are **not** user-scoped — they resolve the same for any
bound user.

```swift
let client = try Client(["user_id": "u_123"])
let copy = await client.getConfig("billing_copy")
// copy is `Any?` — cast to your expected shape:
let headline = (copy as? [String: Any])?["headline"] as? String
```

`getConfig` returns `nil` when the key is absent (or the rules aren't ready).

## Default value

Pass `default` to get a value back when the config key is absent:

```swift
let copy = await client.getConfig("billing_copy", default: ["headline": "Welcome"])
```

Because the returned value is `Any?`, cast it to the shape your config defines.
