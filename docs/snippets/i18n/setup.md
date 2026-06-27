The Swift SDK is server-side: it emits the SSR loader tag for the browser SDK
(the public **client** key goes on the i18n tag, never the server key).

```swift
let bootstrap = await client.bootstrapScriptTag(["user_id": "u_123"], anonId: anonId)
let i18n = await client.i18nScriptTag(clientKey, profile: "{{PROFILE}}")
let head = bootstrap + i18n // inject into the document <head>
```
