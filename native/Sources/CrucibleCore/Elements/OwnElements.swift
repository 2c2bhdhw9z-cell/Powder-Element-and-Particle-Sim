/// The materials this app has that the web reference does not.
///
/// ## Why they are in a file of their own
///
/// Because the fifty in `DefaultElements` are not a list of good ideas — they are a *recording*. Every property of
/// every one of them is compared, value by value, against data extracted from the reference implementation, which
/// is how the port proves it behaves the same way. Adding to that list would break the comparison and lose the
/// proof.
///
/// So the recording stays exactly as it is, and anything new lives here, at identifiers above the range kept for
/// the elements people invent themselves. The port's fidelity is still provable, and the app is not frozen at
/// whatever the reference happened to have.
extension DefaultElements {
    /// This app's own materials, in identifier order. The array's order does not have to match the identifiers, and
    /// is not indexed by them — the registry places each one by its own `id`.
    public static let own: [ElementDefinition] = [
        // MARK: Popcorn

        ElementDefinition(
            id: Element.kernel,
            name: "Corn Kernel",
            category: .biological,
            state: .solidMovable,
            hex: "#C9A227",
            colorVariation: 18,
            density: 14,
            flammability: 18,
            // Hot enough and the water inside it turns to steam and bursts it open. That is what popping is, and
            // the temperature is roughly the real one.
            ignitionTemp: nil,
            info: "Heat it and it pops."
        ),
        ElementDefinition(
            id: Element.popcorn,
            name: "Popcorn",
            category: .biological,
            state: .solidMovable,
            hex: "#FFF6E0",
            colorVariation: 12,
            // Far lighter than the kernel it came from, which is why a popped pile climbs out of the pan.
            density: 3,
            flammability: 42,
            info: "Light, fluffy, and burns easily."
        ),

        // MARK: Soap and foam

        ElementDefinition(
            id: Element.soap,
            name: "Soap",
            category: .liquids,
            state: .liquid,
            hex: "#7DD3C0",
            colorVariation: 6,
            density: 22,
            viscosity: 3,
            acidResistance: 10,
            info: "Stirred into water it foams up."
        ),
        ElementDefinition(
            id: Element.foam,
            name: "Foam",
            category: .liquids,
            state: .liquid,
            hex: "#E8FBF6",
            colorVariation: 10,
            // Lighter than water, so it climbs to the top of whatever it is in and sits there.
            density: 4,
            viscosity: 6,
            // Bubbles do not last. Left alone it thins back to a little water.
            decayTicks: 520,
            decayIntoID: Element.water,
            info: "Piles up, floats, and slowly pops back to water."
        ),

        // MARK: Sponge

        ElementDefinition(
            id: Element.sponge,
            name: "Sponge",
            category: .solids,
            state: .solidMovable,
            hex: "#D9A86C",
            colorVariation: 14,
            density: 60,
            flammability: 30,
            info: "Soaks up water until it is full."
        ),
        ElementDefinition(
            id: Element.wetSponge,
            name: "Wet Sponge",
            category: .solids,
            state: .solidMovable,
            hex: "#8A6A3F",
            colorVariation: 12,
            density: 72,
            // Wet things do not catch.
            flammability: 0,
            info: "Full of water. Squash it and it drips."
        ),

        // MARK: Conveyor belt

        ElementDefinition(
            id: Element.belt,
            name: "Belt",
            category: .special,
            state: .solidFixed,
            hex: "#4B5563",
            colorVariation: 6,
            // As immovable as stone, because it is machinery: it carries things, it does not fall.
            density: 900,
            acidResistance: 60,
            isConductor: false,
            info: "Carries whatever lands on it. Paint it again to turn it round."
        ),

        // MARK: Magnet and iron dust

        ElementDefinition(
            id: Element.magnet,
            name: "Magnet",
            category: .special,
            state: .solidFixed,
            hex: "#9B1C31",
            colorVariation: 4,
            density: 900,
            acidResistance: 40,
            isConductor: true,
            info: "Iron dust reaches toward it and stands up in spikes."
        ),
        ElementDefinition(
            id: Element.ironDust,
            name: "Iron Dust",
            category: .solids,
            state: .solidMovable,
            hex: "#6B7280",
            colorVariation: 16,
            density: 30,
            acidResistance: 5,
            heatConductivity: 40,
            isConductor: true,
            info: "Ordinary dust until there is a magnet near it."
        ),
    ]
}
