import SwiftUI

/// What a floating control sits on.
///
/// ## Why there is no choice here any more
///
/// There used to be a three-way glass setting: flat, one thin blur, or Apple's Liquid Glass. It is gone, and
/// not because it was hard to keep — because it was not worth keeping. Two reasons, in order of importance.
///
/// **It did not look like glass.** Over a near-black world there is nothing behind a panel to refract, so
/// all the material could do was wash the panel grey and darken whatever was under it. The whole appeal of
/// that material is picking up colour and shape from behind; put it over a dark field of small bright dots
/// and it picks up almost nothing. It read as a dirty window, and every setting past "off" made the
/// interface murkier without making it prettier.
///
/// **It cost frames, continuously, for that.** A blur is not a colour — it is the compositor reading the
/// pixels behind the panel and filtering them, every frame, out of the same GPU budget the simulation draws
/// from. There were eight or nine of those regions live at once: the bar across the top, the dock, both tool
/// capsules, the tilt button, the inspect chip, the readout. Two of them also carried a large soft shadow,
/// which is another full blur pass each. All of it sat over a Metal layer being handed to the screen a
/// hundred and twenty times a second, and the cost scaled with the *area* covered — which is why opening
/// the dock made it worse and closing it made it better, and why it sometimes appeared to recover on its
/// own when a chip or a sheet went away.
///
/// So: solid panels, one hairline, nothing sampled and nothing filtered. The look is the one the setting's
/// bottom rung always produced, which was the legible one anyway.
extension View {
    /// Gives a panel its backdrop.
    func solidPanel<S: Shape>(in shape: S) -> some View {
        background(Palette.elevated, in: shape)
            .overlay(shape.stroke(Palette.border, lineWidth: 1))
    }

    /// The same, with the capsule outline almost every floating control in this interface uses.
    func solidPanel() -> some View {
        solidPanel(in: Capsule())
    }

    /// Keeps the system's own glass out of a scrolling view's edges.
    ///
    /// iOS 26 fades the content at the edge of anything that scrolls, behind a soft blur of its own making.
    /// That is a blur this app did not draw and does not want, and it breaks the promise of a flat interface
    /// just as thoroughly as one it did draw. Unconditional now that there is no level to check.
    @ViewBuilder
    func labScrollEdges() -> some View {
        if #available(iOS 26.0, *) {
            // Hard rather than hidden: the content still stops cleanly at the edge, it simply stops instead
            // of dissolving into a pane of frosted glass.
            scrollEdgeEffectStyle(.hard, for: .all)
        } else {
            self
        }
    }
}
