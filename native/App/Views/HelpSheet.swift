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

    var body: some View {
        LabSheet(title: "How to use this", subtitle: "Two chambers, and what they do") {
            chambers
            powder
            field
            depth
            materials
            tilting
            keeping
            sharing
            crashes
        }
    }

    /// Where the phone keeps its reports of the app closing by itself.
    ///
    /// The app writes nothing of its own when it crashes, and cannot: a crashed app is not running to write anything.
    /// But iOS writes a report every time, which says where in the app it happened — worth knowing exists before
    /// anything else is built.
    private var crashes: some View {
        LabGroup("If the app closes by itself") {
            paragraph(
                "Your iPhone writes down every time Crucible closes by itself, and where in the app it went "
                    + "wrong. To find it: open **Settings**, then **Privacy & Security**, then **Analytics & "
                    + "Improvements**, then **Analytics Data**. The reports whose names begin with **Crucible** are "
                    + "this app's, newest at the bottom; tap one, then the share button, to send it.\n\n"
                    + "If that list is empty, turn on **Share iPhone Analytics** on the screen before it (it may say "
                    + "iPhone & Watch); reports are kept from then on.\n\n"
                    + "The report says where it happened. What the world was doing is the other half, and Crucible "
                    + "keeps that itself: a short note of which chamber, how big, what was touched in the last "
                    + "minute. If the app closed by itself, the next time you open it offers to send that note.\n\n"
                    + "**That looked wrong**, at the bottom of the Lab and Field panels, sends the same note on "
                    + "purpose with a picture, for something that looked wrong without the app closing. You can read "
                    + "every word of both before sending, and nothing about you is in either."
            )
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

    @ViewBuilder
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
                    + "**Kaleidoscope** copies every stroke six times round the middle of the world, so one "
                    + "line of sand comes out as a snowflake — which then falls apart, being sand.\n\n"
                    + "**Paint in a colour** is for sand art: whatever you paint takes the colour you choose "
                    + "and keeps it as it falls, so layers stay separate like the bottles at the seaside. "
                    + "Flood a layer with the same material to recolour it. A material that turns into "
                    + "something else — sand melting to glass — loses the colour, because it is a new thing. "
                    + "Somebody watching in a shared room sees the plain material.\n\n"
                    + "**Photo into powder** turns a picture into a world: blue becomes water, white becomes "
                    + "snow, fierce orange becomes real lava, and everything else sand, each grain in its "
                    + "colour from the picture. It holds still until you press play, then falls apart.\n\n"
                    + "The **⇅** button in the tools turns the whole world upside down. Try it on the "
                    + "**Hourglass** scene.\n\n"
                    + "Hold any material's chip to read what it does.\n\n"
                    + "**Simple**, at the top of the Lab panel, shows five materials and three brushes instead of "
                    + "fifty and six, and hides the panels that are not about drawing — for handing the phone to "
                    + "somebody. Nothing behaves differently, and one switch brings it all back."
            )
        }
        LabGroup("Tools that are not painting") {
            paragraph(
                "**Lasso**, beside the brushes: draw a loop round something, and a bar above the tray offers "
                    + "what to do with it. **Move** lifts it out, leaving a hole, and it goes wherever you "
                    + "next drag or tap; **Put it back** changes your mind. **Copy** puts down as many copies as "
                    + "you like. **Heat** and **Cool** change everything inside by 250 degrees a press, "
                    + "**Colour** recolours it, and **Delete** empties it. Everything is one undo away.\n\n"
                    + "**Thermometer**: tap where it should go. It stays there and keeps reading, with a little "
                    + "graph of what it has read and the lowest and highest so far — a kiln warming, a pond "
                    + "freezing. Press the button again to move it; the × takes it out.\n\n"
                    + "**Rewind** is the ◀◀ beside play. The world stops, and the slider goes back through the "
                    + "last few seconds. **Back to now** puts everything exactly as it was; **Carry on from "
                    + "here**, or play, carries on from the moment on screen — and even that is one undo away. "
                    + "How far back it reaches depends on how fine the world is. Changing the detail or turning "
                    + "the phone starts it again.\n\n"
                    + "**Tide**, in the Lab panel under Sea: a sea beyond one edge of the world that slowly "
                    + "comes in and goes out. The whole sea rises, climbs the beach and fills the moat, then "
                    + "runs back out and leaves the rock pools.\n\n"
                    + "**Measure**, in the Lab panel: once a second, how full the world is, how hot, the "
                    + "thermometer's reading and how much of every material, sent as a spreadsheet to draw "
                    + "your own graphs from."
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
                    + "scatters them until they regroup.\n\n"
                    + "**Throw** is a slingshot: put your finger down, pull back and let go. The dotted "
                    + "line is the path it will really take — round black holes, off walls, down under "
                    + "gravity. **Jelly** turns any outline you draw into a wobbly jelly of that shape.\n\n"
                    + "**Record a loop**, in the tray, remembers one movement of your finger and repeats "
                    + "it for ever with the tool you made it with. Stack up to six: stirrers, heartbeats, "
                    + "wave machines.\n\n"
                    + "**Foxes and rabbits** hunt and breed by themselves; the little graph shows the "
                    + "numbers chase each other up and down. **Sand on a drum** gathers into the lines "
                    + "where a ringing plate is still — turn on Listen and the music chooses the pattern.\n\n"
                    + "**Measure**, in the Field panel, writes down once a second how many bodies there are, how "
                    + "fast they go, the energy of all their motion, where the middle is and how spread out they "
                    + "are — and the foxes and rabbits — and sends it as a spreadsheet to draw your own graphs from."
            )
        }
    }

    private var depth: some View {
        LabGroup("The field in 3D") {
            paragraph(
                "Tap **3D** beside the tray's heading and the bodies move in a box instead of on a flat "
                    + "sheet. Whatever is showing is rebuilt in 3D — a galaxy becomes a disc lying level, a "
                    + "tornado a real funnel — and undo takes it back.\n\n"
                    + "Pick **Turn** at the front of the tools and drag to go round the box. Every other "
                    + "tool reaches straight through it, from the front to the back, so pulling where your "
                    + "finger is pulls everything along that line. Walls you draw are panels reaching all the "
                    + "way through.\n\n"
                    + "Some arrangements only exist in 3D and carry a cube: a globe, a knot, an ocean, four "
                    + "strange attractors, a flight through the stars and a snow globe you can stir by "
                    + "tipping the phone with Tilt on.\n\n"
                    + "The tray's 3D section has the rest: views from the front, side, top or at an angle, "
                    + "how deep the box is, how strong the perspective and the fog are, whether the box is "
                    + "drawn, **Glow**, where overlapping bodies add up into light, and looking round the box "
                    + "by moving the phone.\n\n"
                    + "**Show the powder world**, in the tray, draws the powder world in the box as a slab of cubes, so "
                    + "a castle you just built can be turned round and looked at from any side. It is a view of that "
                    + "world, not a copy: nothing can be built from this side, and the powder world carries on exactly "
                    + "as it was.\n\n"
                    + "**Fly in** takes you inside the box: turning the view with Turn then looks round from "
                    + "in there. Touch something with **Look** and press **Fly to what Look touched** to fly "
                    + "to it instead of the middle. **Camera focus** makes near and far go soft like a "
                    + "photograph; touching something with Look brings it into focus."
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
                    + "Shaking the phone rattles loose material, whether tilt is locked or not.\n\n"
                    + "**The room**, in the Lab panel, uses the phone's other senses as part of the physics: falling "
                    + "air pressure means weather coming in, so the powder world turns colder and windier; the sun "
                    + "leans the wind west as the day goes on; the day's walking sets how strong the sea's tide is; "
                    + "and a dark room quietens the picture. It is off until you switch it on, it asks the phone for "
                    + "Motion & Fitness when you do, and nothing is sent anywhere."
            )
        }
    }

    private var keeping: some View {
        LabGroup("Keeping what you make") {
            paragraph(
                "Your work is kept by itself every few seconds and whenever you leave the app, and it "
                    + "comes back next time. Nothing to remember.\n\n"
                    + "**Kept** is a gallery of the worlds you have named deliberately, each with a picture of what "
                    + "it looked like: tap one to load it, hold one to send or delete it. The **camera** takes a "
                    + "picture. The **record** button captures a clip with sound.\n\n"
                    + "Touch and hold the camera in the powder world for two more: a **poster to print** — "
                    + "every grain a crisp square, big enough for an A3 sheet — and a **line drawing for a pen "
                    + "plotter**, every edge where one thing meets another drawn as long straight lines, sized "
                    + "for A4.\n\n"
                    + "Anything you paint is one **undo** away, and so is loading a scene, setting off "
                    + "an event, or running a repair."
            )
        }
    }

    /// Sharing, and the limits of it.
    ///
    /// Every limit stated. All three read as the app being broken if you meet one without having been
    /// told — a room that finds nobody, a follower whose controls do very little, a workshop that says
    /// nothing has been kept. The panels say the same things where they happen; this is for somebody
    /// reading before they try.
    private var sharing: some View {
        LabGroup("Sharing with other people") {
            paragraph(
                "**Shared room** lets somebody next to you paint in the same world. One phone runs the "
                    + "world and the others are shown it many times a second; everybody can paint, and "
                    + "every mark goes to whichever phone is running things. If that phone leaves, "
                    + "another takes over on its own.\n\n"
                    + "It works between phones **in the same place**, over wifi or Bluetooth. There is no "
                    + "server involved and nothing goes over the internet — so somebody in another town "
                    + "cannot join, and a room here cannot see a room opened in a browser.\n\n"
                    + "**Your worlds** keeps worlds on a server instead of on this phone, and the "
                    + "**workshop** is where people publish them. Both need Crucible's web address typed "
                    + "in once, under Your worlds — the app has no way of knowing it. Browsing the "
                    + "workshop needs no account; keeping and publishing do."
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
