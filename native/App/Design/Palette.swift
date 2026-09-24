import SwiftUI
// For UIFont, which is the only way to ask whether a bundled face actually registered.
// SwiftUI's Font has no equivalent — it reports no error for a name it cannot find.
import UIKit

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

    /// Hairlines.
    ///
    /// The stylesheet builds these by mixing the *foreground* into transparency rather than pure
    /// white — twelve percent for the ordinary one and twenty-two for the stronger. Using white
    /// instead is very nearly the same thing, since the foreground is already a near-white, but
    /// there is no reason to be approximately right when the exact value is written down.
    ///
    /// These are the theme's values, used for dividers and panel outlines. Several individual
    /// pieces of chrome specify their own instead — the header's underline is twelve percent white,
    /// the trays' top edge fifteen, a sheet's outline sixteen — and those are set where they are
    /// used, because in the reference they are per-component rather than part of the theme.
    static let border = foreground.opacity(0.12)
    static let borderStrong = foreground.opacity(0.22)
}

/// Corner radii, matching the web version's scale.
enum Radius {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 24
}

/// The three typefaces the web version uses, bundled with the app.
///
/// The web build pulls Syne and IBM Plex Sans from Google's servers at page load. An app
/// cannot do that — it has to work with no network — so the font files are committed under
/// `App/Resources/Fonts` and listed in `Info.plist` under `UIAppFonts`. Both are licensed
/// under the SIL Open Font License, whose text sits beside them in the same folder.
///
/// ## Why each face is named exactly, rather than asked for by weight
///
/// The obvious way to write this is `Font.custom("IBM Plex Sans", size: 12).weight(.medium)`
/// and let the system find the right file. That does not work here. IBM ships each weight of
/// Plex declaring its **own family name** — the medium file calls itself "IBM Plex Sans Medm"
/// and the semibold "IBM Plex Sans SmBld" — so asking the "IBM Plex Sans" family for a
/// heavier weight finds nothing and the system invents one by smearing the regular, which
/// looks subtly wrong in a way that is hard to place.
///
/// So every face is requested by its exact PostScript name. Unambiguous, and it does not
/// depend on the system's font-matching guesswork.
///
/// ## Why a missing font must be noisy
///
/// If one of these files is not in the bundle, `Font.custom` does not fail — it quietly
/// hands back the system face. The app still runs and still looks *fine*; it just does not
/// look like Crucible, with nothing to say why. That is the exact complaint this work exists
/// to fix, so ``LabFonts/missingFaces()`` checks every name at runtime and the debug readout
/// shows the result.
enum LabFonts {
    /// Display: Syne. Titles, headings, and the one big number on the performance sheet.
    enum Display: String, CaseIterable {
        case medium = "Syne-Medium"      // 500
        case semiBold = "Syne-SemiBold"  // 600
        case bold = "Syne-Bold"          // 700
    }

    /// Body: IBM Plex Sans. Everything that is prose or a label.
    enum Body: String, CaseIterable {
        case regular = "IBMPlexSans"        // 400
        case medium = "IBMPlexSans-Medm"    // 500
        case semiBold = "IBMPlexSans-SmBld" // 600
    }

    /// Numeric: IBM Plex Mono. Readouts, counters, anything that changes while watched.
    ///
    /// The web version declares this face and then never loads it — its font request lists
    /// only Syne and Plex Sans — so what actually ships on the web is whatever monospace the
    /// browser defaults to. That is a bug there rather than a decision, and the same request
    /// has been corrected on the web side so the two now genuinely match.
    enum Numeric: String, CaseIterable {
        case regular = "IBMPlexMono-Regular"  // 400
        case medium = "IBMPlexMono-Medium"    // 500
    }

    /// Every face the app expects to find, by PostScript name.
    static var allFaceNames: [String] {
        Display.allCases.map(\.rawValue)
            + Body.allCases.map(\.rawValue)
            + Numeric.allCases.map(\.rawValue)
    }

    /// The faces that are *not* installed, which should be empty.
    ///
    /// Anything listed here is being silently substituted, so the interface is not the one
    /// that was designed. Surfaced in the debug readout rather than only logged, because the
    /// person most likely to notice the difference cannot read a console.
    static func missingFaces() -> [String] {
        allFaceNames.filter { UIFont(name: $0, size: 12) == nil }
    }
}

extension Font {
    /// Headings and titles, in Syne.
    ///
    /// Sizes are fixed rather than scaled with the reader's preferred text size, matching
    /// the web version, whose docks and chips are laid out to the pixel. Growing the type
    /// without also reflowing those would overlap them. Worth revisiting as a real
    /// accessibility pass, which is a layout job rather than a font one.
    static func labDisplay(_ size: CGFloat, _ weight: LabFonts.Display = .semiBold) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }

    /// Prose and labels, in IBM Plex Sans.
    static func labBody(_ size: CGFloat, _ weight: LabFonts.Body = .regular) -> Font {
        .custom(weight.rawValue, fixedSize: size)
    }

    /// Numbers that change while you watch them, in IBM Plex Mono.
    ///
    /// Always monospaced. A frame counter in a proportional face shifts its own width as the
    /// digits change, which reads as the number jittering rather than counting.
    static func labNumeric(_ size: CGFloat, _ weight: LabFonts.Numeric = .medium) -> Font {
        .custom(weight.rawValue, fixedSize: size)
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
