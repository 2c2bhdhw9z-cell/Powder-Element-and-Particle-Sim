import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { POWDER_RECIPES } from "@/sim/powder-recipes";
import { mulberry32 } from "./helpers";

/**
 * Every built-in scene, laid out and recorded cell by cell.
 *
 * Thirteen scenes of dense geometry — cones, tunnels, reactor vessels, three rows of
 * falling snow — every one built from fractions of the world's size with its own
 * collection of magic constants. That is precisely the kind of code where a single
 * transposed number survives review and is never noticed, because the result still looks
 * like a volcano. So rather than trusting the native port to be a faithful transcription,
 * it is held to producing the identical grid.
 *
 * ## Why several sizes
 *
 * Each scene is recorded at four. A large world exercises the intended layout; a cramped
 * one exercises all the clipping, clamping and `max(…)` guards that only matter when the
 * arithmetic produces a position outside the grid — which is where the two
 * implementations are most likely to disagree, and where nobody looks.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-recipes
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-recipes-golden.json"
);

/** Seed for the one scene that scatters things at random. */
const SEED = 1234;

/**
 * The sizes each scene is recorded at.
 *
 * The 20x16 case is the interesting one: most scenes compute positions that fall outside
 * a world that small, so it is the clipping that is under test rather than the layout.
 */
const SIZES: [number, number][] = [
  [120, 90],
  [64, 48],
  [20, 16],
  [200, 40], // Wide and shallow, so the vertical fractions collapse onto each other.
];

interface Result {
  id: string;
  name: string;
  width: number;
  height: number;
  seed: number;
  /** Element ids after laying the scene out, one comma-separated string per row. */
  typeRows: string[];
  /**
   * Temperatures that are not the world's ambient, as `index:value` with two decimals.
   *
   * Sparse because these scenes are mostly at ambient, and writing every cell out in full
   * made this fixture five times larger than the grid data it sits beside — for a file
   * that is regenerated from time to time and committed each time.
   */
  temperatures: string[];
  /**
   * Remaining lifetimes that are not zero, as `index:value`.
   *
   * A lifetime of zero on something that decays means it vanishes on the very next tick, so
   * these decide whether the fire and smoke a scene places survive at all.
   */
  lifetimes: string[];
  activeCount: number;
  /** How many numbers the scene drew. Zero for all but Remix. */
  randomDraws: number;
}

function toRows(values: Uint16Array, width: number, height: number): string[] {
  const rows: string[] = [];
  for (let y = 0; y < height; y++) {
    rows.push(Array.from(values.subarray(y * width, (y + 1) * width)).join(","));
  }
  return rows;
}

/** Cells whose temperature differs from ambient, as `index:value`. */
function sparseTemperatures(values: Float32Array, ambient: number): string[] {
  const out: string[] = [];
  const ambientText = ambient.toFixed(2);
  for (let i = 0; i < values.length; i++) {
    const text = values[i].toFixed(2);
    if (text !== ambientText) out.push(`${i}:${text}`);
  }
  return out;
}

/** Cells with a lifetime left to run, as `index:value`. */
function sparseLifetimes(values: Uint16Array): string[] {
  const out: string[] = [];
  for (let i = 0; i < values.length; i++) {
    if (values[i] !== 0) out.push(`${i}:${values[i]}`);
  }
  return out;
}

function run(recipe: (typeof POWDER_RECIPES)[number], width: number, height: number): Result {
  // The generator is handed in rather than replacing the global one, because that is how
  // the daily scene makes itself reproducible and it is the path worth testing.
  const source = mulberry32(SEED);
  let randomDraws = 0;
  const counted = () => {
    randomDraws++;
    return source();
  };

  // The global source is also replaced, so that anything reaching for it by mistake shows
  // up as a difference rather than as flakiness.
  const previous = Math.random;
  Math.random = () => {
    throw new Error(`${recipe.id} reached for the global random source`);
  };

  try {
    const engine = new PowderEngine(width, height);
    recipe.run(engine, counted);
    return {
      id: recipe.id,
      name: recipe.name,
      width,
      height,
      seed: SEED,
      typeRows: toRows(engine.gridType, width, height),
      temperatures: sparseTemperatures(engine.gridTemp, engine.ambientTemp),
      lifetimes: sparseLifetimes(engine.gridLife),
      activeCount: engine.getActiveParticleCount(),
      randomDraws,
    };
  } finally {
    Math.random = previous;
  }
}

describe("golden powder recipes", () => {
  const results: Result[] = [];
  for (const recipe of POWDER_RECIPES) {
    for (const [width, height] of SIZES) {
      results.push(run(recipe, width, height));
    }
  }

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. Regenerate with: " +
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-recipes",
            scenes: results,
          },
          null,
          2
        ) + "\n"
      );
      expect(results.length).toBe(POWDER_RECIPES.length * SIZES.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { scenes: Result[] };
    expect(fixture.scenes.length).toBe(results.length);
    for (let i = 0; i < results.length; i++) {
      const actual = results[i];
      const expected = fixture.scenes[i];
      expect(`${actual.id}@${actual.width}x${actual.height}`).toBe(
        `${expected.id}@${expected.width}x${expected.height}`
      );
      expect(actual.typeRows).toEqual(expected.typeRows);
      expect(actual.temperatures).toEqual(expected.temperatures);
      expect(actual.lifetimes).toEqual(expected.lifetimes);
      expect(actual.randomDraws).toBe(expected.randomDraws);
    }
  });

  it("every scene puts something in the world", () => {
    for (const result of results) {
      expect(result.activeCount, `${result.id} at ${result.width}x${result.height} is empty`)
        .toBeGreaterThan(0);
    }
  });

  it("only Remix consults the random source, and always the same number of times", () => {
    for (const result of results) {
      if (result.id === "remix") {
        // One draw to pick the underlying scene, then three per scattered cell.
        expect(result.randomDraws, `remix at ${result.width}x${result.height}`).toBe(1 + 40 * 3);
      } else {
        expect(result.randomDraws, `${result.id} should be fully deterministic`).toBe(0);
      }
    }
  });
});
