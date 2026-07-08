// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shipeasy",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        // Native client SDK for shipped Apple apps (iOS / macOS / tvOS / watchOS).
        // Public client key, server-side evaluation over POST /sdk/evaluate,
        // persisted device anonymous_id. See ClientMode.swift.
        .library(name: "Shipeasy", targets: ["Shipeasy"]),
        // Generated OpenAPI admin client (the Shipeasy admin API — flags/experiments/
        // configs/metrics/errors/ops CRUD + reads). URLSession-based, its own module
        // so flags-SDK (`Shipeasy`) consumers don't pull it unless they import it.
        // Depends on AnyCodable (freeform JSON, e.g. connector configs) — that dep is
        // scoped to THIS target only. Regenerate with `apps/mobile` → `pnpm gen:clients swift`.
        .library(name: "ShipeasyAdmin", targets: ["ShipeasyAdmin"]),
        // Opt-in CLIs (not part of the library product consumers import):
        //  - shipeasy-skill: install the bundled agent skill into a project.
        //  - gen-readme:     regenerate README.md from docs/ (+ sync the skill).
        .executable(name: "shipeasy-skill", targets: ["shipeasy-skill"]),
        .executable(name: "gen-readme", targets: ["gen-readme"]),
    ],
    dependencies: [
        // Only ShipeasyAdmin uses it (freeform JSON). The flags `Shipeasy` target
        // links nothing external.
        .package(url: "https://github.com/Flight-School/AnyCodable", .upToNextMajor(from: "0.6.1")),
    ],
    targets: [
        .target(name: "Shipeasy"),
        .target(
            name: "ShipeasyAdmin",
            dependencies: [.product(name: "AnyCodable", package: "AnyCodable")]
        ),
        .executableTarget(
            name: "shipeasy-skill",
            resources: [.copy("SKILL.md")]
        ),
        .executableTarget(name: "gen-readme"),
        .testTarget(
            name: "ShipeasyTests",
            dependencies: ["Shipeasy"]
        ),
    ]
)
