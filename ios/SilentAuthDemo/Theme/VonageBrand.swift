import SwiftUI

/// Vonage brand palette and text styles, from the Vonage Brand Guidelines 2025.
/// We brand through color and type only — the guidelines restrict the logo
/// lock-up and "V" symbol to provided assets with approval, so there is no logo
/// anywhere in the app (a plain-text "Powered by Vonage" footer stands in).
enum VonageBrand {
    // Primary palette
    static let purple = Color(hex: 0x871FFF)   // primary actions, current stage, device
    static let plum = Color(hex: 0x3D0049)     // headlines, nav, server
    static let raspberry = Color(hex: 0x9E1766)
    static let magenta = Color(hex: 0xD6219C)  // SMS stage accent

    // Secondary palette
    static let cyan = Color(hex: 0x80C7F5)     // informational (check_url / silent-auth in-flight)
    static let orange = Color(hex: 0xFA7554)   // voice stage accent (guide: orange for solid fills, not peach)

    // Grays / neutrals
    static let gray1 = Color(hex: 0xE8EAEE)    // subtle section backgrounds
    static let gray2 = Color(hex: 0xD9DCE3)    // separators
    static let gray3 = Color(hex: 0xC2C4CC)    // faint mono labels
    static let gray4 = Color(hex: 0x878A91)    // secondary text
    static let gray5 = Color(hex: 0x54575E)    // dimmed stage text

    static let success = Color(hex: 0x1D9E75)  // completed check (teal, complements the palette)
}

extension Color {
    /// Build a Color from a 0xRRGGBB literal.
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

extension Text {
    /// Eyebrow style from the guidelines: all-caps mono, tracked out. Used for
    /// stage headers and small labels.
    func vonageEyebrow(color: Color = VonageBrand.plum) -> some View {
        self
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.semibold)
            .tracking(1.5)
            .foregroundColor(color)
    }
}
