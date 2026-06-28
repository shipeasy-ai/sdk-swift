The Swift SDK is server-side: it emits the SSR loader tag for the browser SDK
(the public **client** key goes on the i18n tag, never the server key). The
script-tag helpers are package-level functions (no Engine needed). Assumes
`configure()` ran at startup — see Installation.

```swift
// bootstrapScriptTag: user attribute map; anonId: stable __se_anon_id unit (no key);
// optional i18nProfile: locale profile ("en:prod"); optional baseURL: CDN host
let bootstrap = await bootstrapScriptTag(["user_id": "u_123"], anonId: anonId)

// i18nScriptTag: PUBLIC clientKey (positional); profile: locale profile ("en:prod" default);
// optional baseURL: CDN host (defaults to https://cdn.shipeasy.ai)
let i18n = await i18nScriptTag(clientKey, profile: "{{PROFILE}}")

let head = bootstrap + i18n // inject into the document <head>
```
