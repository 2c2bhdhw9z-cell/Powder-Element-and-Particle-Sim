import SwiftUI

/// What everything does, in plain words.
///
/// ## Adapted rather than translated
///
/// The web version's equivalent is mostly a list of keyboard shortcuts — space to pause, `[` and `]`
/// for brush size, `T` to cycle the heat view. On a phone every one of those is meaningless, and
/// carrying them across would produce a help screen that helps with nothing.
///
/// What *is* worth keeping is the other half: the knowledge about how the simulation behaves, which
/// is not discoverable by poking at it. That water erodes sand, that sealed steam ruptures, that
/// painting a fan again turns it — these are the things someone would otherwise never find.
///
/// Everything here describes something that actually exists in this app. It is easy to write a help
/// screen from the reference implementation's and end up promising a feature that was never ported,
/// which is worse than saying nothing.
struct HelpSheet: View {
    let glass: GlassLevel

    var body: some View {
        LabSheet(title: "How to use this", subtitle: "Two chambers, and what they do", glass: glass) {
            chambers
            powder
            field
            materials
            tilting
            keeping
        }
    }

    // MARK: Sections

    private var chambers: some View {
        LabGroup("The two chambers") {
            paragraph(
                "**Powder** is falling matter on a grid — sand, water, lava, fire. **Particles** is a "
                    + "field of free bodies pulling on one another: orbits, swarms, cloth.\n\nSwitch "
                    + "between them at the top. Whichever you are not looking at pauses and picks up "
                    + "exactly where it left off — or, if you turn on **Keep both running** in the "
                    + "Lab panel, carries on out of sight.\n\nThe split button beside the switch shows "
                    + "both at once, one above the other. Worth trying: the two chambers affect each "
                    + "other, and that is invisible unless you can see both. Explosions here throw "
                    + "sparks into the field, and bodies that come to rest there silt down into sand "
                    + "and water. Tap a half to give it the tray."
            )
        }
    }

    private var powder: some View {
        LabGroup("Painting") {
            paragraph(
                "Drag on the world to paint. The tray along the bottom holds every material — open it "
                    + "for the full set, a search box, and the brush.\n\n"
                    + "**Round, Square and Spray** differ only in shape. **Line** draws a single "
                    + "trail of cells. **Flood** fills the whole connected space you tap — useful for "
                    + "filling a container in one go. **Replace** swaps one material for another and "
                    + "leaves everything else alone: it replaces whatever you start the drag on.\n\n"
                    + "**Pick** takes the material under your next tap, which is quicker than hunting "
                    + "for it in the tray. **Erase** is at the end of the quick row.\n\n"
                    + "Hold any material's chip to read what it does."
            )
        }
    }

    private var field: some View {
        LabGroup("The particle field") {
            paragraph(
                "Touch and hold to apply a force. The tray chooses which — **Pull**, **Push**, "
                    + "**Swirl**, **Well**, **Freeze**, **Emit**, **Paint**, **Hawk** or **Hyper**. "
                    + "The ring round your finger shows how far the force reaches; turned all the way "
                    + "up it covers the whole world, and the ring grows to say so.\n\n"
                    + "**Arrangements** drop in a ready-made setup — a galaxy, a cloth, a helix. "
                    + "**Add** scatters in more bodies, up to whatever ceiling you have set.\n\n"
                    + "Cloth, rope and blob are held together by springs, so dragging one pulls the "
                    + "whole sheet. A flock is steered by its own neighbours, and pushing into it "
                    + "scatters them until they regroup."
            )
        }
    }

    private var materials: some View {
        LabGroup("What the materials do to each other") {
            paragraph(
                "This is the part worth knowing, because none of it is obvious:\n\n"
                    + "Water boils into steam on lava and freezes beside ice. Steam rises, cools, and "
                    + "rains back down — but sealed in a room it builds pressure until it ruptures.\n\n"
                    + "Oil floats on water and burns hard. Fire needs fuel and dies without it. Lava "
                    + "melts sand into glass and stone into more lava, and sets into obsidian as it "
                    + "cools.\n\n"
                    + "Acid eats almost everything except glass and bedrock. Sparks travel through "
                    + "metal and copper — copper also carries heat a long way. Plants drink water and "
                    + "grow toward it. C4 and hydrogen go off if anything sparks them.\n\n"
                    + "Water slowly erodes sand and dirt. Paint a fan again to turn it. The void "
                    + "deletes whatever touches it and sucks pressure out of the room."
            )
        }
    }

    private var tilting: some View {
        LabGroup("Tilting and shaking") {
            paragraph(
                "**Tilt** hands gravity over to the phone — tip it and everything falls that way. Tap "
                    + "it again to **lock**, which holds gravity where it is so you can bring the "
                    + "phone back level and look at what you have made without it all sliding back. A "
                    + "third tap switches it off.\n\n"
                    + "Shaking the phone rattles loose material, whether tilt is locked or not."
            )
        }
    }

    private var keeping: some View {
        LabGroup("Keeping what you make") {
            paragraph(
                "Your work is kept by itself every few seconds and whenever you leave the app, and it "
                    + "comes back next time. Nothing to remember.\n\n"
                    + "**Kept** holds scenes you have named deliberately, and can send one to another "
                    + "app or open one you were sent. The **camera** takes a picture. The **record** "
                    + "button captures a clip with sound.\n\n"
                    + "Anything you paint is one **undo** away, and so is loading a scene, setting off "
                    + "an event, or running a repair."
            )
        }
    }

    // MARK: Pieces

    /// A block of prose.
    ///
    /// Written with markup for the emphasis, which SwiftUI understands in a string it is given
    /// directly — so the names of controls can be bold without splitting every paragraph into a dozen
    /// pieces of view.
    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .font(.labBody(13))
            .foregroundStyle(Palette.muted)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }
}
