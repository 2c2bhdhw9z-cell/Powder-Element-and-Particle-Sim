import SwiftUI

/// How much glass the interface uses.
///
/// A real range, not a fade. The requirement is that someone who wants a flat, quiet,
/// legible interface can have one — and that turning it down genuinely removes the work
/// rather than making it invisible. Every blur behind a control is pixels the GPU reads back
/// and filters each frame, in the same budget the simulation is drawing from, so on a large
/// world this is a performance setting as much as a matter of taste.
enum GlassLevel: String, CaseIterable, Identifiable, Codable {
    /// No blur anywhere. Controls are solid panels. Nothing is sampled, nothing is filtered.
    case flat
    /// A single thin blur. The look of the web version.
    case subtle
    /// The full treatment: Apple's Liquid Glass where the system provides it, with its
    /// refraction and its response to what is behind it.
    case full

    var id: String { rawValue }

    /// What the choice is called on screen.
    ///
    /// **"Off" rather than "Flat".** The three rungs used to read Flat / Subtle / Glass, and somebody
    /// looking for a way to turn the glass off found no such words — picked the middle one, which still
    /// blurs, and reasonably concluded the setting did nothing. A control named for the *look it produces*
    /// is no use to somebody who wants the look gone; the bottom rung has to say so.
    var title: String {
        switch self {
        case .flat: "Off"
        case .subtle: "Light"
        case .full: "Apple glass"
        }
    }

    var explanation: String {
        switch self {
        case .flat: "No blur anywhere. Every panel is solid. Fastest, and the easiest to read."
        case .subtle: "One thin blur behind each panel. Things behind still show through, faintly."
        case .full: "Apple's own glass, which bends and picks up whatever is behind it."
        }
    }

    /// Whether anything is blurred at all at this level.
    ///
    /// The question every surface in the app is really asking, and worth a name of its own so that a
    /// surface which cannot use the shared treatments still has one obvious thing to check.
    var blursAnything: Bool { self != .flat }
}

/// Applies the chosen glass treatment to a panel.
///
/// One place, so a change to the look reaches every control at once and no panel is left
/// behind. Applied as a background rather than an overlay so content keeps its own colours.
struct GlassBackground<S: Shape>: ViewModifier {
    let level: GlassLevel
    let shape: S

    func body(content: Content) -> some View {
        switch level {
        case .flat:
            // A solid fill. Deliberately not a very dark translucency, which would still
            // composite against the simulation and still cost a pass — the point of this
            // setting is that there is nothing to composite.
            content
                .background(Palette.elevated, in: shape)
                .overlay(shape.stroke(Palette.border, lineWidth: 1))

        case .subtle:
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.black.opacity(0.45), in: shape)
                .overlay(shape.stroke(Palette.border, lineWidth: 1))

        case .full:
            content.modifier(LiquidGlassBackground(shape: shape))
        }
    }
}

/// The full treatment, where the system offers it.
///
/// Liquid Glass arrived in iOS 26. The app's floor is iOS 17, so this falls back to the
/// thicker of the ordinary materials — which is the same thing the `subtle` level does one
/// step lighter, and reads as a deliberate design rather than a missing feature.
private struct LiquidGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Palette.borderStrong, lineWidth: 1))
        }
    }
}

extension View {
    /// Keeps the system's own glass out of a scrolling view's edges, unless the full treatment was what
    /// was asked for.
    ///
    /// iOS 26 fades the content at the edge of anything that scrolls, behind a soft blur of its own
    /// making. That is Apple's glass turning up somewhere this app never put any — which is welcome at
    /// the top setting and is precisely what the bottom setting exists to remove. "No blur at all" is the
    /// promise Flat makes, and a blur the app did not draw breaks it just as thoroughly as one it did.
    @ViewBuilder
    func labScrollEdges(_ level: GlassLevel) -> some View {
        if #available(iOS 26.0, *), level != .full {
            // Hard rather than hidden: the content still stops cleanly at the edge, it simply stops
            // instead of dissolving into a pane of frosted glass.
            scrollEdgeEffectStyle(.hard, for: .all)
        } else {
            self
        }
    }

    /// Gives a panel the current glass treatment.
    func glassPanel<S: Shape>(_ level: GlassLevel, in shape: S) -> some View {
        modifier(GlassBackground(level: level, shape: shape))
    }

    /// Gives a panel the current glass treatment with a capsule outline, which is the shape
    /// almost every floating control in this interface uses.
    func glassPanel(_ level: GlassLevel) -> some View {
        modifier(GlassBackground(level: level, shape: Capsule()))
    }
}

/// A backdrop for a surface that is not a panel.
///
/// A bar has one edge and a sheet has two, so neither can use ``GlassBackground`` — it outlines all four.
/// They used to carry their own copy of the same three-way switch instead, which meant the app decided what
/// glass means in three separate places. They agreed, but nothing made them agree, and "turn the glass off"
/// is exactly the kind of promise that gets broken by the copy somebody forgot.
///
/// - Parameters:
///   - solid: what is painted when there is no blur to paint.
///   - tint: how dark the wash over the blur is, when there is one. A bar wants less than a sheet: a sheet
///     is something you read, and a bar sits over a moving simulation all the time.
struct GlassSurface: View {
    let level: GlassLevel
    let solid: Color
    let tint: Double

    var body: some View {
        switch level {
        case .flat:
            // Flat means opaque. Not a very dark translucency — that still composites the simulation
            // behind it every frame, which is both the cost and the look this setting exists to remove.
            solid
        case .subtle:
            Color.black.opacity(tint).background(.ultraThinMaterial)
        case .full:
            Color.black.opacity(tint).background(.regularMaterial)
        }
    }
}

/// Groups several glass panels so they can influence one another.
///
/// On iOS 26 sibling glass surfaces inside a container merge and separate as they move,
/// which is most of what makes the material feel like a material. Below that, and at the
/// lower settings, this is just a passthrough.
struct GlassGroup<Content: View>: View {
    let level: GlassLevel
    @ViewBuilder var content: Content

    var body: some View {
        if level == .full, #available(iOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
