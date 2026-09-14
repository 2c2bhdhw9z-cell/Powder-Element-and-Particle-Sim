import { describe, expect, it, beforeEach } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { renderToCanvas } from "@/sim/powder/render";
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

/**
 * Minimal ImageData/2D-context stand-in for the node vitest env (no DOM).
 * `renderToCanvas` only touches imageSmoothingEnabled, createImageData,
 * putImageData, and reads width/height/data.buffer off the ImageData.
 */
function makeFakeCtx(_w: number, _h: number) {
  const makeImageData = (iw: number, ih: number) => ({
    width: iw,
    height: ih,
    data: new Uint8ClampedArray(iw * ih * 4),
  });
  const ctx = {
    imageSmoothingEnabled: false,
    createImageData: (iw: number, ih: number) => makeImageData(iw, ih),
    putImageData: () => {},
  };
  return ctx as unknown as CanvasRenderingContext2D;
}

/** Read the RGB of one cell out of the engine's rendered ImageData buffer. */
function cellRgb(e: PowderEngine, x: number, y: number): [number, number, number] {
  const data = new Uint8Array((e.imageData as ImageData).data.buffer);
  const off = (y * e.width + x) * 4;
  return [data[off], data[off + 1], data[off + 2]];
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

  it("hot lava surrounded by enough water resolves to obsidian within a tick budget", () => {
    const e = makeEngine();
    // Bedrock box (floor + walls) so the water body can't drain away.
    for (let x = 10; x <= 22; x++) {
      e.setElementAt(x, 26, BEDROCK); // floor
    }
    for (let y = 12; y <= 26; y++) {
      e.setElementAt(10, y, BEDROCK); // left wall
      e.setElementAt(22, y, BEDROCK); // right wall
    }
    // Fill the basin with water.
    for (let x = 11; x <= 21; x++)
      for (let y = 14; y <= 25; y++) e.setElementAt(x, y, WATER);
    // Drop a hot lava cell into the middle of the pool.
    e.setElementAt(16, 18, LAVA, 1200);

    const BUDGET = 400;
    let resolvedAt = -1;
    for (let i = 0; i < BUDGET; i++) {
      e.step();
      if (countType(e, LAVA) === 0) {
        resolvedAt = i;
        break;
      }
    }

    // The fight finishes: no molten lava is left oscillating.
    expect(countType(e, LAVA)).toBe(0);
    expect(resolvedAt).toBeGreaterThanOrEqual(0);
    expect(resolvedAt).toBeLessThan(BUDGET);
    // The lava vitrified rather than simply boiling every neighbor to steam.
    expect(countType(e, OBSIDIAN)).toBeGreaterThan(0);
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

describe("PowderEngine — render texture invariants (bug 1: no liquid glitter)", () => {
  it("a liquid cell renders identically regardless of grid position (no position-hash jitter)", () => {
    // default textureMode is "natural_grain", which hashes (x, y). Water is a
    // liquid, so its shade must NOT depend on where it sits — otherwise a
    // flowing cell shimmers as it moves.
    const e = makeEngine(16, 16);
    expect(e.textureMode).toBe("natural_grain");

    const ctx = makeFakeCtx(e.width, e.height);
    const samples: Array<[number, number]> = [
      [3, 4],
      [7, 9],
      [11, 2],
      [5, 13],
    ];
    const colors = samples.map(([x, y]) => {
      // isolate a single water cell each render so nothing else interferes
      e.clear();
      e.setElementAt(x, y, WATER);
      renderToCanvas(e, ctx, "normal");
      return cellRgb(e, x, y);
    });
    for (let i = 1; i < colors.length; i++) {
      expect(colors[i]).toEqual(colors[0]);
    }
  });

  it("a moving water column renders one flat color across consecutive frames", () => {
    const e = makeEngine(24, 24);
    // pour a short water column so cells actually flow between frames
    for (let y = 2; y <= 6; y++) e.setElementAt(12, y, WATER);
    for (let i = 0; i < 5; i++) e.step();

    const ctx = makeFakeCtx(e.width, e.height);

    // Collect every distinct rendered water color across two consecutive frames.
    // With position-hash jitter removed for liquids, all water cells — no matter
    // where they have flowed to — must share exactly one flat shade.
    const shades = new Set<string>();
    let checked = 0;
    for (let frame = 0; frame < 2; frame++) {
      renderToCanvas(e, ctx, "normal");
      const data = new Uint8Array((e.imageData as ImageData).data.buffer);
      for (let i = 0; i < e.gridType.length; i++) {
        if (e.gridType[i] !== WATER) continue;
        const off = i * 4;
        shades.add(`${data[off]},${data[off + 1]},${data[off + 2]}`);
        checked++;
      }
      e.step();
    }
    expect(checked).toBeGreaterThan(0);
    expect(shades.size).toBe(1);
  });

  it("solid-grain texture (sand) still gets position-dependent color jitter", () => {
    // Guard the fix's scope: grains must KEEP their speckle.
    const e = makeEngine(16, 16);
    const ctx = makeFakeCtx(e.width, e.height);
    for (let x = 0; x < e.width; x++)
      for (let y = 0; y < e.height; y++) e.setElementAt(x, y, SAND);
    renderToCanvas(e, ctx, "normal");
    const seen = new Set<string>();
    for (let x = 0; x < e.width; x++) {
      for (let y = 0; y < e.height; y++) {
        seen.add(cellRgb(e, x, y).join(","));
      }
    }
    // more than one distinct shade => grain jitter is still applied
    expect(seen.size).toBeGreaterThan(1);
  });
});
