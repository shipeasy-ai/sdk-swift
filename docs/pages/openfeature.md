# OpenFeature

**The Swift SDK does not ship an OpenFeature provider.** There is no `OpenFeature`
module, provider type, or adapter in the package — the source tree contains no
OpenFeature integration (the Swift OpenFeature ecosystem is immature).

Use the native API instead:

```swift
let client = shipeasyClient()!
await client.identify(["user_id": "u_123"])
let enabled = await client.getFlag("new_checkout")
```

`getFlag` (with an optional `default:`) is the interop surface — see
[flags](flags.md). If a Swift OpenFeature provider is something you need, file a
request on [shipeasy-ai/sdk-swift](https://github.com/shipeasy-ai/sdk-swift).
