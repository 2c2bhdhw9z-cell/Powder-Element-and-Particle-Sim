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

    var title: String {
        switch self {
        case .flat: "Flat"
        case .subtle: "Subtle"
        case .full: "Glass"
        }
    }

    var explanation: String {
        switch self {
        case .flat: "No blur at all. Fastest, and the easiest to read."
        case .subtle: "One thin blur behind each panel."
        case .full: "Refracting glass that picks up what is behind it."
        }
    }
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
