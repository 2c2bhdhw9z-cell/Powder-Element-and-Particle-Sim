#!/usr/bin/env node
/**
 * Writes the native encyclopedia and periodic drawer from the recorded fixture.
 *
 * ## Why this is generated rather than written
 *
 * It is fifty short descriptions plus twenty-four element mappings — a few hundred short strings
 * with degree signs, typographic apostrophes, arrows and subscript digits in them. Moving that
 * across by hand is a few hours of transcription and a near-certainty of at least one silent
 * error: a melting point off by a digit, or a card attached to the element next to the one it
 * describes. Nothing misbehaves when that happens, so nothing ever finds it.
 *
 * Generating it removes the transcription step entirely, and `LoreTests` then checks the result
 * against the same fixture — so the two can never drift even if someone edits the generated file
 * by hand.
 *
 * ## Running it
 *
 *   cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-lore
 *   node scripts/generate-lore.mjs
 *   cd native && swift test --filter Lore
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");
const FIXTURE = resolve(root, "native/Tests/CrucibleCoreTests/Fixtures/web-lore-golden.json");
const OUT = resolve(root, "native/Sources/CrucibleCore/Elements/Encyclopedia.swift");

/** A Swift string literal. Only backslashes and double quotes need escaping; the rest is UTF-8. */
function swiftString(value) {
  return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}

/** An optional Swift string literal. */
function swiftOptional(value) {
  return value === null || value === undefined ? "nil" : swiftString(value);
}

const fixture = JSON.parse(readFileSync(FIXTURE, "utf8"));

const header = `// GENERATED FILE — do not edit by hand.
//
// Written by scripts/generate-lore.mjs from
// Tests/CrucibleCoreTests/Fixtures/web-lore-golden.json, which is itself recorded from the
// reference implementation's encyclopedia.ts and periodic.ts.
//
// To change any of this text, change it in the web version, re-record the fixture, and run the
// generator again:
//
//     cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-lore
//     node scripts/generate-lore.mjs
//     cd native && swift test --filter Lore
//
// Generated rather than transcribed because it is several hundred short strings full of degree
// signs, typographic apostrophes and arrows, and a single mistyped melting point — or a card
// attached to the element next to the one it describes — would never misbehave and so would never
// be found. LoreTests holds this file to the fixture, so editing it here instead fails loudly.

/// What the encyclopedia says about one element.
///
/// Separate from \`ElementDefinition\` because it is prose for a reader rather than anything the
/// simulation consults: the melting point here is a phrase like "700°C solidify" or "never",
/// written to be understood, not the number the physics actually uses.
public struct ElementLore: Sendable, Hashable {
    /// How this element melts, as a phrase. Absent where the idea does not apply.
    public var melt: String?
    /// How it boils. Present on only a handful.
    public var boil: String?
    /// What it consumes or destroys.
    public var eats: String
    /// The one thing worth knowing about using it.
    public var note: String
}

/// The encyclopedia.
public enum Encyclopedia {
    /// The card for an element, or a general one for anything user-authored.
    ///
    /// A custom element has no card written for it, and inventing one would be worse than
    /// admitting there is none — so this points the reader at the properties they can actually
    /// see on the palette.
    public static func lore(for id: ElementID) -> ElementLore {
        cards[id] ?? fallback
    }

    /// Whether an element has a card of its own, as opposed to the general one.
    public static func hasOwnCard(for id: ElementID) -> Bool {
        cards[id] != nil
    }

    public static let fallback = ElementLore(
        melt: nil,
        boil: nil,
        eats: "See density and flammability on the palette.",
        note: "No extra card yet."
    )

    /// One card per built-in element.
`;

let out = header;
out += "    public static let cards: [ElementID: ElementLore] = [\n";
for (const entry of fixture.lore) {
  out += `        ${entry.id}: ElementLore(`;
  out += `melt: ${swiftOptional(entry.melt)}, `;
  out += `boil: ${swiftOptional(entry.boil)}, `;
  out += `eats: ${swiftString(entry.eats)}, `;
  out += `note: ${swiftString(entry.note)}`;
  out += `),  // ${entry.name}\n`;
}
out += "    ]\n}\n\n";

out += `/// A real-world substance, and the lab material that stands in for it.
///
/// The drawer's whole premise is that the lab cannot simulate chemistry, so it maps something
/// recognisable onto the closest thing it can. Several entries map to the same material — iron,
/// silver, tin, tungsten, platinum, gold and aluminium are all simply "metal" — and that is
/// honest rather than lazy: the alternative is pretending to a distinction the physics does not
/// make.
public struct PeriodicEntry: Sendable, Hashable, Identifiable {
    /// Atomic number. Zero for a compound, which has none.
    public var atomicNumber: Int
    /// Chemical symbol, which for the compounds uses real subscript digits.
    public var symbol: String
    public var name: String
    /// The lab element this stands in for.
    public var mapsTo: ElementID
    /// Why that substitution, in a few words.
    public var why: String

    public var id: String { "\\(atomicNumber)-\\(symbol)" }

    /// Whether this is a compound rather than a single element.
    public var isCompound: Bool { atomicNumber == 0 }
}

/// The periodic drawer.
///
/// Not laid out as the real table. The reference presents it as two simple grids, and eighteen
/// scattered elements would leave an eighteen-column periodic layout almost entirely empty.
public enum PeriodicTable {
`;

out += "    /// The single elements, in order of atomic number.\n";
out += "    public static let elements: [PeriodicEntry] = [\n";
for (const item of fixture.periodic) {
  out += `        PeriodicEntry(atomicNumber: ${item.z}, symbol: ${swiftString(item.symbol)}, name: ${swiftString(item.name)}, mapsTo: ${item.mapsTo}, why: ${swiftString(item.why)}),\n`;
}
out += "    ]\n\n";

out += "    /// The compounds, which have no atomic number.\n";
out += "    public static let compounds: [PeriodicEntry] = [\n";
for (const item of fixture.compounds) {
  out += `        PeriodicEntry(atomicNumber: ${item.z}, symbol: ${swiftString(item.symbol)}, name: ${swiftString(item.name)}, mapsTo: ${item.mapsTo}, why: ${swiftString(item.why)}),\n`;
}
out += "    ]\n";
out += "}\n";

writeFileSync(OUT, out);
console.log(
  `Wrote ${OUT}\n  ${fixture.lore.length} cards, ${fixture.periodic.length} elements, ${fixture.compounds.length} compounds`
);
