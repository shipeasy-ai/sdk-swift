import Foundation

public struct ExperimentResult: Sendable {
    public let inExperiment: Bool
    public let group: String
    public let params: Any?
}

enum Eval {
    static let notIn = ExperimentResult(inExperiment: false, group: "control", params: nil)

    static func enabled(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i == 1 }
        if let d = v as? Double { return d == 1 }
        return false
    }

    static func toNum(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func userId(_ user: [String: Any]) -> String? {
        if let v = user["user_id"] { return "\(v)" }
        if let v = user["anonymous_id"] { return "\(v)" }
        return nil
    }

    static func matchRule(_ rule: [String: Any], _ user: [String: Any]) -> Bool {
        guard let attr = rule["attr"] as? String, let op = rule["op"] as? String else { return false }
        let value = rule["value"]
        let actual = user[attr]

        switch op {
        case "eq": return equal(actual, value)
        case "neq": return !equal(actual, value)
        case "in":
            guard let arr = value as? [Any] else { return false }
            return arr.contains { equal($0, actual) }
        case "not_in":
            guard let arr = value as? [Any] else { return true }
            return !arr.contains { equal($0, actual) }
        case "contains":
            if let a = actual as? String, let v = value as? String { return a.contains(v) }
            if let arr = actual as? [Any] { return arr.contains { equal($0, value) } }
            return false
        case "regex":
            guard let a = actual as? String, let v = value as? String,
                  let re = try? NSRegularExpression(pattern: v) else { return false }
            return re.firstMatch(in: a, range: NSRange(a.startIndex..., in: a)) != nil
        case "gt", "gte", "lt", "lte":
            guard let a = toNum(actual), let b = toNum(value) else { return false }
            switch op { case "gt": return a > b; case "gte": return a >= b; case "lt": return a < b; default: return a <= b }
        default: return false
        }
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        if let a = a as? String, let b = b as? String { return a == b }
        if let a = toNum(a), let b = toNum(b) { return a == b }
        if let a = a as? Bool, let b = b as? Bool { return a == b }
        return false
    }

    static func evalGate(_ gate: [String: Any]?, _ user: [String: Any]) -> Bool {
        guard let gate = gate else { return false }
        if enabled(gate["killswitch"]) { return false }
        if !enabled(gate["enabled"]) { return false }
        for r in (gate["rules"] as? [[String: Any]] ?? []) {
            if !matchRule(r, user) { return false }
        }
        let rolloutPct = (gate["rolloutPct"] as? Int) ?? Int((gate["rolloutPct"] as? Double) ?? 0)
        guard let uid = userId(user) else {
            // No unit id (an unidentified request before any anon id is minted):
            // a fully-rolled gate is on for everyone, so it can be answered
            // without bucketing; a fractional rollout needs a stable unit, so
            // deny until one exists. Rules above still apply, so targeting wins.
            // See experiment-platform/18-identity-bucketing.md.
            return rolloutPct >= 10000
        }
        let salt = (gate["salt"] as? String) ?? ""
        return Murmur3.bucket("\(salt):\(uid)", mod: 10000) < UInt32(rolloutPct)
    }

    static func evalExperiment(
        _ exp: [String: Any]?,
        _ flags: [String: Any]?,
        _ exps: [String: Any]?,
        _ user: [String: Any]
    ) -> ExperimentResult {
        guard let exp = exp, exp["status"] as? String == "running" else { return notIn }

        if let tg = exp["targetingGate"] as? String, !tg.isEmpty {
            let gates = flags?["gates"] as? [String: Any]
            let gate = gates?[tg] as? [String: Any]
            if !evalGate(gate, user) { return notIn }
        }

        guard let uid = userId(user) else { return notIn }

        if let universeName = exp["universe"] as? String {
            let universes = exps?["universes"] as? [String: Any]
            let universe = universes?[universeName] as? [String: Any]
            if let holdout = universe?["holdout_range"] as? [Int], holdout.count == 2 {
                let seg = Murmur3.bucket("\(universeName):\(uid)", mod: 10000)
                if seg >= UInt32(holdout[0]) && seg <= UInt32(holdout[1]) { return notIn }
            }
        }

        let salt = (exp["salt"] as? String) ?? ""
        let allocPct = (exp["allocationPct"] as? Int) ?? Int((exp["allocationPct"] as? Double) ?? 0)
        if Murmur3.bucket("\(salt):alloc:\(uid)", mod: 10000) >= UInt32(allocPct) { return notIn }

        let groupHash = Murmur3.bucket("\(salt):group:\(uid)", mod: 10000)
        let groups = (exp["groups"] as? [[String: Any]]) ?? []
        var cumulative: UInt32 = 0
        for (i, g) in groups.enumerated() {
            cumulative += UInt32((g["weight"] as? Int) ?? 0)
            if groupHash < cumulative || i == groups.count - 1 {
                return ExperimentResult(inExperiment: true, group: (g["name"] as? String) ?? "control", params: g["params"])
            }
        }
        return notIn
    }
}
