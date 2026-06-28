import SwiftUI

/// Shipeasy dark-brand palette + a `Color(hex:)` helper.
///
/// All values are the brand tokens from the design spec. The accent colours
/// live on each `Entity` (see `Entity.swift`); the surfaces and text tokens
/// here are shared across the whole guide screen.
enum Theme {
    // Surfaces
    static let screenBg = Color(hex: "#0a0a0b") // screen background
    static let card = Color(hex: "#141416")     // entity card surface
    static let codeSurface = Color(hex: "#0f0f10") // nested / code surface
    static let hairline = Color(hex: "#1f1f22")  // hairline border (~white @ 8%)

    // Text
    static let textPrimary = Color(hex: "#F5F5F4")
    static let textMuted = Color(hex: "#B9B9B6")
    static let textFaint = Color(hex: "#7C7C79")
}

extension Color {
    /// Build a `Color` from a `#RRGGBB` or `#RRGGBBAA` hex string.
    ///
    /// Falls back to opaque magenta on a malformed string so a typo is loud
    /// rather than silently transparent.
    init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value) else {
            self = Color(red: 1, green: 0, blue: 1)
            return
        }

        let r, g, b, a: Double
        switch raw.count {
        case 6: // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            self = Color(red: 1, green: 0, blue: 1)
            return
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
