// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shipeasy",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "Shipeasy", targets: ["Shipeasy"]),
        // Generated OpenAPI admin client (the Shipeasy admin API — flags/experiments/
        // configs/metrics/errors/ops CRUD + reads). URLSession-based, zero external
        // deps, its own module so flags-SDK consumers don't pull it unless they ask.
        // Regenerate with `apps/mobile` → `pnpm gen:clients swift`.
        .library(name: "ShipeasyAdmin", targets: ["ShipeasyAdmin"]),
        // Opt-in CLIs (not part of the library product consumers import):
        //  - shipeasy-skill: install the bundled agent skill into a project.
        //  - gen-readme:     regenerate README.md from docs/ (+ sync the skill).
        .executable(name: "shipeasy-skill", targets: ["shipeasy-skill"]),
        .executable(name: "gen-readme", targets: ["gen-readme"]),
    ],
    targets: [
        .target(name: "Shipeasy"),
        .target(name: "ShipeasyAdmin"),
        .executableTarget(
            name: "shipeasy-skill",
            resources: [.copy("SKILL.md")]
        ),
        .executableTarget(name: "gen-readme"),
        .testTarget(
            name: "ShipeasyTests",
            dependencies: ["Shipeasy"],
            resources: [.copy("Fixtures/eval-vectors.json")]
        ),
    ]
)
