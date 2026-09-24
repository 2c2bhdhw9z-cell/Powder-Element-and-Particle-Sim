import { beforeEach, describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { ParticleEngine } from "@/sim/particle-engine";
import { PowderHistory } from "@/sim/powder/history";
import { packSwarmSnap, packXY, unpackSwarmSnap, unpackXY } from "@/sim/live-pack";
import { seedRng } from "./helpers";

/**
 * Saving, loading, undo and the multiplayer wire format.
 *
 * This layer handles data the simulation did not produce itself — scene files a user
 * picked, autosaves from an older build, payloads from another machine over the
 * network. The interesting failures here are all the same shape: something malformed
 * arrives and the code neither rejects it nor survives it, but half-applies it and
 * leaves the world quietly broken. Every test below started as one of those.
 */

const SAND = 1;
const WATER = 2;
const BEDROCK = 29;

describe("powder grid serialization", () => {
  let restoreRng: () => void;
  beforeEach(() => {
    restoreRng = seedRng(1234);
    return () => restoreRng();
  });

  it("rejects a payload whose dimensions are not valid instead of loading it crooked", () => {
    const engine = new PowderEngine(32, 24);
    for (let x = 0; x < 32; x++) engine.setElementAt(x, 23, BEDROCK);
    const before = Array.from(engine.gridType);

    // 40x30 of data, but the declared size is nonsense. The declared size is what
    // decides the row stride, so accepting the cells anyway writes row 1 of the
    // payload partway through row 0 of the grid, and so on — the whole world shears.
    const payload = JSON.stringify({
      width: "40",
      height: 30.5,
      gridType: new Array(40 * 30).fill(SAND),
      gridTemp: new Array(40 * 30).fill(20),
      gridLife: new Array(40 * 30).fill(0),
    });
    engine.deserializeState(payload);

    expect(engine.width).toBe(32);
    expect(engine.height).toBe(24);
    expect(Array.from(engine.gridType)).toEqual(before);
  });

  it("keeps the world intact when a lite payload cannot be decoded", () => {
    const engine = new PowderEngine(16, 16);
    engine.setElementAt(8, 8, WATER);
    const before = Array.from(engine.gridType);

    // Valid JSON, valid dimensions, but the body is not base64. Decoding throws.
    engine.deserializeLite(JSON.stringify({ w: 16, h: 16, t: "!!!! not base64 !!!!" }));

    // The old code wiped the grid *before* attempting to decode, so a single bad
    // message from a peer left the receiving player staring at an empty world.
    expect(Array.from(engine.gridType)).toEqual(before);
  });

  it("round-trips a world through the lite format", () => {
    const source = new PowderEngine(20, 15);
    source.setElementAt(3, 4, SAND);
    source.setElementAt(10, 12, BEDROCK);
    source.gravityX = 0.25;

    const target = new PowderEngine(8, 8);
    target.deserializeLite(source.serializeLite());

    expect(target.width).toBe(20);
    expect(target.height).toBe(15);
    expect(Array.from(target.gridType)).toEqual(Array.from(source.gridType));
    expect(target.gravityX).toBeCloseTo(0.25, 10);
  });

  it("fingerprints the world by what it actually transmits", () => {
    // Two worlds that send identical bytes must fingerprint identically, or the host
    // decides they disagree and resends the entire grid every single tick, forever,
    // while the two worlds never converge.
    const a = new PowderEngine(24, 18);
    const b = new PowderEngine(24, 18);
    a.gridType[100] = 300; // Out of the byte range the wire format carries.
    b.deserializeLite(a.serializeLite());
    expect(b.hashLite()).toBe(a.hashLite());
  });

  it("refuses element ids the registry cannot describe", () => {
    const engine = new PowderEngine(8, 8);
    const payload = JSON.stringify({
      width: 8,
      height: 8,
      gridType: [400, 9999, -1, 1.5, SAND, ...new Array(59).fill(0)],
      gridTemp: new Array(64).fill(20),
      gridLife: new Array(64).fill(0),
    });
    engine.deserializeState(payload);

    // Anything outside the registry's range becomes empty. Previously ids from 100 to
    // 499 were admitted, behaved as air because the registry falls back to air, and
    // yet counted as active particles forever — invisible, immortal phantoms.
    expect(engine.gridType[0]).toBe(0);
    expect(engine.gridType[1]).toBe(0);
    expect(engine.gridType[2]).toBe(0);
    expect(engine.gridType[3]).toBe(0);
    expect(engine.gridType[4]).toBe(SAND);
    expect(engine.getActiveParticleCount()).toBe(1);
  });

  it("clamps wind arriving from a file", () => {
    const engine = new PowderEngine(8, 8);
    engine.deserializeState(
      JSON.stringify({ width: 8, height: 8, gridType: new Array(64).fill(0), windX: 500 })
    );
    expect(engine.windX).toBeLessThanOrEqual(5);
  });
});

describe("powder undo history", () => {
  it("restores the grid, the settings and the ambient temperature together", () => {
    const engine = new PowderEngine(16, 12);
    engine.ambientTemp = 20;
    engine.setElementAt(4, 4, SAND);

    const history = new PowderHistory(5);
    history.push(engine);

    engine.setElementAt(4, 4, 0);
    engine.ambientTemp = -40;
    expect(history.undo(engine)).toBe(true);

    expect(engine.gridType[4 * 16 + 4]).toBe(SAND);
    expect(engine.ambientTemp).toBe(20);
  });

  it("brings back the exact temperatures alongside the ambient value", () => {
    // The snapshot is applied over a freshly cleared grid, and the clear fills it with
    // the ambient temperature — so the ambient value has to be in place before the
    // clear, not assigned after it, or any cell the snapshot does not reach is left
    // holding the temperature of the world being replaced.
    const engine = new PowderEngine(8, 8);
    engine.ambientTemp = 100;
    engine.resetGrid();
    engine.setElementAt(3, 3, SAND, 450);

    const history = new PowderHistory(5);
    history.push(engine);

    engine.ambientTemp = -50;
    engine.resetGrid();
    expect(history.undo(engine)).toBe(true);

    expect(engine.ambientTemp).toBe(100);
    expect(engine.gridTemp[3 * 8 + 3]).toBeCloseTo(450, 3);
    expect(engine.gridTemp[0]).toBeCloseTo(100, 3);
  });

  it("clamps wind on the way back out of a snapshot", () => {
    const engine = new PowderEngine(8, 8);
    const history = new PowderHistory(5);
    // windX is a public field, so anything may have written an absurd value into it.
    engine.windX = 900;
    history.push(engine);
    engine.setWind(0);
    history.undo(engine);
    expect(engine.windX).toBeLessThanOrEqual(5);
  });

  it("refuses to restore a snapshot that does not fit rather than shearing the grid", () => {
    const engine = new PowderEngine(16, 16);
    const history = new PowderHistory(5);
    history.push(engine);

    // Forge a snapshot whose size can never be adopted, which is what an allocation
    // failure during resize leaves behind. Blitting it in anyway puts every row at the
    // wrong offset.
    const forged = {
      width: 0,
      height: 0,
      type: new Uint16Array(0),
      temp: new Float32Array(0),
      life: new Uint16Array(0),
      gravityX: 0,
      gravityY: 1,
      windX: 0,
      ambientTemp: 20,
    };
    engine.setElementAt(2, 2, SAND);
    const before = Array.from(engine.gridType);
    history.restore(engine, forged);

    expect(engine.width).toBe(16);
    expect(engine.height).toBe(16);
    expect(Array.from(engine.gridType)).toEqual(before);
  });

  it("never lets a snapshot failure throw out of undo or redo", () => {
    const engine = new PowderEngine(8, 8);
    const history = new PowderHistory(2);
    history.push(engine);
    // push() already tolerates a failed capture; undo() and redo() captured outside
    // any guard, so the same failure escaped into the interface instead.
    expect(() => history.undo(engine)).not.toThrow();
    expect(() => history.redo(engine)).not.toThrow();
  });

  it("treats a nonsensical depth as a working single step rather than dead", () => {
    // A depth of zero made push() discard the snapshot it had just taken, so undo was
    // permanently unavailable with no indication anything was wrong.
    const engine = new PowderEngine(8, 8);
    const history = new PowderHistory(0);
    engine.setElementAt(1, 1, SAND);
    history.push(engine);
    expect(history.canUndo()).toBe(true);
  });
});

describe("the live multiplayer codec", () => {
  it("round-trips positions and velocities within its stated resolution", () => {
    const { n, b } = packSwarmSnap([10.5, -3.25], [7.125, 900.5], [1.5, -2.25], [0.5, 0.75]);
    const out = unpackSwarmSnap(n, b);
    expect(out.sx).toEqual([10.5, -3.25]);
    expect(out.sy).toEqual([7.125, 900.5]);
    expect(out.svx).toEqual([1.5, -2.25]);
    expect(out.svy).toEqual([0.5, 0.75]);
  });

  it("round-trips a position-only payload", () => {
    const { n, b } = packXY([1.25, 300.5], [2.5, 17.875]);
    const out = unpackXY(n, b);
    expect(out.sx).toEqual([1.25, 300.5]);
    expect(out.sy).toEqual([2.5, 17.875]);
  });

  it("returns nothing rather than throwing on a payload that is not base64", () => {
    // These are fed straight from the network. A peer sending one bad frame used to
    // throw out of the message handler, which killed the whole session.
    expect(() => unpackSwarmSnap(4, "%%%%")).not.toThrow();
    expect(unpackSwarmSnap(4, "%%%%").sx).toEqual([]);
    expect(() => unpackXY(4, "%%%%")).not.toThrow();
    expect(unpackXY(4, "%%%%").sx).toEqual([]);
  });

  it("returns nothing rather than throwing on a truncated payload", () => {
    // An odd byte count cannot be read as 16-bit values at all.
    const odd = btoa("abc");
    expect(() => unpackSwarmSnap(1, odd)).not.toThrow();
    expect(() => unpackXY(1, odd)).not.toThrow();
  });

  it("never reads more bodies than the payload holds", () => {
    const { b } = packXY([1, 2], [3, 4]);
    // A peer claiming a thousand bodies in a two-body payload.
    expect(unpackXY(1000, b).sx.length).toBe(2);
  });
});

describe("loading a particle scene", () => {
  it("drops springs belonging to the world being replaced", () => {
    // Springs hold positions in the particle list. Replacing the list without
    // clearing them leaves each spring joining whichever two particles now happen to
    // sit at those positions, with a rest length measured for a different pair — so
    // the structure pumps energy into the scene on every frame afterwards. This is
    // the single most damaging bug in this layer.
    const engine = new ParticleEngine(400, 300);
    engine.spawnCloth(6, 5);
    expect(engine.springs.length).toBeGreaterThan(0);

    engine.replaceParticles([
      { id: "a", x: 10, y: 10, vx: 0, vy: 0, radius: 2, mass: 1, charge: 1, color: "#fff", type: "standard", trail: [] },
      { id: "b", x: 20, y: 20, vx: 0, vy: 0, radius: 2, mass: 1, charge: 1, color: "#fff", type: "standard", trail: [] },
    ]);

    expect(engine.particles.length).toBe(2);
    expect(engine.springs.length).toBe(0);
  });

  it("keeps every spring pointing at a real pair of particles", () => {
    const engine = new ParticleEngine(400, 300);
    engine.spawnRope(10);
    engine.replaceParticles(engine.particles.slice(0, 4));
    for (const spring of engine.springs) {
      expect(engine.particles[spring.a]).toBeDefined();
      expect(engine.particles[spring.b]).toBeDefined();
      expect(spring.a).not.toBe(spring.b);
    }
  });
});
