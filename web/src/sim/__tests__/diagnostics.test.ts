import { beforeEach, describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { ParticleEngine } from "@/sim/particle-engine";
import { POWDER_RECIPES, seedRemix } from "@/sim/powder-recipes";
import { seedRng } from "./helpers";

/**
 * The repair tools.
 *
 * These exist to rescue a world that has gone wrong, which makes them the last place a
 * bug should live — a repair that reports success without repairing anything, or that
 * damages something unrelated on the way, is worse than no repair at all. Every test
 * below was a real instance of one of those.
 */

const SAND = 1;
const FIRE = 4;
const BEDROCK = 29;

describe("powder health inspection", () => {
  it("counts a cell that is wrong in two ways only once", () => {
    const engine = new PowderEngine(16, 16);
    // A bad element id and an unreadable temperature in the same cell. The two checks
    // each incremented the same counter, so twenty damaged cells were reported as
    // forty — and the repair that followed then truthfully said it had cleared twenty,
    // which read like a failure.
    engine.gridType[0] = 9999;
    engine.gridTemp[0] = NaN;

    const diag = engine.getDiagnostics();
    expect(diag.corruptCellCount).toBe(1);
    expect(diag.corruptTypeCount).toBe(1);
    expect(diag.nanTempCount).toBe(1);
  });

  it("treats an element the registry cannot describe as corrupt", () => {
    const engine = new PowderEngine(16, 16);
    // 300 is past every real id. It used to sit below the corruption threshold of 500,
    // so it drew as air, behaved as air, was never reported, could not be cleared, and
    // still counted as an active particle forever.
    engine.gridType[5] = 300;
    const diag = engine.getDiagnostics();
    expect(diag.corruptTypeCount).toBe(1);
    expect(diag.isHealthy).toBe(false);

    engine.flushStuckCells();
    expect(engine.gridType[5]).toBe(0);
    expect(engine.getDiagnostics().corruptTypeCount).toBe(0);
  });

  it("averages temperature over the cells it could actually read", () => {
    const engine = new PowderEngine(10, 10);
    engine.gridTemp.fill(100);
    for (let i = 0; i < 50; i++) engine.gridTemp[i] = NaN;
    // Dividing by every cell while skipping the unreadable ones dragged the average
    // toward zero in proportion to the damage — so the figure was least trustworthy
    // exactly when someone was consulting it.
    expect(engine.getDiagnostics().avgTemp).toBe(100);
  });
});

describe("powder repairs", () => {
  it("empties a corrupt cell completely, not just its element", () => {
    const engine = new PowderEngine(8, 8);
    engine.gridType[3] = 9999;
    engine.gridLife[3] = 77;
    engine.gridVx[3] = 5;
    engine.gridVy[3] = -4;

    engine.flushStuckCells();

    // Leaving the lifetime and momentum behind meant the next thing to occupy the cell
    // inherited a stranger's motion and a countdown to decay.
    expect(engine.gridType[3]).toBe(0);
    expect(engine.gridLife[3]).toBe(0);
    expect(engine.gridVx[3]).toBe(0);
    expect(engine.gridVy[3]).toBe(0);
  });

  it("returns temperatures to the world's own ambient, not a fixed room temperature", () => {
    const engine = new PowderEngine(8, 8);
    engine.ambientTemp = -40;
    engine.gridTemp[0] = 9000;
    engine.gridTemp[1] = NaN;

    engine.zeroThermalExtremes();
    expect(engine.gridTemp[0]).toBeCloseTo(-40, 4);
    expect(engine.gridTemp[1]).toBeCloseTo(-40, 4);

    engine.coolAllCells();
    expect(engine.gridTemp[5]).toBeCloseTo(-40, 4);
  });

  it("clears unreadable temperatures during the automatic pass", () => {
    const engine = new PowderEngine(12, 12);
    // The only fault is unreadable temperatures. The thermal repair used to be gated
    // on the hottest and coldest readings, and an unreadable value is neither — so
    // nothing was done, and the pass then declared the world recovered.
    for (let i = 0; i < 20; i++) engine.gridTemp[i] = NaN;
    expect(engine.getDiagnostics().isHealthy).toBe(false);

    engine.runAutoFix();
    expect(engine.getDiagnostics().nanTempCount).toBe(0);
    expect(engine.getDiagnostics().isHealthy).toBe(true);
  });

  it("does not wall in the world during the automatic pass", () => {
    const engine = new PowderEngine(20, 20);
    // A scene with a deliberately open top, which is what every built-in recipe has.
    for (let x = 0; x < 20; x++) engine.setElementAt(x, 19, BEDROCK);
    engine.gridType[40] = 9999; // One unrelated fault, to make the world unhealthy.

    engine.runAutoFix();

    // Sealing the perimeter replaces it with bedrock. Running that automatically, in
    // response to a fault that has nothing to do with the edges, destroyed the shape
    // of any scene built with an open top. It is a manual action now.
    let sealedTop = 0;
    for (let x = 0; x < 20; x++) if (engine.gridType[x] === BEDROCK) sealedTop++;
    expect(sealedTop).toBe(0);
  });

  it("still seals the world when asked directly", () => {
    const engine = new PowderEngine(12, 12);
    const res = engine.sealBedrockBorders();
    expect(res.borderCellsSet).toBeGreaterThan(0);
    for (let x = 0; x < 12; x++) expect(engine.gridType[x]).toBe(BEDROCK);
  });

  it("leaves nothing burning inside the bedrock it lays down", () => {
    const engine = new PowderEngine(12, 12);
    engine.setElementAt(3, 0, FIRE, 900);
    engine.sealBedrockBorders();
    const idx = engine.getIndex(3, 0);
    // Bedrock does not burn or decay, so whatever it replaced has to go with it. A
    // burning cell turned into bedrock that was still at 900°C with a decay countdown
    // running kept cooking its neighbours from inside something meant to be inert.
    expect(engine.gridType[idx]).toBe(BEDROCK);
    expect(engine.gridTemp[idx]).toBeCloseTo(engine.ambientTemp, 3);
    expect(engine.gridLife[idx]).toBe(0);
  });

  it("survives a world with no cells at all", () => {
    const engine = new PowderEngine(0, 0);
    // With no cells there is no border. The loops used to compute an index of -1,
    // whose write a typed array silently drops while the read beside it returns
    // undefined — so the count rose for writes that never happened.
    const res = engine.sealBedrockBorders();
    expect(res.borderCellsSet).toBe(0);
    expect(() => engine.runAutoFix()).not.toThrow();
  });

  it("reports what it could not fix instead of claiming recovery", () => {
    // Near-maximum density is a complaint with no corresponding repair, so the pass has
    // to finish and admit it. Large enough that clearing the frame — which the pass does
    // do — cannot by itself bring the world back under the threshold.
    const engine = new PowderEngine(200, 200);
    for (let i = 0; i < engine.gridType.length; i++) engine.gridType[i] = SAND;
    expect(engine.getDiagnostics().isHealthy).toBe(false);

    const { logs } = engine.runAutoFix();
    expect(engine.getDiagnostics().isHealthy).toBe(false);
    // The old message said "RECOVERY COMPLETED" regardless, which is precisely the case
    // where the detail matters.
    expect(logs.some((line) => /could not be repaired/i.test(line))).toBe(true);
    expect(logs.some((line) => /density/i.test(line))).toBe(true);
  });
});

describe("the thermal spike injector", () => {
  it("leaves a spike that is still hot on the next tick", () => {
    const engine = new PowderEngine(40, 40);
    engine.injectThermalSpike();
    engine.step();
    // Writing the element straight into the grid left its decay countdown at zero, and
    // anything decaying with a spent countdown becomes its successor immediately — so
    // the whole spike turned to smoke on the first tick, erasing the very extreme the
    // injector exists to create.
    expect(engine.getDiagnostics().maxTemp).toBeGreaterThan(1000);
  });
});

describe("particle health inspection and repairs", () => {
  let restoreRng: () => void;
  beforeEach(() => {
    restoreRng = seedRng(4242);
    return () => restoreRng();
  });

  it("repairs a corrupt swarm instead of reporting it forever", () => {
    const engine = new ParticleEngine(300, 300);
    engine.spawnBatch(5000);
    engine.swarm.xy[0] = NaN;
    engine.swarm.v[3] = Infinity;

    const before = engine.getDiagnostics();
    expect(before.swarmCorruptCount).toBeGreaterThan(0);
    expect(before.isHealthy).toBe(false);

    // Purging only ever touched the object list, so the report said "N corrupt" and
    // the repair said it had removed none, leaving the issue unresolvable.
    engine.runAutoFix();
    expect(engine.getDiagnostics().swarmCorruptCount).toBe(0);
  });

  it("does not freeze the world when the speed limit is zero", () => {
    const engine = new ParticleEngine(400, 300);
    engine.spawnBurst(40);
    engine.maxSpeed = 0;
    engine.clampVelocities();
    // The inspection reads a limit of zero as "no limit". The repair took it literally
    // and multiplied every velocity by zero, stopping the entire field dead — while the
    // inspection that triggered it had reported nothing wrong.
    const moving = engine.particles.filter((p) => p.vx !== 0 || p.vy !== 0);
    expect(moving.length).toBeGreaterThan(0);
  });

  it("keeps a radius of zero when bringing a particle back in bounds", () => {
    const engine = new ParticleEngine(400, 300);
    engine.addParticle({ x: -500, y: 150, vx: -1, vy: 0, radius: 0 });
    engine.recentreOutOfBounds();
    // Zero is a legitimate radius that addParticle goes out of its way to preserve. A
    // truthiness test silently replaced it with the default size, resizing a particle
    // inside a repair that is only supposed to move it.
    expect(engine.particles[0].radius).toBe(0);
    expect(engine.particles[0].x).toBeGreaterThanOrEqual(0);
  });

  it("balances charge to exactly zero", () => {
    const engine = new ParticleEngine(400, 300);
    for (let i = 0; i < 5; i++) engine.addParticle({ x: 10 * i, y: 10, charge: 5 });
    engine.resetCharges();
    const total = engine.particles.reduce((sum, p) => sum + p.charge, 0);
    // With an odd number of charged particles the last one used to keep whatever it had
    // — possibly a charge of five — while the function reported a balanced field.
    expect(total).toBe(0);
  });

  it("counts swarm particles that exceed the speed limit", () => {
    const engine = new ParticleEngine(300, 300);
    engine.spawnBatch(5000);
    engine.maxSpeed = 10;
    engine.swarm.v[0] = 900;
    engine.swarm.v[1] = 0;
    // The swarm only fed the headline top speed, so the report could show 900 beside a
    // count of zero over the limit, and an escaped swarm was invisible to the pass.
    expect(engine.getDiagnostics().extremeVelocityCount).toBeGreaterThan(0);
  });
});

describe("the daily scene", () => {
  it("builds the same world from the same day for everyone", () => {
    // One of the thirteen recipes scatters elements at random. It used to read the
    // global random source, so on roughly one day in thirteen the shared "daily" world
    // was different for every player while the interface still named it.
    const first = new PowderEngine(60, 40);
    const second = new PowderEngine(60, 40);
    const remix = POWDER_RECIPES.find((r) => r.id === "remix");
    expect(remix).toBeDefined();

    const seeded = () => {
      let a = 99 >>> 0;
      return () => {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      };
    };
    remix!.run(first, seeded());
    remix!.run(second, seeded());
    expect(Array.from(first.gridType)).toEqual(Array.from(second.gridType));
  });

  it("still varies when nobody supplies a generator", () => {
    const restore = seedRng(7);
    const a = new PowderEngine(60, 40);
    seedRemix(a);
    restore();
    const restore2 = seedRng(8);
    const b = new PowderEngine(60, 40);
    seedRemix(b);
    restore2();
    expect(Array.from(a.gridType)).not.toEqual(Array.from(b.gridType));
  });
});
