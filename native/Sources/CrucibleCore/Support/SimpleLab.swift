/// A smaller lab, for handing the phone to somebody.
///
/// ## Why taking things away is a feature
///
/// There are fifty materials, a couple of dozen arrangements, nine scenes that only exist in 3D, and dozens of
/// settings. That is right for somebody who wants it, and hopeless for somebody who has just been handed the phone.
/// Nothing in the app could be made smaller until now, which meant the only way to show it to anybody was to watch
/// them tap the wrong thing.
///
/// So this is the short list: five materials, three shapes, four scenes, the two things that make something happen.
/// Nothing is removed from the app — the full set is one switch away — and nothing here behaves differently from how it
/// behaves in the full lab. It is the same lab with less of it showing.
///
/// ## How the list was chosen
///
/// Each material has to *do* something visible to the next one along, because that is the whole of what makes the
/// powder world interesting: sand piles and pours, water finds its level and puts fire out, lava burns and sets into
/// stone, plants drink and grow, and stone holds everything else up. Fire is there rather than a fifth solid because
/// fire is what makes the other four worth trying.
public enum SimpleLab {
    /// The materials offered, in the order they should be shown.
    public static let materials: [ElementID] = [
        Element.sand,
        Element.water,
        Element.stone,
        Element.lava,
        Element.plant,
    ]

    /// The brush shapes offered. Flood and replace are for building; a guest is drawing.
    public static let shapes: [BrushShape] = [.circle, .square, .spray]

    /// The scenes offered, by the name each recipe carries.
    ///
    /// Held as names rather than as recipes so that this list cannot go stale without being noticed: the test alongside
    /// it looks every one up, so a renamed scene fails a check rather than quietly vanishing from the short list.
    public static let sceneNames = ["Beach", "Volcano", "Snow", "Forest"]

    /// The set-piece events offered: the two that are unmistakable.
    public static let events: [PowderEventID] = [.meteor, .freeze]

    /// Whether a material is offered in the smaller lab. The eraser always is.
    public static func offers(_ id: ElementID) -> Bool {
        id == Element.empty || materials.contains(id)
    }

    /// The scenes offered, looked up among all the recipes there are. A name that matches nothing is left out rather
    /// than crashing; the test beside this one is what makes sure that never happens quietly.
    public static var scenes: [PowderRecipe] {
        sceneNames.compactMap { name in allPowderRecipes.first { $0.name == name } }
    }
}

/// The few things worth saying to somebody opening the app for the first time.
///
/// ## Why the words are here rather than in the app
///
/// Because they are the app's one chance to explain itself, and because here they can be checked: that there is a step
/// for each of the things nobody would otherwise find, that none of them is empty, and that none of them promises
/// something that does not exist. A first run written in the interface is a first run nobody tests, and it ages badly —
/// it goes on describing a button that has moved.
public enum LabIntroduction {
    /// One thing to say, with the picture that goes with it.
    public struct Step: Sendable, Hashable {
        /// A few words, as a heading.
        public var title: String
        /// One or two sentences, in plain English.
        public var body: String
        /// The name of the symbol to draw beside it. The app's own furniture uses these throughout.
        public var symbol: String

        public init(title: String, body: String, symbol: String) {
            self.title = title
            self.body = body
            self.symbol = symbol
        }
    }

    /// What is said, in order. Six, because a seventh is where somebody stops reading.
    public static let steps: [Step] = [
        Step(
            title: "Two worlds",
            body: "The powder world is falling material on a grid — sand, water, lava, fire. The particle field is a "
                + "crowd of bodies pulling on one another: orbits, swarms, cloth. Switch between them at the top, or "
                + "show both at once.",
            symbol: "square.grid.3x3.fill"
        ),
        Step(
            title: "Drag to paint",
            body: "Whatever is chosen in the tray at the bottom is what your finger leaves behind. Open the tray for "
                + "everything there is, and hold any material to read what it does.",
            symbol: "hand.draw"
        ),
        Step(
            title: "The materials do things to each other",
            body: "That is the whole point of them. Water puts fire out and boils on lava. Lava melts sand into glass "
                + "and sets into stone as it cools. Plants drink water and grow towards it. Acid eats nearly "
                + "everything.",
            symbol: "flame"
        ),
        Step(
            title: "Tilt it",
            body: "Tilt hands gravity to the phone: tip it and everything falls that way. Tap it again to hold "
                + "gravity where it is, so you can bring the phone back level and look at what you have made.",
            symbol: "gyroscope"
        ),
        Step(
            title: "Nothing is lost",
            body: "Anything you do is one undo away, including loading a scene or setting something off. Your work is "
                + "kept by itself and comes back next time, and Rewind beside play goes back through the last few "
                + "seconds.",
            symbol: "arrow.uturn.backward"
        ),
        Step(
            title: "Handing it to somebody",
            body: "In the Lab panel, Simple shows five materials and three brushes instead of fifty and six. It is the "
                + "same lab with less of it showing, and one switch brings it all back.",
            symbol: "person.2"
        ),
    ]
}
