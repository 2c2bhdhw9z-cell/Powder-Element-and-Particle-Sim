// The first time you make something, it gets written down.
//
// ## Why this exists at all
//
// The lab has about fifty materials and a great many ways they turn into one another, and almost none of that is
// written down anywhere a player would find it. Sand becomes glass — but only above one thousand four hundred and
// fifty degrees, which nothing tells you. Lava cooling below seven hundred becomes obsidian. Water and dirt make mud.
// A kernel at a hundred and eighty pops.
//
// So people find one or two of these and never the rest, and the world is much smaller than it is. A notebook is the
// cheapest possible fix: keep playing, and the moment something new appears it is noted, with a picture of the moment
// it happened and a line about what the rule actually was. Nothing to read first, nothing to unlock, no scores.
//
// ## Why noticing is harder than it sounds
//
// There is exactly one place in the engine where a cell's material can be *deliberately* set, and sixteen places that
// can change a cell at all. Watching all sixteen would be a lot of hooks in a hot loop. Watching the one would miss
// most of what happens.
//
// What is done instead: the one deliberate door — `setElement` — raises a flag, and the engine only *listens* while it
// is running a moment of simulation. That distinction is the whole design. Painting glass by hand is not discovering
// glass; making sand hot enough that it becomes glass by itself is. The same door serves both, and the difference is
// simply whether the world was running its own rules at the time.
//
// The few places that write a cell without going through that door are the ones that had to be added by hand, and each
// is noted where it is.
//
// ## Why the list is written out rather than derived
//
// It would be possible to notice *every* material that ever appears and name it from the element table. That would give
// a notebook full of "you discovered sand", which is not a discovery — it is the thing you painted. The list below is
// the things that are genuinely made rather than placed, each with the rule that makes it, in the words somebody would
// use. Fifteen entries that mean something, rather than fifty that do not.

/// One thing worth finding out.
public struct Discovery: Sendable, Hashable, Codable, Identifiable {
    /// What it is called, which is also how it is remembered — so renaming one loses it rather than duplicating it.
    public var id: String
    /// The heading.
    public var name: String
    /// What actually happened, in the words somebody would use to tell a friend.
    public var about: String
    /// What to try, for the ones still unfound. Left out of the notebook until then.
    public var hint: String

    public init(id: String, name: String, about: String, hint: String) {
        self.id = id
        self.name = name
        self.about = about
        self.hint = hint
    }
}

/// Everything the notebook can hold.
public enum Discoveries {
    /// The ones made from a material appearing that was not there before.
    ///
    /// Keyed by the element that appears. Only materials that are *made* — a material you can simply choose from the
    /// tray is not a discovery, and putting it here would fill the notebook with things nobody found.
    public static let byElement: [ElementID: Discovery] = [
        Element.glass: Discovery(
            id: "glass",
            name: "Glass",
            about: "Sand went past fourteen hundred and fifty degrees and turned to glass. "
                + "This is really how glass is made.",
            hint: "Get sand very hot. Lava will do it, and so will a laser."
        ),
        Element.obsidian: Discovery(
            id: "obsidian",
            name: "Obsidian",
            about: "Lava cooled below seven hundred degrees and set into obsidian — volcanic glass. "
                + "Water does it fastest.",
            hint: "Cool lava down. Pour water on it, or just wait."
        ),
        Element.steam: Discovery(
            id: "steam",
            name: "Steam",
            about: "Water reached a hundred degrees and became steam, which rises and cools again as rain.",
            hint: "Boil water."
        ),
        Element.ice: Discovery(
            id: "ice",
            name: "Ice",
            about: "Fresh water dropped to nought and froze. Salt water will not, however cold it gets — "
                + "which is why roads get salted.",
            hint: "Make water very cold."
        ),
        Element.mud: Discovery(
            id: "mud",
            name: "Mud",
            about: "Water soaked into dirt and made mud, which flows slowly and stops flowing when it dries.",
            hint: "Pour water onto dirt."
        ),
        Element.honey: Discovery(
            id: "honey",
            name: "Honey",
            about: "Wax past sixty-five degrees went runny.",
            hint: "Warm some wax."
        ),
        Element.lava: Discovery(
            id: "lava",
            name: "Melted stone",
            about: "Stone past twelve hundred and fifty degrees melted into lava. So will obsidian, "
                + "at fourteen hundred and fifty.",
            hint: "Get stone hotter than you would think possible."
        ),
        Element.plasma: Discovery(
            id: "plasma",
            name: "Plasma",
            about: "Something got hot enough to stop being a gas at all. Plasma is what lightning "
                + "and the inside of the sun are made of.",
            hint: "An explosion, or a very great deal of heat."
        ),
        Element.thermite: Discovery(
            id: "thermite",
            name: "Thermite",
            about: "An explosion tore glass or sand apart into thermite, which burns hot enough to cut steel.",
            hint: "Set off something big next to glass."
        ),
        Element.popcorn: Discovery(
            id: "popcorn",
            name: "Popcorn",
            about: "A kernel past a hundred and eighty degrees popped, jumped, and went white and fluffy.",
            hint: "Heat a corn kernel."
        ),
        Element.foam: Discovery(
            id: "foam",
            name: "Foam",
            about: "Soap met water and turned to foam, which piles up and slowly pops.",
            hint: "Stir soap into water."
        ),
        Element.wetSponge: Discovery(
            id: "wetsponge",
            name: "A sponge that soaked",
            about: "A sponge drank the water beside it and swelled. Drop something heavy on it and it gives it back.",
            hint: "Put a sponge in water."
        ),
        Element.plant: Discovery(
            id: "plant",
            name: "Something grew",
            about: "A plant found water and grew into it. Given light and room it will keep going.",
            hint: "Give a plant some water."
        ),
        Element.stone: Discovery(
            id: "stone",
            name: "Lava set solid",
            about: "Lava chilled all at once and set as plain stone rather than obsidian. "
                + "How fast it cools decides which you get.",
            hint: "Freeze lava instead of cooling it slowly."
        ),
        Element.fire: Discovery(
            id: "fire",
            name: "Fire caught",
            about: "Something reached the temperature it catches alight at, and lit itself.",
            hint: "Heat something that burns."
        ),
    ]

    /// The ones that are a moment rather than a material.
    ///
    /// Named by hand because they are not "a material appeared" — a supernova is a thing that happens to a whole
    /// field, and an explosion is a thing that happens to a place.
    public static let moments: [Discovery] = [
        Discovery(
            id: "bigbang",
            name: "A supernova",
            about: "A star collapsed and threw everything in the field outward at once.",
            hint: "In the particle chamber, find the supernova."
        ),
        Discovery(
            id: "bigblast",
            name: "A very large explosion",
            about: "Something went off with a blast more than sixty cells across.",
            hint: "Set off nitro, or several things at once."
        ),
        Discovery(
            id: "chainreaction",
            name: "A chain reaction",
            about: "One explosion set off another, and then another — five in a row without being touched.",
            hint: "Put explosives near each other."
        ),
        Discovery(
            id: "lifeitself",
            name: "Something that looks alive",
            about: "Colours that like and dislike each other sorted themselves into things that crawl, "
                + "split and chase. Nobody designed those shapes; they are what the rules do.",
            hint: "In the particle chamber, find the one where colours have opinions."
        ),
    ]

    /// Everything, in the order the notebook shows it.
    public static let all: [Discovery] = {
        // Materials first, in the order of the list above made stable by sorting on the name — a dictionary has no
        // order, and a notebook whose pages moved about between runs would be unreadable.
        let materials = byElement.values.sorted { $0.name < $1.name }
        return materials + moments
    }()

    /// One by its name.
    public static func named(_ id: String) -> Discovery? {
        all.first { $0.id == id }
    }

    /// Which discovery a material appearing counts as, if any.
    public static func forElement(_ id: ElementID) -> Discovery? {
        byElement[id]
    }
}

/// What has been found so far.
///
/// Kept as names rather than numbers, so a build that adds or reorders discoveries does not turn somebody's notebook
/// into a different notebook. A name that no longer exists is simply not shown, and nothing is lost by keeping it.
public struct DiscoveryNotebook: Sendable, Hashable, Codable {
    public static let currentVersion = 1

    /// One page: what was found, and when.
    public struct Page: Sendable, Hashable, Codable, Identifiable {
        public var id: String { discovery }
        /// The name of the discovery. See ``Discovery/id``.
        public var discovery: String
        /// When, as seconds since the start of 1970, so it can be written down without a calendar.
        public var at: Double
        /// Which chamber it happened in.
        public var chamber: String

        public init(discovery: String, at: Double, chamber: String) {
            self.discovery = discovery
            self.at = at
            self.chamber = chamber
        }
    }

    public var version: Int
    public var pages: [Page]

    public init(version: Int = DiscoveryNotebook.currentVersion, pages: [Page] = []) {
        self.version = version
        self.pages = pages
    }

    /// Whether something has already been found.
    public func has(_ id: String) -> Bool {
        pages.contains { $0.discovery == id }
    }

    /// Writes a page, if it is not written already.
    ///
    /// - Returns: whether this was the first time. The caller uses that to decide whether to take a picture, which is
    ///   the expensive part — so "already found" has to be answered before anything is captured, not after.
    @discardableResult
    public mutating func note(_ id: String, at when: Double, chamber: String) -> Bool {
        guard Discoveries.named(id) != nil, !has(id) else { return false }
        pages.append(Page(discovery: id, at: when.isFinite ? when : 0, chamber: chamber))
        return true
    }

    /// How many of the things there are to find have been found.
    public var found: Int {
        pages.count { Discoveries.named($0.discovery) != nil }
    }

    /// How many there are altogether.
    public var howMany: Int { Discoveries.all.count }

    /// The ones still to find, in the notebook's order.
    public var stillToFind: [Discovery] {
        Discoveries.all.filter { !has($0.id) }
    }

    /// Every page that still names something this build knows about, newest first.
    public var inOrder: [Page] {
        pages.filter { Discoveries.named($0.discovery) != nil }.sorted { $0.at > $1.at }
    }
}
