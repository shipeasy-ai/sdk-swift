# Shipeasy · Swift Entity Guide

A runnable, single-screen SwiftUI app that reads like a "big guide document":
one styled card per Shipeasy entity — feature flag, dynamic config, A/B
experiment, kill switch, event/metric, i18n label, and `see()` error reporting.
Open it in Xcode and **Run it on your iPhone or your Mac**.

It makes **zero network calls** and needs no external services.

## ⚠ SDK not wired yet

This example does **not** depend on the Shipeasy Swift package, and it does
**not** `import Shipeasy`. Every value on every card is a hardcoded placeholder
Swift constant. For each entity the card shows the *real* SDK call both as a
visible monospace code block and as a `// TODO: once the Shipeasy Swift package
is installed` comment in the source (`Guide/Entity.swift`). Add the package and
replace each `// TODO` to make the values live.

## Run it

The primary runnable path generates a real Xcode project with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen      # one-time
xcodegen generate          # reads project.yml → writes Guide.xcodeproj
open Guide.xcodeproj
```

Then in Xcode pick a run destination from the toolbar — an **iOS Simulator**,
**your iPhone**, or **My Mac** — and press **Run** (⌘R). The app is a single
multiplatform target, so the same target runs on both iOS and macOS.

## Project layout

```
examples/guide/
├── project.yml              # XcodeGen spec — app target "Guide" (iOS 16 / macOS 13), bundle id ai.shipeasy.guide
├── Package.swift            # optional SwiftPM manifest (secondary path; XcodeGen is primary)
├── README.md
├── .gitignore               # ignores generated *.xcodeproj/, .build/, DerivedData
└── Guide/
    ├── GuideApp.swift       # @main App entry
    ├── ContentView.swift    # the ScrollView guide: hero, banner, cards, footer
    ├── Entity.swift         # the entity model + the placeholder data array (the // TODOs live here)
    ├── Theme.swift          # Color(hex:) helper + the dark-brand palette
    └── Assets.xcassets/     # AppIcon + AccentColor placeholders
```

## Tests

`Tests/GuideTests/GuideEntitiesTest.swift` mocks every value the SDK returns via
the testing setup (`Engine.forTesting()` + `override*`) and asserts the rendered
card data (`Entity.all`) contains each mocked value. The value assertions are
**expected to fail** until `Entity.swift` is wired to the SDK (the cards are
still hardcoded placeholders); the SDK-read-back case always passes.

It uses **swift-testing** (`import Testing`) instead of XCTest so it runs from the
command line without full Xcode (macOS XCTest ships only with Xcode):

```sh
# one-time: a toolchain that bundles swift-testing (no sudo)
brew install swiftly && swiftly init --assume-yes && swiftly install latest --assume-yes

swift test            # uses the swiftly toolchain once its env is on PATH
```

The command-line `Package.swift` build compiles only the data layer
(`Entity.swift` + `Theme.swift`); the SwiftUI app shell uses the `#Preview` macro,
which requires full Xcode. The complete app still builds via XcodeGen.

## Next step: go live

1. Add the Shipeasy Swift package as a dependency (Swift Package Manager:
   `https://github.com/shipeasy-ai/sdk-swift`).
2. In `Guide/Entity.swift`, `import Shipeasy`, construct a client, and replace
   each `// TODO: once the Shipeasy Swift package is installed` block by calling
   the SDK and feeding the result into the card's `value`.
3. Remove the placeholder banner from `ContentView.swift`.

Docs: https://docs.shipeasy.ai
