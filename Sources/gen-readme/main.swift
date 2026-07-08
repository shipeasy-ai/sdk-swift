// Regenerate README.md from the docs in docs/ and keep the embedded agent skill
// (Sources/shipeasy-skill/SKILL.md) in sync with docs/skill/SKILL.md. The docs
// are the single source of truth.
//
//     swift run gen-readme
//
// CI (.github/workflows/tests.yml) re-runs it and `git diff --exit-code`s the
// result to catch drift. Idempotent. Run from the package root (CWD).
import Foundation

let owner = "shipeasy-ai"
let repo = "sdk-swift"
let blob = "https://github.com/\(owner)/\(repo)/blob/main"
let pagesSite = "https://\(owner).github.io/\(repo)"

let pageOrder = [
    "overview", "installation", "configuration", "flags", "configs",
    "killswitches", "experiments", "i18n", "error-reporting", "testing",
    "openfeature", "advanced",
]
let pageTitle: [String: String] = [
    "overview": "Overview", "installation": "Installation", "configuration": "Configuration",
    "flags": "Feature flags", "configs": "Dynamic configs", "killswitches": "Kill switches",
    "experiments": "Experiments", "i18n": "Internationalization", "error-reporting": "Error reporting",
    "testing": "Testing", "openfeature": "OpenFeature", "advanced": "Advanced",
]
let pageBlurb: [String: String] = [
    "overview": "The `configureClient()` + `ShipeasyClient` model.",
    "installation": "Install (SwiftPM), where to call `configureClient()`, custom `AnonymousStore`.",
    "configuration": "`configureClient()` key, options, the persisted anon id.",
    "flags": "`getFlag`, defaults, cached reads.",
    "configs": "`getConfig`, typed reads, defaults.",
    "killswitches": "`getKillswitch`, named switches.",
    "experiments": "`getExperiment`, `logExposure`, `track`.",
    "i18n": "Not part of the native client SDK.",
    "error-reporting": "`see()` structured error reporting.",
    "testing": "Hermetic tests: inject an `AnonymousStore` + transport stub.",
    "openfeature": "OpenFeature interop notes.",
    "advanced": "Anon-id persistence, private attributes, `refreshAssignments`.",
]

let fm = FileManager.default
let root = fm.currentDirectoryPath
let docs = root + "/docs"

func read(_ rel: String) -> String {
    (try? String(contentsOfFile: docs + "/" + rel, encoding: .utf8)) ?? ""
}

func firstCode(_ md: String, _ lang: String) -> String {
    guard let start = md.range(of: "```\(lang)\n") else { return "" }
    let rest = md[start.upperBound...]
    guard let end = rest.range(of: "```") else { return "" }
    return String(rest[rest.startIndex..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
}

func leadParagraph(_ md: String) -> String {
    var out: [String] = []
    var started = false
    for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if !started { started = line.hasPrefix("# "); continue }
        let s = line.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { if !out.isEmpty { break }; continue }
        if let f = s.first, "#`>|-<".contains(f) { if !out.isEmpty { break }; continue }
        out.append(s)
    }
    return out.joined(separator: " ").replacingOccurrences(of: "  ", with: " ")
}

func absolutize(_ text: String) -> String {
    // Rewrite relative `](page.md)` links to absolute GitHub blob URLs. Absolute
    // http(s)/root links are left as-is.
    guard let re = try? NSRegularExpression(pattern: "\\]\\(([\\w./-]+?\\.md)(#[\\w-]+)?\\)") else { return text }
    let ns = text as NSString
    var result = text
    let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
    for m in matches {
        let path = ns.substring(with: m.range(at: 1))
        if path.hasPrefix("/") { continue }
        let frag = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
        let replacement = "](\(blob)/docs/pages/\(path)\(frag))"
        result = (result as NSString).replacingCharacters(in: m.range, with: replacement)
    }
    return result
}

guard let manifestData = read("manifest.json").data(using: .utf8),
      let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
      let sdk = manifest["sdk"] as? String,
      let skillRel = manifest["skill"] as? String
else {
    FileHandle.standardError.write("gen-readme: cannot read docs/manifest.json\n".data(using: .utf8)!)
    exit(1)
}

let install = { () -> String in
    let c = firstCode(read("pages/installation.md"), "bash")
    return c.isEmpty ? ".package(url: \"https://github.com/\(owner)/\(repo)\", from: \"1.0.0\")" : c
}()
let quickstart = firstCode(read("pages/overview.md"), "swift")
let testingMd = read("pages/testing.md")
let testingLead = absolutize(leadParagraph(testingMd))
let testingCode = firstCode(testingMd, "swift")

var rows: [String] = []
for key in pageOrder {
    let title = pageTitle[key] ?? key
    var blurb = pageBlurb[key] ?? ""
    if blurb.count > 90 { blurb = String(blurb.prefix(87)).trimmingCharacters(in: .whitespaces) + "…" }
    rows.append("| [\(title)](\(blob)/docs/pages/\(key).md) | \(blurb) |")
}
let docsTable = rows.joined(separator: "\n")

let readme = """
<!--
  This file is GENERATED by Sources/gen-readme from docs/.
  Do NOT edit by hand — edit the docs, then run: swift run gen-readme
-->

# Shipeasy (Swift)

[![Tests](https://github.com/\(owner)/\(repo)/actions/workflows/tests.yml/badge.svg)](https://github.com/\(owner)/\(repo)/actions/workflows/tests.yml)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Linux-lightgrey.svg)](https://github.com/\(owner)/\(repo))

Native **client** SDK for [Shipeasy](https://shipeasy.ai) — **feature flags,
dynamic configs, kill switches, A/B experiments, and metric tracking** for shipped
**iOS / macOS / tvOS / watchOS** apps. Configure once with your **public client
key** (`pk_…`, safe to embed); `ShipeasyClient` evaluates the device user
server-side over `POST /sdk/evaluate`, caches the assignments for cheap local
reads, and **persists the device `anonymous_id` across launches** so a logged-out
user buckets identically on every cold start.

> 📚 **Full documentation:** **<\(pagesSite)/>** — also browsable under
> [`docs/`](\(blob)/docs). This README is generated from those docs.

## 🤖 Using an AI agent?

This SDK ships an installable **agent skill** — a copy-paste-ready guide to
`configureClient()` + `ShipeasyClient`, experiments, error reporting, testing, and
more, with links the agent can pull for deeper docs:

- **Skill:** [`docs/skill/SKILL.md`](\(blob)/docs/skill/SKILL.md) · raw:
  `\(pagesSite)/skill/SKILL.md`
- **Install it** (ships with the package — no network):
  `swift run shipeasy-skill install` → `.claude/skills/shipeasy-\(sdk)/SKILL.md`
  (or via the Shipeasy CLI: `shipeasy docs skill --sdk \(sdk) --install`)

**Humans:** you can copy that skill straight into your own project's agent skills
directory so your coding agent always uses the correct Shipeasy patterns. Every
doc page and snippet is also fetchable by URL — start from the manifest at
`\(pagesSite)/manifest.json`.

## Install

```bash
\(install)
```

Where to call `configureClient()` (App / `@main` / SceneDelegate) and how to plug
in a custom `AnonymousStore` (Keychain / app group / tests) is on the
[Installation](\(blob)/docs/pages/installation.md) page.

## Quickstart — `configureClient()` once, then read from `ShipeasyClient`

```swift
\(quickstart)
```

Reads serve the cached assignments (no per-call network) — configure once at
launch, then `await shipeasyClient()?.getFlag(...)` anywhere.

## Documentation

| Page | What |
| --- | --- |
\(docsTable)

Copy-paste snippets live under [`docs/snippets/`](\(blob)/docs/snippets)
(release · metrics · i18n · ops); an installable agent skill is at
[`docs/skill/SKILL.md`](\(blob)/docs/skill/SKILL.md).

## Testing

\(testingLead)

```swift
\(testingCode)
```

More — the in-memory `AnonymousStore` and transport-stub pattern for hermetic
tests — on the [Testing](\(blob)/docs/pages/testing.md) page.

## License

See [LICENSE](\(blob)/LICENSE).

"""

try! readme.write(toFile: root + "/README.md", atomically: true, encoding: .utf8)

// Keep the embedded agent skill (read by shipeasy-skill via Bundle.module) in
// sync with the canonical docs/skill/SKILL.md.
let skill = read(skillRel)
try! skill.write(toFile: root + "/Sources/shipeasy-skill/SKILL.md", atomically: true, encoding: .utf8)

print("Wrote README.md (\(readme.count) chars) + synced Sources/shipeasy-skill/SKILL.md from \(pageOrder.count) doc pages.")
