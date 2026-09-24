import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { loreFor } from "@/sim/encyclopedia";
import { COMPOUNDS, PERIODIC } from "@/sim/periodic";
import { DEFAULT_ELEMENTS } from "@/sim/element-registry";

/**
 * The reference text: one lore card per built-in element, and the periodic drawer's mappings.
 *
 * Unlike every other fixture here this records *writing* rather than behaviour — fifty short
 * descriptions, eighteen real elements mapped onto lab materials, and six compounds. There is no
 * physics to compare, but there is every opportunity to mistype something while moving it across,
 * and a wrong melting point or a card attached to the wrong element is the kind of error that
 * survives indefinitely because nothing misbehaves.
 *
 * So the native copy is **generated** from this fixture rather than retyped, and this suite is
 * what proves the generated copy still says what the reference says.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-lore
 * node ../scripts/generate-lore.mjs          # writes the Swift
 * cd ../native && swift test --filter Lore
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-lore-golden.json"
);

interface Entry {
  id: number;
  name: string;
  melt: string | null;
  boil: string | null;
  eats: string;
  note: string;
}

interface Mapping {
  z: number;
  symbol: string;
  name: string;
  mapsTo: number;
  why: string;
}

function collect(): { lore: Entry[]; periodic: Mapping[]; compounds: Mapping[] } {
  const lore: Entry[] = [];
  // Every built-in, by id, so a gap in the table shows up as a missing entry rather than as a
  // silently shorter list.
  for (const element of DEFAULT_ELEMENTS) {
    if (element.id >= 50) continue;
    const card = loreFor(element.id);
    lore.push({
      id: element.id,
      name: element.name,
      melt: card.melt ?? null,
      boil: card.boil ?? null,
      eats: card.eats,
      note: card.note,
    });
  }
  lore.sort((a, b) => a.id - b.id);
  return { lore, periodic: PERIODIC, compounds: COMPOUNDS };
}

describe("golden encyclopedia and periodic drawer", () => {
  const collected = collect();

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. Regenerate with: " +
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-lore",
            ...collected,
          },
          null,
          2
        ) + "\n"
      );
      expect(collected.lore.length).toBeGreaterThan(0);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as ReturnType<typeof collect>;
    expect(collected.lore).toEqual(fixture.lore);
    expect(collected.periodic).toEqual(fixture.periodic);
    expect(collected.compounds).toEqual(fixture.compounds);
  });

  it("every built-in element has a card of its own", () => {
    // The fallback exists for user-authored elements. A built-in reaching it means a card is
    // missing, which shows up in the app as a blank description rather than as an error.
    const fallback = loreFor(9999);
    for (const entry of collected.lore) {
      expect(
        entry.eats === fallback.eats && entry.note === fallback.note,
        `element ${entry.id} (${entry.name}) has no card of its own`
      ).toBe(false);
    }
  });

  it("every periodic mapping points at an element that exists", () => {
    const ids = new Set(DEFAULT_ELEMENTS.map((e) => e.id));
    for (const item of [...collected.periodic, ...collected.compounds]) {
      expect(ids.has(item.mapsTo), `${item.symbol} maps to missing element ${item.mapsTo}`).toBe(
        true
      );
    }
  });
});
