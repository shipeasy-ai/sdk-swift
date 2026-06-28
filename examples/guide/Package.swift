// swift-tools-version:6.0
import PackageDescription

// Secondary path. The PRIMARY runnable path is XcodeGen:
//   brew install xcodegen && xcodegen generate && open Guide.xcodeproj
//
// This manifest exists so `swift build` can type-check the SwiftUI sources from
// the command line. SwiftPM does not produce a bundled, double-clickable iOS
// app — use the XcodeGen-generated Guide.xcodeproj to actually Run on a device
// or simulator.
let package = Package(
    name: "Guide",
    // tools-version is 6.0 so SwiftPM auto-wires swift-testing (`import Testing`),
    // but the sources stay in the Swift 5 language mode (see swiftLanguageModes
    // below) — they predate Swift 6 strict concurrency and the SDK's `getConfig`
    // returns a non-Sendable `Any?`.
    platforms: [.macOS(.v13), .iOS(.v16)],
    dependencies: [
        // The Shipeasy Swift SDK lives two levels up (examples/guide → sdk-swift).
        // The test target uses Engine.forTesting() to mock every value.
        .package(path: "../..")
    ],
    targets: [
        // For the COMMAND-LINE (`swift build` / `swift test`) path we compile only
        // the data layer the test needs — `Entity.swift` + `Theme.swift`. The
        // SwiftUI app shell (`ContentView.swift`, `GuideApp.swift`) is excluded
        // here because it uses the `#Preview` macro and `@main`, whose macro
        // plugin (`PreviewsMacros`) and app entry point ship only with full
        // Xcode — the command-line toolchain cannot compile them at all, so
        // excluding them repairs `swift build`/`swift test` rather than losing
        // coverage. The PRIMARY runnable path is still XcodeGen
        // (`xcodegen generate`), which builds the complete app from every file
        // in `Guide/`.
        .target(
            name: "Guide",
            path: "Guide",
            exclude: ["Assets.xcassets", "ContentView.swift", "GuideApp.swift"]
        ),
        // XCTest target: builds the entity data the view renders and asserts it
        // contains every value mocked via the SDK testing setup. `@testable
        // import Guide` reaches the example's `Entity` type without restructuring
        // the app.
        .testTarget(
            name: "GuideTests",
            dependencies: [
                "Guide",
                .product(name: "Shipeasy", package: "sdk-swift"),
            ],
            path: "Tests/GuideTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
