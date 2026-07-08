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
    "overview": "The `configure()` + `Client(user)` model.",
    "installation": "Install (SwiftPM), Vapor / Hummingbird, `configure()` wiring.",
    "configuration": "Keys, `attributes`, one-shot vs poll, every option.",
    "flags": "`getFlag`, `getFlagDetail`, defaults.",
    "configs": "`getConfig`, typed reads, defaults.",
    "killswitches": "`getKillswitch`, named switches.",
    "experiments": "`getExperiment`, `logExposure`, `track`.",
    "i18n": "SSR bootstrap + i18n loader tags.",
    "error-reporting": "`see()` structured error reporting.",
    "testing": "`configureForTesting` / `configureForOffline`, overrides.",
    "openfeature": "OpenFeature interop notes.",
    "advanced": "Anon-id, private attributes, sticky bucketing, SSR.",
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
    return c.isEmpty ? ".package(url: \"https://github.com/\(owner)/\(repo)\", from: \"0.10.0\")" : c
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

SDK for [Shipeasy](https://shipeasy.ai) — **feature flags, dynamic configs, kill
switches, A/B experiments, and metric tracking** for Swift. Two front doors:
`configure()` + `Client(user)` on a **server** (server key), and
`configureClient()` + `ShipeasyClient` in a **shipped iOS/macOS app** (public
client key, persisted device anon id). Never embed a server key in an app bundle.

> 📚 **Full documentation:** **<\(pagesSite)/>** — also browsable under
> [`docs/`](\(blob)/docs). This README is generated from those docs.

## 🤖 Using an AI agent?

This SDK ships an installable **agent skill** — a copy-paste-ready guide to
`configure()` + `Client(user)`, testing, experiments, error reporting, and more,
with links the agent can pull for deeper docs:

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

Per-framework setup (Vapor / Hummingbird) is on the
[Installation](\(blob)/docs/pages/installation.md) page.

## Quickstart — `configure()` once, then `Client(user)` per request

```swift
\(quickstart)
```

Constructing `Client(user)` before `configure()` throws.

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

More — the on-the-spot override helpers and a working example snapshot file — on
the [Testing](\(blob)/docs/pages/testing.md) page.

## License

See [LICENSE](\(blob)/LICENSE). Evaluation is tested against the cross-language
MurmurHash3 vectors in `experiment-platform/04-evaluation.md`.

"""

try! readme.write(toFile: root + "/README.md", atomically: true, encoding: .utf8)

// Keep the embedded agent skill (read by shipeasy-skill via Bundle.module) in
// sync with the canonical docs/skill/SKILL.md.
let skill = read(skillRel)
try! skill.write(toFile: root + "/Sources/shipeasy-skill/SKILL.md", atomically: true, encoding: .utf8)

print("Wrote README.md (\(readme.count) chars) + synced Sources/shipeasy-skill/SKILL.md from \(pageOrder.count) doc pages.")
