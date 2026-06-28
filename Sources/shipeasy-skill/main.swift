// shipeasy-skill — install the bundled Shipeasy agent skill into a project.
//
//     swift run shipeasy-skill install                 # -> .claude/skills/shipeasy-swift/SKILL.md
//     swift run shipeasy-skill install --dir path/     # custom destination (file or dir)
//     swift run shipeasy-skill install --force         # overwrite an existing file
//     swift run shipeasy-skill print                   # write the skill to stdout
//
// The skill (SKILL.md) is bundled as a SwiftPM resource, kept in sync with the
// canonical docs/skill/SKILL.md by `swift run gen-readme`.
import Foundation

let defaultDest = ".claude/skills/shipeasy-swift/SKILL.md"

func skillText() -> String {
    if let url = Bundle.module.url(forResource: "SKILL", withExtension: "md"),
       let s = try? String(contentsOf: url, encoding: .utf8) {
        return s
    }
    FileHandle.standardError.write("shipeasy-skill: bundled SKILL.md not found.\n".data(using: .utf8)!)
    exit(1)
}

func err(_ s: String) { FileHandle.standardError.write(s.data(using: .utf8)!) }

func install(_ dir: String, force: Bool) -> Int32 {
    let fm = FileManager.default
    var dest = dir
    var isDir: ObjCBool = false
    let exists = fm.fileExists(atPath: dest, isDirectory: &isDir)
    if (exists && isDir.boolValue) || (dir as NSString).pathExtension.isEmpty {
        dest = (dir as NSString).appendingPathComponent("SKILL.md")
    }
    if fm.fileExists(atPath: dest) && !force {
        err("shipeasy-skill: refusing to overwrite \(dest) — pass --force\n")
        return 1
    }
    let parent = (dest as NSString).deletingLastPathComponent
    if !parent.isEmpty {
        try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
    }
    do {
        try skillText().write(toFile: dest, atomically: true, encoding: .utf8)
    } catch {
        err("shipeasy-skill: \(error)\n")
        return 1
    }
    print("shipeasy-skill: installed the Shipeasy agent skill → \(dest)")
    return 0
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "print":
    print(skillText())
case "install":
    var dir = defaultDest
    var force = false
    var i = 1
    while i < args.count {
        if args[i] == "--force" { force = true }
        else if args[i] == "--dir", i + 1 < args.count { i += 1; dir = args[i] }
        i += 1
    }
    exit(install(dir, force: force))
default:
    print("""
    shipeasy-skill — install the Shipeasy agent skill.

      shipeasy-skill install [--dir <path>] [--force]
      shipeasy-skill print
    """)
    exit(args.first == nil || args.first == "--help" || args.first == "-h" ? 0 : 1)
}
