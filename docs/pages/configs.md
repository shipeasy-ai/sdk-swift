# Dynamic configs

A dynamic config is a typed JSON value (string, number, bool, array, or object)
fetched by name from the cached `/sdk/evaluate` response.

```swift
let client = shipeasyClient()!
await client.identify(["user_id": "u_123"])

let copy = await client.getConfig("billing_copy")
// copy is `Any?` — cast to your expected shape:
let headline = (copy as? [String: Any])?["headline"] as? String
```

`getConfig` returns `nil` when the key is absent (or the assignments aren't
loaded yet).

## Default value

Pass `default` to get a value back when the config key is absent:

```swift
let copy = await client.getConfig("billing_copy", default: ["headline": "Welcome"])
```

## Typed reads

Because the returned value is `Any?`, cast it with `as?` to the shape your config
defines:

```swift
let maxItems = (await client.getConfig("cart_limit")) as? Int ?? 10
let banner   = (await client.getConfig("banner_text")) as? String
let theme    = (await client.getConfig("theme")) as? [String: Any]
let accent   = theme?["accent"] as? String
```
