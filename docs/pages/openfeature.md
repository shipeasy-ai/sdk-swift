# OpenFeature

**The Swift SDK does not ship an OpenFeature provider.** There is no
`OpenFeature` module, provider type, or adapter in the package — the source tree
contains no OpenFeature integration.

Use the native API instead:

```swift
let client = try Client(["user_id": "u_123"])
let enabled = await client.getFlag("new_checkout")
let detail  = await client.getFlagDetail("new_checkout") // .value + .reason
```

If you need an evaluation reason (the OpenFeature `reason` field equivalent),
`getFlagDetail` returns both the value and the resolution reason — see
[flags](flags.md). If a Swift OpenFeature provider is something you need, file a
request on [shipeasy-ai/sdk-swift](https://github.com/shipeasy-ai/sdk-swift).
