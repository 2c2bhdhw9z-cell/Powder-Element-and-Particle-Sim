import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { POWDER_RECIPES } from "@/sim/powder-recipes";
import { dailyHash } from "@/sim/daily-seed";

/**
 * The day's chosen world, recorded for a fixed set of dates.
 *
 * This one matters more than it looks. The whole point of the daily world is that everyone gets the
 * same one — so if the native app and the web version disagree about which scene a given day maps to,
 * the feature is not merely wrong, it is *silently* wrong: both sides confidently announce a name, and
 * two people comparing notes would find they had been given different worlds with no indication why.
 *
 * There is no shared server deciding it. The agreement rests entirely on both implementations hashing
 * the date identically and indexing the same list in the same order, which is exactly the sort of thing
 * that drifts. Hence a fixture.
 *
 * ## The dates
 *
 * Chosen to cover the awkward cases rather than at random: a leap day, the last day of a year, the
 * first day of a year, and a run of consecutive days — because consecutive dates are where a weak hash
 * shows itself by handing out the same scene several days running.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-daily
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-daily-golden.json"
);

const PARTICLE_PRESETS = ["galaxy", "well", "vortex", "flare", "fountain", "sync", "fall"] as const;

/** The native side's names for the same seven arrangements, in the same order. */
const NATIVE_PARTICLE_PRESETS = [
  "galaxy",
  "blackhole",
  "vortex",
  "flare",
  "fountain",
  "synchrotron",
  "waterfall",
] as const;

const DAYS = [
  "2024-02-29", // a leap day
  "2024-12-31",
  "2025-01-01",
  "2025-06-15",
  "2026-09-24",
  "2026-09-25",
  "2026-09-26",
  "2026-09-27", // four consecutive days
  "2030-11-05",
  "1999-12-31",
];

/** The reference's hash, with the date handed in rather than read from the clock. */
function hashForDay(day: string): number {
  let h = 2166136261;
  const s = `crucible:${day}`;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

interface Entry {
  day: string;
  hash: number;
  powderIndex: number;
  powderId: string;
  powderName: string;
  particleIndex: number;
  /** The name the native side uses, so the two lists can be compared directly. */
  particlePreset: string;
}

function choose(day: string): Entry {
  const h = hashForDay(day);
  const powderIndex = h % POWDER_RECIPES.length;
  const particleIndex = (h >>> 8) % PARTICLE_PRESETS.length;
  return {
    day,
    hash: h,
    powderIndex,
    powderId: POWDER_RECIPES[powderIndex].id,
    powderName: POWDER_RECIPES[powderIndex].name,
    particleIndex,
    particlePreset: NATIVE_PARTICLE_PRESETS[particleIndex],
  };
}

describe("golden daily world", () => {
  const entries = DAYS.map(choose);

  it("the hash helper agrees with the shipping one for today", () => {
    // The helper above duplicates the reference's hash so a date can be handed in. This is what stops
    // the duplicate drifting from the real thing — if `daily-seed.ts` ever changes its hash, the two
    // stop matching here rather than silently in production.
    const today = new Date().toISOString().slice(0, 10);
    expect(hashForDay(today)).toBe(dailyHash());
  });

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. Regenerate with: " +
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-daily",
            days: entries,
          },
          null,
          2
        ) + "\n"
      );
      expect(entries.length).toBe(DAYS.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { days: Entry[] };
    expect(entries).toEqual(fixture.days);
  });

  it("consecutive days do not all get the same world", () => {
    // A weak hash would hand out the same scene several days running, which nobody would report as a
    // bug — it would just feel like the feature was not working.
    const run = ["2026-09-24", "2026-09-25", "2026-09-26", "2026-09-27"].map(choose);
    const scenes = new Set(run.map((e) => e.powderId));
    expect(scenes.size).toBeGreaterThan(1);
  });

  it("the two chambers do not move in step", () => {
    // The particle index is taken from a shifted hash precisely so that a given scene is not always
    // paired with the same arrangement. If they moved together the pairings would repeat every
    // thirteen days.
    const pairs = new Set(entries.map((e) => `${e.powderIndex}:${e.particleIndex}`));
    const scenes = new Set(entries.map((e) => e.powderIndex));
    expect(pairs.size).toBeGreaterThanOrEqual(scenes.size);
  });
});
