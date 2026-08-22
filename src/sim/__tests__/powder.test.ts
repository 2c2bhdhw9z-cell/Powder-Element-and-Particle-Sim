import { describe, expect, it, beforeEach } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { seedRng } from "./helpers";

// Element IDs (see element-registry.ts)
const EMPTY = 0;
const SAND = 1;
const WATER = 2;
const FIRE = 4;
const SMOKE = 5;
const LAVA = 6;
const ACID = 8;
const BEDROCK = 29;
const OBSIDIAN = 46;
const ICE = 13;

function makeEngine(w = 32, h = 32): PowderEngine {
  const e = new PowderEngine(w, h);
  return e;
}

function countType(e: PowderEngine, id: number): number {
  let n = 0;
  for (let i = 0; i < e.gridType.length; i++) if (e.gridType[i] === id) n++;
  return n;
}

function countOfType(e: PowderEngine, y0: number, y1: number, id: number): number {
  let n = 0;
  for (let y = y0; y < y1; y++)
    for (let x = 0; x < e.width; x++) if (e.gridType[e.getIndex(x, y)] === id) n++;
  return n;
}

beforeEach(() => {
  seedRng();
});

describe("PowderEngine — basic mechanics", () => {
  it("sand falls to the bottom of the grid", () => {
    const e = makeEngine();
    for (let y = 2; y < 6; y++) e.setElementAt(16, y, SAND);
    for (let i = 0; i < 80; i++) e.step();
    expect(countOfType(e, e.height - 5, e.height, SAND)).toBe(4);
    expect(countOfType(e, 0, e.height - 5, SAND)).toBe(0);
  });

  it("conserves particle count for inert elements (no creation/destruction)", () => {
    const e = makeEngine();
    e.drawBrush(16, 8, 3, SAND, "circle");
    const initial = e.getActiveParticleCount();
    expect(initial).toBeGreaterThan(0);
    for (let i = 0; i < 60; i++) e.step();
    expect(e.getActiveParticleCount()).toBe(initial);
  });

  it("bedrock never moves", () => {
    const e = makeEngine();
    e.setElementAt(16, 0, BEDROCK);
    e.setElementAt(16, 3, SAND);
    for (let i = 0; i < 120; i++) e.step();
    expect(e.gridType[e.getIndex(16, 0)]).toBe(BEDROCK);
    // sand settled at the very bottom, not trapped mid-air
    expect(e.gridType[e.getIndex(16, e.height - 1)]).toBe(SAND);
  });

  it("zero gravity: plasma rises, nothing falls down by itself", () => {
    const e = makeEngine();
    e.gravityY = 0;
    e.setElementAt(16, 24, FIRE, 600, 40);
    for (let i = 0; i < 10; i++) e.step();
    // fire (or its decay product smoke) must be above the start row
    let found = false;
    for (let y = 0; y < 24; y++) {
      if (e.gridType[e.getIndex(16, y)] === FIRE || e.gridType[e.getIndex(16, y)] === SMOKE) {
        found = true;
        break;
      }
    }
    expect(found).toBe(true);
  });

  it("inverted gravity: water rises to the top", () => {
    const e = makeEngine();
    e.gravityY = -1;
    for (let x = 4; x < 12; x++) e.setElementAt(x, 20, WATER);
    for (let i = 0; i < 60; i++) e.step();
    expect(countOfType(e, 0, 6, WATER)).toBe(8);
    expect(countOfType(e, 12, e.height, WATER)).toBe(0);
  });

  it("heavier sand sinks through lighter water", () => {
    const e = makeEngine();
    // bedrock floor
    for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
    // 30 columns: 2 rows of sand above 3 rows of water (inverted stacking)
    for (let x = 1; x <= 30; x++) {
      for (let y = 26; y <= 27; y++) e.setElementAt(x, y, SAND);
      for (let y = 28; y <= 30; y++) e.setElementAt(x, y, WATER);
    }
    for (let i = 0; i < 200; i++) e.step();
    const sandLow = countOfType(e, e.height - 4, e.height - 1, SAND);
    const sandHigh = countOfType(e, 26, 28, SAND);
    expect(sandLow).toBeGreaterThan(sandHigh);
  });
});

describe("PowderEngine — phase changes & decay", () => {
  it("ice melts into water above 0°C", () => {
    const e = makeEngine();
    e.setElementAt(16, 16, ICE, 10);
    e.step();
    expect(e.gridType[e.getIndex(16, 16)]).toBe(WATER);
  });

  it("cool lava vitrifies into obsidian, hot lava stays molten", () => {
    const e = makeEngine();
    for (let x = 8; x <= 24; x++) e.setElementAt(x, 17, BEDROCK); // floor so lava can't fall
    e.setElementAt(10, 16, LAVA, 500); // below vitrification threshold
    e.setElementAt(20, 16, LAVA, 1200); // molten
    e.step();
    expect(e.gridType[e.getIndex(10, 16)]).toBe(OBSIDIAN);
    // hot lava may flow sideways a cell on its first tick — assert it stayed molten in place
    let hotLava = 0;
    for (let x = 8; x <= 24; x++) if (e.gridType[e.getIndex(x, 16)] === LAVA) hotLava++;
    expect(hotLava).toBe(1);
  });

  it("fire decays into smoke after its lifetime, smoke then vanishes", () => {
    const e = makeEngine();
    e.setElementAt(16, 20, FIRE, 600, 2);
    e.step();
    e.step();
    e.step(); // lifetime exhausted on 3rd tick
    expect(countType(e, FIRE)).toBe(0);
    expect(countType(e, SMOKE)).toBe(1);
    // smoke decays into air after ~120 ticks
    for (let i = 0; i < 160; i++) e.step();
    expect(countType(e, SMOKE)).toBe(0);
    expect(countType(e, FIRE)).toBe(0);
  });
});

describe("PowderEngine — reactions", () => {
  it("acid dissolves sand and is consumed", () => {
    const e = makeEngine();
    for (let x = 10; x <= 22; x++) {
      e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(x, e.height - 2, SAND);
    }
    for (let x = 14; x <= 17; x++) e.setElementAt(x, e.height - 3, ACID);
    const sandBefore = countType(e, SAND);
    const acidBefore = countType(e, ACID);
    expect(acidBefore).toBe(4);
    for (let i = 0; i < 40; i++) e.step();
    expect(countType(e, ACID)).toBe(0);
    expect(countType(e, SAND)).toBeLessThan(sandBefore);
  });

  it("explosion injects particles and fires onBurst", () => {
    const e = makeEngine();
    let bursts = 0;
    e.onBurst = () => bursts++;
    e.triggerExplosion(16, 16, 8);
    expect(bursts).toBe(1);
    expect(e.getActiveParticleCount()).toBeGreaterThan(0);
  });
});

describe("PowderEngine — editing tools", () => {
  it("drawBrush paints an exact circle for radius 1", () => {
    const e = makeEngine();
    e.drawBrush(8, 8, 1, SAND, "circle");
    const expectCells = [
      [8, 8],
      [7, 8],
      [9, 8],
      [8, 7],
      [8, 9],
    ];
    for (const [x, y] of expectCells) expect(e.gridType[e.getIndex(x, y)]).toBe(SAND);
    expect(countType(e, SAND)).toBe(5);
  });

  it("drawBrush paints a 3×3 square for radius 1", () => {
    const e = makeEngine();
    e.drawBrush(8, 8, 1, SAND, "square");
    expect(countType(e, SAND)).toBe(9);
  });

  it("spawnAmount places exactly the requested particles", () => {
    const e = makeEngine();
    e.spawnAmount(SAND, 50);
    expect(e.getActiveParticleCount()).toBe(50);
  });

  it("resize preserves existing particles", () => {
    const e = makeEngine();
    e.setElementAt(5, 5, SAND);
    e.resize(48, 48);
    expect(e.gridType[e.getIndex(5, 5)]).toBe(SAND);
    expect(e.getActiveParticleCount()).toBe(1);
  });
});

describe("PowderEngine — undo / redo / persistence", () => {
  it("undo reverts a change, redo re-applies it", () => {
    const e = makeEngine();
    e.drawBrush(5, 5, 1, SAND, "circle");
    e.pushUndo();
    e.drawBrush(20, 20, 1, SAND, "circle");
    expect(countType(e, SAND)).toBe(10);
    expect(e.canUndo()).toBe(true);
    expect(e.canRedo()).toBe(false);
    const ok = e.undo();
    expect(ok).toBe(true);
    expect(countType(e, SAND)).toBe(5);
    expect(countOfType(e, 18, 23, SAND)).toBe(0);
    const ok2 = e.redo();
    expect(ok2).toBe(true);
    expect(countType(e, SAND)).toBe(10);
    expect(countOfType(e, 18, 23, SAND)).toBe(5);
  });

  it("clear() is undoable", () => {
    const e = makeEngine();
    e.drawBrush(8, 8, 2, WATER, "circle");
    const before = e.getActiveParticleCount();
    e.clear();
    expect(e.getActiveParticleCount()).toBe(0);
    expect(e.undo()).toBe(true);
    expect(e.getActiveParticleCount()).toBe(before);
  });

  it("serializeState/deserializeState round-trips the grid", () => {
    const e = makeEngine();
    e.drawBrush(10, 10, 2, SAND, "circle");
    e.setElementAt(20, 20, LAVA, 900);
    const snapshot = e.serializeState();
    const typeBefore = e.gridType.slice();
    const tempBefore = e.gridTemp.slice();
    // Mutate the world
    e.drawBrush(24, 24, 2, WATER, "circle");
    e.setElementAt(10, 10, EMPTY);
    e.deserializeState(snapshot);
    for (let i = 0; i < e.gridType.length; i++) {
      expect(e.gridType[i]).toBe(typeBefore[i]);
      expect(e.gridTemp[i]).toBeCloseTo(tempBefore[i], 5);
    }
  });

  it("serializeLite/deserializeLite round-trips element layout + gravity", () => {
    const e = makeEngine();
    e.gravityY = -1;
    e.drawBrush(12, 12, 2, WATER, "circle");
    const lite = e.serializeLite();
    const typeBefore = e.gridType.slice();
    e.gravityY = 1;
    e.drawBrush(20, 20, 2, SAND, "circle");
    e.deserializeLite(lite);
    for (let i = 0; i < e.gridType.length; i++) expect(e.gridType[i]).toBe(typeBefore[i]);
    expect(e.gravityY).toBe(-1);
  });

  it("hashLite is stable for the same world", () => {
    const a = makeEngine();
    const b = makeEngine();
    a.drawBrush(10, 10, 2, SAND, "circle");
    b.drawBrush(10, 10, 2, SAND, "circle");
    expect(a.hashLite()).toBe(b.hashLite());
    b.setElementAt(3, 3, WATER);
    expect(a.hashLite()).not.toBe(b.hashLite());
  });
});

describe("PowderEngine — diagnostics & auto-fix", () => {
  it("reports healthy on a fresh grid", () => {
    const e = makeEngine();
    const d = e.getDiagnostics();
    expect(d.isHealthy).toBe(true);
    expect(d.issues).toHaveLength(0);
  });

  it("detects corrupt cells and repairs them via runAutoFix", () => {
    const e = makeEngine();
    e.injectCorruptCells();
    expect(e.getDiagnostics().isHealthy).toBe(false);
    e.runAutoFix();
    expect(e.getDiagnostics().isHealthy).toBe(true);
  });
});
