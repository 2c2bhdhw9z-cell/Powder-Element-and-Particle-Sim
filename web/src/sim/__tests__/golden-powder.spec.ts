import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { mulberry32 } from "./helpers";

/**
 * Golden scenarios shared with the native port.
 *
 * The native engine (../../../native) is verified tick-for-tick against the
 * output of *this* engine, which is the behavioral specification. Hand-written
 * expectations could only prove the port matches what someone assumed; these
 * prove it matches what actually happens.
 *
 * Every scenario is restricted to sand and bedrock. That is deliberate: neither
 * element appears in any branch of `reactions.ts`, has any declarative
 * interaction, or matches any case in `updatePhase`, and at ambient temperature
 * heat diffusion has nothing to do. So the only subsystem with any effect is
 * movement, and — just as importantly — the only code drawing from the random
 * stream is movement. A scenario involving water would consume draws in
 * `reactions.ts` (the water-spread rule) and the two engines' random streams
 * would drift apart for reasons unrelated to the port's correctness.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder
 * ```
 *
 * Without that variable this file *asserts* against the committed fixture
 * instead, so it also guards against the web engine's own behavior drifting
 * unnoticed. If a deliberate physics change makes it fail, regenerate and the
 * native suite will then show the same diff.
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-powder-golden.json"
);

const SEED = 1234;
const SAND = 1;
const BEDROCK = 29;

interface Scenario {
  name: string;
  why: string;
  width: number;
  height: number;
  gravityX?: number;
  gravityY?: number;
  steps: number;
  build: (e: PowderEngine) => void;
}

const SCENARIOS: Scenario[] = [
  {
    name: "single-grain-falls",
    why: "One grain, no contention. Pins down fall speed and the resting row.",
    width: 32,
    height: 32,
    steps: 40,
    build: (e) => e.setElementAt(16, 2, SAND),
  },
  {
    name: "column-collapses",
    why:
      "A vertical column. Exercises the bottom-up scan: processed top-down the whole " +
      "column would collapse in a single tick instead of falling at a sane speed.",
    width: 32,
    height: 32,
    steps: 60,
    build: (e) => {
      for (let y = 2; y <= 9; y++) e.setElementAt(16, y, SAND);
    },
  },
  {
    name: "pile-forms-on-floor",
    why:
      "A block of sand onto a bedrock floor. The shape of the resulting pile is decided " +
      "entirely by the diagonal-slide rules and the per-row scan direction flip.",
    width: 48,
    height: 32,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 20; x <= 27; x++) for (let y = 2; y <= 9; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "slides-off-a-shelf",
    why: "Sand landing on a narrow bedrock shelf must shed off both shoulders.",
    width: 40,
    height: 36,
    steps: 100,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 16; x <= 23; x++) e.setElementAt(x, 20, BEDROCK);
      for (let x = 18; x <= 21; x++) for (let y = 4; y <= 11; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "inverted-gravity-sand-rises",
    why: "Gravity up flips the vertical scan to top-down. Sand must pile on the ceiling.",
    width: 32,
    height: 32,
    gravityY: -1,
    steps: 80,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, 0, BEDROCK);
      for (let x = 12; x <= 19; x++) for (let y = 24; y <= 27; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "zero-gravity-sand-still-settles",
    why:
      "With gravity at zero the direction comes from the fallback branch, which sends " +
      "granular solids downward anyway. Guards that fallback.",
    width: 32,
    height: 32,
    gravityY: 0,
    steps: 80,
    build: (e) => {
      for (let x = 14; x <= 17; x++) for (let y = 10; y <= 13; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "no-sideways-drift",
    why:
      "A single grain on a flat floor, run long. The per-row alternating scan direction " +
      "exists to stop exactly this grain from walking sideways forever.",
    width: 64,
    height: 24,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(32, 4, SAND);
    },
  },
  {
    name: "tall-stack-settles",
    why:
      "Enough sand to fill several rows, so cells repeatedly contend for the same space " +
      "and the visited mask is load-bearing.",
    width: 24,
    height: 40,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 19; x++) for (let y = 2; y <= 13; y++) e.setElementAt(x, y, SAND);
    },
  },
];

interface Result {
  name: string;
  why: string;
  width: number;
  height: number;
  gravityX: number;
  gravityY: number;
  steps: number;
  seed: number;
  /** Cells that were painted before stepping, as [x, y, elementId] triples. */
  setup: [number, number, number][];
  /**
   * Element ids after stepping, one comma-separated string per grid row.
   *
   * Stored row-wise rather than as one flat array so a failing diff points at
   * the row that changed, and so the file stays a manageable size.
   */
  typeRows: string[];
  /**
   * Momentum after stepping, as [index, velocityX, velocityY] for the cells
   * where either is non-zero. Sparse because in these scenarios almost nothing
   * carries momentum, and a full grid of zeroes would dwarf the useful data.
   */
  velocityNonZero: [number, number, number][];
  activeCount: number;
  hashLite: number;
  /** How many times the engine drew from the random stream. */
  randomDraws: number;
}

function toRows(values: Uint16Array, width: number, height: number): string[] {
  const rows: string[] = [];
  for (let y = 0; y < height; y++) {
    rows.push(Array.from(values.subarray(y * width, (y + 1) * width)).join(","));
  }
  return rows;
}

function sparseVelocity(vx: Int8Array, vy: Int8Array): [number, number, number][] {
  const out: [number, number, number][] = [];
  for (let i = 0; i < vx.length; i++) {
    if (vx[i] !== 0 || vy[i] !== 0) out.push([i, vx[i], vy[i]]);
  }
  return out;
}

/** Records the cells a scenario paints, so the native side sets up identically. */
function recordSetup(scenario: Scenario): [number, number, number][] {
  const painted: [number, number, number][] = [];
  const recorder = new PowderEngine(scenario.width, scenario.height);
  const original = recorder.setElementAt.bind(recorder);
  recorder.setElementAt = (x: number, y: number, id: number, temp?: number, life?: number) => {
    painted.push([x, y, id]);
    original(x, y, id, temp, life);
  };
  scenario.build(recorder);
  return painted;
}

function run(scenario: Scenario): Result {
  const setup = recordSetup(scenario);

  // Seed the global generator and count every draw the engine makes. The count
  // is as valuable as the grid: a port that produces the right picture while
  // consuming a different number of random numbers has diverged and will drift
  // apart on some other scenario later.
  let randomDraws = 0;
  const source = mulberry32(SEED);
  const previous = Math.random;
  Math.random = () => {
    randomDraws++;
    return source();
  };

  try {
    const e = new PowderEngine(scenario.width, scenario.height);
    if (scenario.gravityX !== undefined) e.gravityX = scenario.gravityX;
    if (scenario.gravityY !== undefined) e.gravityY = scenario.gravityY;
    scenario.build(e);
    for (let i = 0; i < scenario.steps; i++) e.step();

    return {
      name: scenario.name,
      why: scenario.why,
      width: scenario.width,
      height: scenario.height,
      gravityX: e.gravityX,
      gravityY: e.gravityY,
      steps: scenario.steps,
      seed: SEED,
      setup,
      typeRows: toRows(e.gridType, scenario.width, scenario.height),
      velocityNonZero: sparseVelocity(e.gridVx, e.gridVy),
      activeCount: e.getActiveParticleCount(),
      hashLite: e.hashLite(),
      randomDraws,
    };
  } finally {
    Math.random = previous;
  }
}

describe("golden powder scenarios", () => {
  const results = SCENARIOS.map(run);

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. " +
              "Regenerate with: cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder",
            scenarios: results,
          },
          null,
          2
        ) + "\n"
      );
      expect(results.length).toBe(SCENARIOS.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { scenarios: Result[] };
    expect(fixture.scenarios.length).toBe(results.length);
    for (let i = 0; i < results.length; i++) {
      expect(results[i].name).toBe(fixture.scenarios[i].name);
      expect(results[i].typeRows).toEqual(fixture.scenarios[i].typeRows);
      expect(results[i].velocityNonZero).toEqual(fixture.scenarios[i].velocityNonZero);
      expect(results[i].randomDraws).toBe(fixture.scenarios[i].randomDraws);
      expect(results[i].hashLite).toBe(fixture.scenarios[i].hashLite);
    }
  });

  it("every scenario actually moved something", () => {
    for (const result of results) {
      expect(result.activeCount).toBeGreaterThan(0);
      expect(result.randomDraws).toBeGreaterThan(0);
    }
  });
});
