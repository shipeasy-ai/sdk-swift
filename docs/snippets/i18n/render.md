Rendering a translated label is **client-side** — the Swift server SDK has no
`t()`. After the loader from `i18nScriptTag(...)` hydrates the `{{PROFILE}}`
profile, render in the browser with the client SDK:

```ts
// browser (@shipeasy/sdk client) — NOT Swift
import { t } from "@shipeasy/sdk/client";
t("checkout.cta"); // -> the translated string
```
