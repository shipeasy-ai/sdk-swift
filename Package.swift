// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shipeasy",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "Shipeasy", targets: ["Shipeasy"]),
        // Opt-in CLIs (not part of the library product consumers import):
        //  - shipeasy-skill: install the bundled agent skill into a project.
        //  - gen-readme:     regenerate README.md from docs/ (+ sync the skill).
        .executable(name: "shipeasy-skill", targets: ["shipeasy-skill"]),
        .executable(name: "gen-readme", targets: ["gen-readme"]),
    ],
    targets: [
        .target(name: "Shipeasy"),
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
