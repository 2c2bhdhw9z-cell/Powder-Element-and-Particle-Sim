import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import {
  finishPowderEvent,
  startPowderEvent,
  type PowderEventId,
  type PowderEventStart,
} from "@/sim/powder-events";
import { mulberry32 } from "./helpers";

/**
 * The four set-piece events, recorded cell by cell through both of their halves.
 *
 * These lived inside the canvas component until now, which is the only reason they are the last
 * part of the simulation to be checked. They are dense with unexplained constants — a disc of
 * radius ten at a depth of fourteen, an explosion at 0.65 of the world's height, a water band
 * from 0.28 down to two from the bottom, four element substitutions at −200°C — and every one of
 * them is the kind of number that can be transposed without the result ceasing to look like an
 * explosion.
 *
 * ## Why the shake and sound are recorded too
 *
 * They are returned rather than performed, so they are data, and data can be wrong. A meteor that
 * silently stopped asking for its sound would be a real regression that no picture of the grid
 * would reveal.
 *
 * ## Why several sizes
 *
 * The same reason as the scenes. Every one of these events computes positions from the world's
 * dimensions, and three of the four can address cells outside a small world — the surge's band
 * inverts entirely below about forty cells tall, and a naive port crashes there rather than doing
 * nothing. The cramped sizes are the ones under test.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-events
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-events-golden.json"
);

const SEED = 20260924;

const EVENTS: PowderEventId[] = ["meteor", "blast", "surge", "freeze"];

/**
 * The sizes each event is recorded at.
 *
 * 30x24 is the important one: it is smaller than the meteor's own disc and far below the surge's
 * band, so almost everything in these functions has to clip or decline to run.
 */
const SIZES: [number, number][] = [
  [120, 90],
  [64, 48],
  [30, 24],
  [200, 40], // Wide and shallow, collapsing the vertical fractions onto each other.
];

interface Result {
  event: string;
  width: number;
  height: number;
  seed: number;
  /** Element ids after both halves have run, one comma-separated string per row. */
  typeRows: string[];
  /** Temperatures away from ambient, as `index:value` with two decimals. */
  temperatures: string[];
  /** Non-zero lifetimes, as `index:value`. */
  lifetimes: string[];
  /** Non-zero momentum, as `index:vx,vy`. The surge and the meteor both set it directly. */
  momentum: string[];
  activeCount: number;
  /** How many random numbers the pair of halves consumed. */
  randomDraws: number;
  /** What the event asked the app to do, which is part of its definition. */
  start: PowderEventStart;
}

function toRows(values: Uint16Array, width: number, height: number): string[] {
  const rows: string[] = [];
  for (let y = 0; y < height; y++) {
    rows.push(Array.from(values.subarray(y * width, (y + 1) * width)).join(","));
  }
  return rows;
}

function sparseTemperatures(values: Float32Array, ambient: number): string[] {
  const out: string[] = [];
  const ambientText = ambient.toFixed(2);
  for (let i = 0; i < values.length; i++) {
    const text = values[i].toFixed(2);
    if (text !== ambientText) out.push(`${i}:${text}`);
  }
  return out;
}

function sparseLifetimes(values: Uint16Array): string[] {
  const out: string[] = [];
  for (let i = 0; i < values.length; i++) {
    if (values[i] !== 0) out.push(`${i}:${values[i]}`);
  }
  return out;
}

function sparseMomentum(vx: Int8Array, vy: Int8Array): string[] {
  const out: string[] = [];
  for (let i = 0; i < vx.length; i++) {
    if (vx[i] !== 0 || vy[i] !== 0) out.push(`${i}:${vx[i]},${vy[i]}`);
  }
  return out;
}

function run(event: PowderEventId, width: number, height: number): Result {
  const source = mulberry32(SEED);
  let randomDraws = 0;
  const previous = Math.random;
  Math.random = () => {
    randomDraws++;
    return source();
  };

  try {
    const engine = new PowderEngine(width, height);
    // A floor and a little material, so a freeze has something to convert and an explosion has
    // something to throw. Laid down deterministically rather than at random, so the fixture
    // records the event's own draws and nothing else.
    for (let x = 0; x < width; x++) engine.setElementAt(x, height - 1, 29);
    for (let x = 0; x < width; x += 3) {
      const y = height - 2;
      if (engine.isValid(x, y)) engine.setElementAt(x, y, 2); // water, to become ice
      if (engine.isValid(x + 1, y)) engine.setElementAt(x + 1, y, 6); // lava, to become stone
      if (engine.isValid(x + 2, y)) engine.setElementAt(x + 2, y, 1); // sand, to be thrown
    }

    const drawsBeforeEvent = randomDraws;
    randomDraws = 0;
    void drawsBeforeEvent;

    const start = startPowderEvent(engine, event);
    // Both halves, because the delay is presentation and the second half is as much part of the
    // event as the first. The delay itself is recorded in `start.followUp`.
    if (start.followUp) finishPowderEvent(engine, start.followUp);

    return {
      event,
      width,
      height,
      seed: SEED,
      typeRows: toRows(engine.gridType, width, height),
      temperatures: sparseTemperatures(engine.gridTemp, engine.ambientTemp),
      lifetimes: sparseLifetimes(engine.gridLife),
      momentum: sparseMomentum(engine.gridVx, engine.gridVy),
      activeCount: engine.getActiveParticleCount(),
      randomDraws,
      start,
    };
  } finally {
    Math.random = previous;
  }
}

describe("golden powder events", () => {
  const results: Result[] = [];
  for (const event of EVENTS) {
    for (const [width, height] of SIZES) {
      results.push(run(event, width, height));
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
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-events",
            events: results,
          },
          null,
          2
        ) + "\n"
      );
      expect(results.length).toBe(EVENTS.length * SIZES.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { events: Result[] };
    expect(fixture.events.length).toBe(results.length);
    for (let i = 0; i < results.length; i++) {
      const actual = results[i];
      const expected = fixture.events[i];
      const label = `${actual.event}@${actual.width}x${actual.height}`;
      expect(`${expected.event}@${expected.width}x${expected.height}`).toBe(label);
      expect(actual.typeRows, `${label} grid`).toEqual(expected.typeRows);
      expect(actual.temperatures, `${label} temperatures`).toEqual(expected.temperatures);
      expect(actual.lifetimes, `${label} lifetimes`).toEqual(expected.lifetimes);
      expect(actual.momentum, `${label} momentum`).toEqual(expected.momentum);
      expect(actual.activeCount, `${label} active count`).toBe(expected.activeCount);
      expect(actual.randomDraws, `${label} random draws`).toBe(expected.randomDraws);
      expect(actual.start, `${label} accompaniment`).toEqual(expected.start);
    }
  });
});
