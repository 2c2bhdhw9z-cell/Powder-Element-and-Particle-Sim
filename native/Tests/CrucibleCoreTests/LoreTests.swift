import Foundation
import Testing

@testable import CrucibleCore

/// Holds the encyclopedia and the periodic drawer to the reference implementation's text.
///
/// `Encyclopedia.swift` is generated rather than written, by `scripts/generate-lore.mjs`, because
/// it is several hundred short strings full of degree signs, typographic apostrophes, arrows and
/// subscript digits. Transcribing that by hand is hours of work and a near-certainty of at least
/// one silent error — a melting point off by a digit, or a card attached to the element beside the
/// one it describes. Nothing misbehaves when that happens, which is exactly why nothing ever finds
/// it.
///
/// Generating it removes the transcription. This suite is what stops the generated file drifting
/// afterwards: edit it by hand and these fail, naming what changed.
@Suite("The encyclopedia matches the reference text")
struct LoreTests {
    struct Entry: Decodable {
        var id: ElementID
        var name: String
        var melt: String?
        var boil: String?
        var eats: String
        var note: String
    }

    struct Mapping: Decodable {
        var z: Int
        var symbol: String
        var name: String
        var mapsTo: ElementID
        var why: String
    }

    struct Fixture: Decodable {
        var note: String
        var lore: [Entry]
        var periodic: [Mapping]
        var compounds: [Mapping]
    }

    static let fixture: Fixture = {
        guard let url = Bundle.module.url(
            forResource: "web-lore-golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "web-lore-golden", withExtension: "json") else {
            fatalError("Fixture web-lore-golden.json is missing from the test bundle")
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: try Data(contentsOf: url))
        } catch {
            fatalError("Could not decode the golden lore fixture: \(error)")
        }
    }()

    // MARK: Cards

    @Test("Every card says exactly what the reference says")
    func cardsMatch() {
        for entry in Self.fixture.lore {
            let card = Encyclopedia.lore(for: entry.id)
            let label = "element \(entry.id) (\(entry.name))"
            #expect(card.melt == entry.melt, "\(label): melting point")
            #expect(card.boil == entry.boil, "\(label): boiling point")
            #expect(card.eats == entry.eats, "\(label): what it eats")
            #expect(card.note == entry.note, "\(label): note")
        }
    }

    @Test("There are no cards the reference does not have, and none missing")
    func cardCountMatches() {
        #expect(Encyclopedia.cards.count == Self.fixture.lore.count)
        let expected = Set(Self.fixture.lore.map(\.id))
        let actual = Set(Encyclopedia.cards.keys)
        #expect(actual == expected, "extra: \(actual.subtracting(expected)), missing: \(expected.subtracting(actual))")
    }

    /// Every built-in must have writing of its own. Reaching the general card is not an error the
    /// app can show — it just looks like an element nobody bothered to describe.
    @Test("Every built-in element has a card of its own")
    func everyBuiltInHasACard() {
        let registry = ElementRegistry()
        for definition in registry.allElements where definition.id < Element.customIDStart {
            #expect(
                Encyclopedia.hasOwnCard(for: definition.id),
                "element \(definition.id) (\(definition.name)) has no card"
            )
        }
    }

    /// And a user-authored element must reach the general one rather than nothing at all.
    @Test("A custom element gets the general card")
    func customElementsGetTheFallback() {
        let card = Encyclopedia.lore(for: 73)
        #expect(card == Encyclopedia.fallback)
        #expect(!Encyclopedia.hasOwnCard(for: 73))
        #expect(card.melt == nil)
        // Points at what the reader can actually see, rather than inventing a description.
        #expect(card.eats.contains("palette"))
    }

    // MARK: Periodic drawer

    @Test("The periodic drawer matches, in order")
    func periodicMatches() {
        #expect(PeriodicTable.elements.count == Self.fixture.periodic.count)
        for (actual, expected) in zip(PeriodicTable.elements, Self.fixture.periodic) {
            #expect(actual.atomicNumber == expected.z, "\(expected.symbol): atomic number")
            #expect(actual.symbol == expected.symbol, "\(expected.symbol): symbol")
            #expect(actual.name == expected.name, "\(expected.symbol): name")
            #expect(actual.mapsTo == expected.mapsTo, "\(expected.symbol): what it maps to")
            #expect(actual.why == expected.why, "\(expected.symbol): reason")
        }
    }

    @Test("The compounds match, in order")
    func compoundsMatch() {
        #expect(PeriodicTable.compounds.count == Self.fixture.compounds.count)
        for (actual, expected) in zip(PeriodicTable.compounds, Self.fixture.compounds) {
            #expect(actual.symbol == expected.symbol, "\(expected.symbol): symbol")
            #expect(actual.name == expected.name, "\(expected.symbol): name")
            #expect(actual.mapsTo == expected.mapsTo, "\(expected.symbol): what it maps to")
            #expect(actual.why == expected.why, "\(expected.symbol): reason")
            #expect(actual.isCompound, "\(expected.symbol) should be marked a compound")
        }
    }

    /// A mapping pointing at an element that does not exist would give the drawer a tappable cell
    /// that silently selects nothing.
    @Test("Every mapping points at an element that exists")
    func mappingsResolve() {
        let registry = ElementRegistry()
        let table = registry.table
        for entry in PeriodicTable.elements + PeriodicTable.compounds {
            #expect(
                table[entry.mapsTo].isDefined,
                "\(entry.symbol) maps to element \(entry.mapsTo), which is not registered"
            )
        }
    }

    /// The subscript digits are the reason this file is generated rather than typed. A compound
    /// whose symbol came across as "H2O" would look almost right, which is the worst outcome.
    @Test("The compounds keep their subscript digits")
    func subscriptsSurvived() {
        let symbols = PeriodicTable.compounds.map(\.symbol)
        #expect(symbols.contains("H₂O"))
        #expect(symbols.contains("SiO₂"))
        #expect(symbols.contains("C₄"))
        for symbol in symbols {
            // No ordinary digits should have crept in where a subscript belongs.
            #expect(
                !symbol.contains(where: { $0.isNumber && $0.isASCII }),
                "\(symbol) has a plain digit where a subscript belongs"
            )
        }
    }

    /// Likewise the punctuation. An apostrophe that came across as a straight quote would be a
    /// silent downgrade in something the reader looks straight at.
    @Test("The typographic punctuation survived")
    func punctuationSurvived() {
        var allText = ""
        for card in Encyclopedia.cards.values {
            allText += card.eats
            allText += card.note
            allText += card.melt ?? ""
            allText += card.boil ?? ""
        }
        #expect(allText.contains("’"), "the typographic apostrophes are gone")
        #expect(allText.contains("—"), "the em dashes are gone")
        #expect(allText.contains("°C"), "the degree signs are gone")
        #expect(allText.contains("→"), "the arrows are gone")
    }
}
