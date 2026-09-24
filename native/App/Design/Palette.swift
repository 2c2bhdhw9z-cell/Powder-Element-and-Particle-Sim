import SwiftUI

/// Crucible's colours, carried over from the web version so the two look like one product.
///
/// Every value here is the same one the stylesheet defines. They are deliberately not
/// replaced with the system's own colours: the lab is a near-black room with desaturated
/// greys, and iOS's dark grey is lighter and bluer than this, which makes the chrome float
/// off the simulation instead of sitting under it.
enum Palette {
    /// The room. Everything sits on this.
    static let background = Color(hex: 0x0A0A0B)
    /// A raised surface — sheets, cards.
    static let elevated = Color(hex: 0x121214)
    /// A quieter raised surface, for controls at rest.
    static let subtle = Color(hex: 0x1A1A1E)

    /// Ordinary text and active icons.
    static let foreground = Color(hex: 0xF0F0F2)
    /// Secondary text, and icons that are available but not the point.
    static let muted = Color(hex: 0x9A9AA3)
    /// Text that is barely there: hints, units, disabled labels.
    static let subtleForeground = Color(hex: 0x6E6E76)

    /// The accent. A cool near-white rather than a colour, so nothing in the chrome ever
    /// competes with the simulation for attention.
    static let primary = Color(hex: 0xC8CCD4)
    static let primaryForeground = Color(hex: 0x0A0A0B)

    /// Destructive actions, and the recording indicator.
    static let danger = Color(hex: 0xC45C5C)
    /// Something healthy.
    static let ok = Color(hex: 0x7D9B84)
    /// Something worth noticing but not wrong.
    static let warn = Color(hex: 0xB5986A)

    /// Hairlines. The web version builds these by mixing the foreground into transparency;
    /// the same effect, stated directly.
    static let border = Color.white.opacity(0.15)
    static let borderStrong = Color.white.opacity(0.22)
}

/// Corner radii, matching the web version's scale.
enum Radius {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
}

extension Font {
    /// Headings and titles.
    ///
    /// The web version sets these in Syne, a geometric display face. Bundling a font file is
    /// a later refinement; until then this is the system face at the weight and tightness
    /// that reads closest to it, which is much nearer than leaving it at the default.
    static func labDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    /// Numbers that change while you watch them.
    ///
    /// Always monospaced. A frame counter in a proportional face shifts its own width as the
    /// digits change, which reads as the number jittering rather than counting.
    static func labNumeric(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

extension Color {
    /// Builds a colour from the `0xRRGGBB` form the stylesheet uses, so the two can be
    /// compared by eye without converting anything.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
