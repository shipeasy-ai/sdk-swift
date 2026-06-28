import SwiftUI

/// One Shipeasy entity rendered as a single card in the guide.
///
/// Everything in here is a HARDCODED PLACEHOLDER. The SDK is not wired into
/// this example yet, so `value` is a static string and `call` is the real SDK
/// call rendered as a visible code block. Once you add the Shipeasy Swift
/// package, replace the matching `// TODO` (see the block on each property
/// below and in `ContentView.swift`) to make these values live.
struct Entity: Identifiable {
    let id = UUID()
    /// UPPERCASE type label shown in the accent chip (e.g. "FEATURE FLAG").
    let label: String
    /// The monospace key/identifier shown as the card title (e.g. "new_checkout").
    let key: String
    /// The placeholder display value shown in the accent value chip.
    let value: String
    /// One-line plain-English description of what the entity is.
    let description: String
    /// The real SDK call, rendered as a monospace code block on the card.
    let call: String
    /// A faint meta line under the code block.
    let meta: String
    /// Accent colour for this entity's chips.
    let accent: Color
}

extension Entity {
    /// The placeholder data, in the exact order the guide presents it.
    ///
    /// To go live, install the Shipeasy Swift package and replace each
    /// placeholder `value` with the result of the call shown in `call`.
    static let all: [Entity] = [
        // 1. FEATURE FLAG ----------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   let on = await client.getFlag("new_checkout", user: ["user_id": "u_123"])
        Entity(
            label: "FEATURE FLAG",
            key: "new_checkout",
            value: "true · RULE_MATCH",
            description: "A boolean on/off switch with targeting rules + percentage rollout.",
            call: #"let on = await client.getFlag("new_checkout", user: ["user_id": "u_123"])"#,
            meta: "evaluated for user u_123 · reason RULE_MATCH",
            accent: Color(hex: "#34d399")
        ),

        // 2. DYNAMIC CONFIG --------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   let cfg = await client.getConfig("billing_copy")
        Entity(
            label: "DYNAMIC CONFIG",
            key: "billing_copy",
            value: #"["headline": "Welcome back 👋", "cta": "Upgrade to Pro"]"#,
            description: "A typed JSON blob you change without deploying.",
            call: #"let cfg = await client.getConfig("billing_copy")"#,
            meta: "typed JSON · changed from the dashboard, no redeploy",
            accent: Color(hex: "#60a5fa")
        ),

        // 3. A/B EXPERIMENT --------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   let r = await client.getExperiment("checkout_button", user: ["user_id": "u_123"], defaultParams: ["color": "#888", "label": "Buy"])
        Entity(
            label: "A/B EXPERIMENT",
            key: "checkout_button",
            value: ##"treatment · ["color": "#34d399", "label": "Buy now"]"##,
            description: "Splits users into variants and measures a metric.",
            call: ##"let r = await client.getExperiment("checkout_button", user: ["user_id": "u_123"], defaultParams: ["color": "#888", "label": "Buy"])"##,
            meta: "inExperiment true · group treatment",
            accent: Color(hex: "#c084fc")
        ),

        // 4. KILL SWITCH -----------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   let boot = await client.evaluate(["user_id": "u_123"])
        //   let paused = boot["killswitches"]?["payments_paused"]
        Entity(
            label: "KILL SWITCH",
            key: "payments_paused",
            value: "false · payments live",
            description: "An operational off-switch shipped alongside flags — flip it to disable a subsystem during an incident.",
            call: #"let boot = await client.evaluate(["user_id": "u_123"]); let paused = boot["killswitches"]?["payments_paused"]"#,
            meta: "operational · flip to disable a subsystem during an incident",
            accent: Color(hex: "#f87171")
        ),

        // 5. EVENT / METRIC --------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   await client.track(userId: "u_123", eventName: "checkout_completed", properties: ["revenue": 49.99, "plan": "pro"])
        Entity(
            label: "EVENT / METRIC",
            key: "checkout_completed",
            value: #"queued · ["revenue": 49.99, "plan": "pro"]"#,
            description: "Fire-and-forget events that power experiment metrics + dashboards.",
            call: #"await client.track(userId: "u_123", eventName: "checkout_completed", properties: ["revenue": 49.99, "plan": "pro"])"#,
            meta: "last event queued · powers experiment metrics + dashboards",
            accent: Color(hex: "#22d3ee")
        ),

        // 6. I18N LABEL ------------------------------------------------------
        // TODO: once the Shipeasy Swift package is installed (i18n ships as a follow-up for Swift)
        //   t("hero.title", ["name": "Sam"])
        Entity(
            label: "I18N LABEL",
            key: "hero.title",
            value: "Ship features, not stress",
            description: "Server-managed copy you translate + publish from the dashboard — no redeploy. (i18n for the Swift SDK ships as a follow-up; shown for completeness.)",
            call: #"t("hero.title", ["name": "Sam"])"#,
            meta: "illustrative · i18n for the Swift SDK ships as a follow-up",
            accent: Color(hex: "#fbbf24")
        ),

        // 7. ERROR REPORTING — see() -----------------------------------------
        // TODO: once the Shipeasy Swift package is installed
        //   do { try await submitOrder(o) }
        //   catch { see(error).causes_the("checkout").to("use cached prices").extras(["order_id": o.id]) }
        Entity(
            label: "ERROR REPORTING",
            key: "see()",
            value: "0 issues reported this session",
            description: "Structured error reports that document the product consequence, not just a stack trace.",
            call: #"do { try await submitOrder(o) } catch { see(error).causes_the("checkout").to("use cached prices").extras(["order_id": o.id]) }"#,
            meta: "documents the product consequence, not just a stack trace",
            accent: Color(hex: "#f87171")
        ),
    ]
}
