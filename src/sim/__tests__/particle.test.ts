import { describe, expect, it, beforeEach } from "vitest";
import { ParticleEngine } from "@/sim/particle-engine";
import { seedRng } from "./helpers";

beforeEach(() => {
  seedRng();
});

function makeEngine(w = 200, h = 200): ParticleEngine {
  return new ParticleEngine(w, h);
}

describe("ParticleEngine — spawning", () => {
  it("spawnBurst adds exactly the requested particles", () => {
    const e = makeEngine();
    e.spawnBurst(100);
    expect(e.particles.length).toBe(100);
    expect(e.bodyCount()).toBe(100);
  });

  it("large dumps go through the swarm path", () => {
    const e = makeEngine();
    e.spawnBatch(5000);
    expect(e.particles.length).toBe(0);
    expect(e.swarm.n).toBe(5000);
    expect(e.bodyCount()).toBe(5000);
  });

  it("setMaxParticles clamps to the [1000, 1e6] range", () => {
    const e = makeEngine();
    expect(e.setMaxParticles(10)).toBe(1000);
    expect(e.setMaxParticles(1e9)).toBe(1_000_000);
    expect(e.setMaxParticles(42000)).toBe(42000);
  });

  it("spawnCloth builds a pinned grid with the expected spring count", () => {
    const e = makeEngine();
    e.spawnCloth(16, 12);
    expect(e.particles.length).toBe(16 * 12);
    // horizontal: (cols-1)*rows, vertical: cols*(rows-1)
    expect(e.springs.length).toBe(15 * 12 + 16 * 11);
    // top row pins x = 0, 4, 8, 12, 15 (x % 4 === 0 plus both ends)
    const fixedCount = e.particles.slice(0, 16).filter((p) => p.fixed).length;
    expect(fixedCount).toBe(5);
  });
});

describe("ParticleEngine — physics", () => {
  it("bounce boundary keeps every particle inside the viewport", () => {
    const e = makeEngine();
    for (let i = 0; i < 150; i++) {
      e.addParticle({
        x: 5 + Math.random() * (e.width - 10),
        y: 5 + Math.random() * (e.height - 10),
        vx: (Math.random() - 0.5) * 16,
        vy: (Math.random() - 0.5) * 16,
        radius: 3,
      });
    }
    for (let i = 0; i < 200; i++) e.step();
    for (const p of e.particles) {
      expect(p.x).toBeGreaterThanOrEqual(0);
      expect(p.x).toBeLessThanOrEqual(e.width);
      expect(p.y).toBeGreaterThanOrEqual(0);
      expect(p.y).toBeLessThanOrEqual(e.height);
    }
  });

  it("gravity settles particles near the floor", () => {
    const e = makeEngine();
    e.gravityY = 0.3;
    for (let i = 0; i < 100; i++) {
      // charge 0 — otherwise the O(N²) Coulomb repulsion floats the cloud
      e.addParticle({ x: 10 + Math.random() * (e.width - 20), y: 10 + Math.random() * 50, charge: 0 });
    }
    for (let i = 0; i < 400; i++) e.step();
    const avgY = e.particles.reduce((s, p) => s + p.y, 0) / e.particles.length;
    expect(avgY).toBeGreaterThan(e.height - 60);
  });

  it("opposite charges attract", () => {
    const e = makeEngine();
    e.gravityX = 0;
    e.gravityY = 0;
    e.addParticle({ x: 100, y: 100, vx: 0, vy: 0, charge: 1, ignoreGravity: true });
    e.addParticle({ x: 160, y: 100, vx: 0, vy: 0, charge: -1, ignoreGravity: true });
    e.step();
    expect(e.particles[0].vx).toBeGreaterThan(0); // toward the negative charge
    expect(e.particles[1].vx).toBeLessThan(0); // toward the positive charge
  });

  it("black hole pulls nearby particles inward", () => {
    const e = makeEngine();
    e.gravityX = 0;
    e.gravityY = 0;
    e.placeWell(e.width / 2, e.height / 2);
    e.addParticle({ x: e.width / 2 + 100, y: e.height / 2, charge: 0, ignoreGravity: false });
    e.step();
    const probe = e.particles.find((p) => p.type === "standard")!;
    expect(probe.vx).toBeLessThan(0);
  });

  it("particles with an origin recycle instead of dying", () => {
    const e = makeEngine();
    e.addParticle({ x: 100, y: 100, originX: 100, originY: 100, lifespan: 5, maxLife: 50 });
    for (let i = 0; i < 8; i++) e.step();
    expect(e.particles.length).toBe(1);
    const p = e.particles[0];
    // respawn within 15px of origin + a few steps of ballistic drift
    expect(Math.abs(p.x - 100)).toBeLessThan(60);
    expect(Math.abs(p.y - 100)).toBeLessThan(60);
  });

  it("particles without an origin are removed on expiry", () => {
    const e = makeEngine();
    e.addParticle({ x: 100, y: 100, lifespan: 3 });
    for (let i = 0; i < 6; i++) e.step();
    expect(e.particles.length).toBe(0);
  });
});

describe("ParticleEngine — undo / redo", () => {
  it("undo reverts particle additions, redo re-applies them", () => {
    const e = makeEngine();
    e.spawnBurst(10);
    e.pushUndo();
    e.spawnBurst(10);
    expect(e.particles.length).toBe(20);
    expect(e.undo()).toBe(true);
    expect(e.particles.length).toBe(10);
    expect(e.redo()).toBe(true);
    expect(e.particles.length).toBe(20);
  });
});

describe("ParticleEngine — live multiplayer snapshot", () => {
  it("liveSnapshot/applyLive pulls displaced particles back toward the snapshot", () => {
    const e = makeEngine();
    e.spawnBurst(80);
    const snap = e.liveSnapshot();
    expect(snap.bodies).toHaveLength(80);

    // Displace every particle hard
    for (const p of e.particles) {
      p.x += 200;
      p.y += 100;
    }
    const before = e.particles.reduce(
      (s, p, i) => s + Math.hypot(p.x - snap.bodies[i].x, p.y - snap.bodies[i].y),
      0,
    );
    e.applyLive(snap);
    const after = e.particles.reduce(
      (s, p, i) => s + Math.hypot(p.x - snap.bodies[i].x, p.y - snap.bodies[i].y),
      0,
    );
    expect(after).toBeLessThan(before);
  });
});

describe("ParticleEngine — clearing & diagnostics", () => {
  it("clear() empties particles, swarm, springs and toggles", () => {
    const e = makeEngine();
    e.spawnBurst(50);
    e.spawnBatch(5000);
    e.fluidEnabled = true;
    e.flockEnabled = true;
    e.clear();
    expect(e.bodyCount()).toBe(0);
    expect(e.particles.length).toBe(0);
    expect(e.swarm.n).toBe(0);
    expect(e.springs.length).toBe(0);
    expect(e.fluidEnabled).toBe(false);
    expect(e.flockEnabled).toBe(false);
  });

  it("detects NaN particles and repairs them via runAutoFix", () => {
    const e = makeEngine();
    e.injectCorruptVectorParticles();
    const diag = e.getDiagnostics();
    expect(diag.isHealthy).toBe(false);
    expect(diag.nanCount).toBe(15);
    e.runAutoFix();
    expect(e.getDiagnostics().isHealthy).toBe(true);
  });

  it("clampVelocities caps speed at maxSpeed", () => {
    const e = makeEngine();
    e.addParticle({ x: 100, y: 100, vx: 500, vy: 0, ignoreGravity: true });
    const { clamped } = e.clampVelocities();
    expect(clamped).toBe(1);
    const speed = Math.hypot(e.particles[0].vx, e.particles[0].vy);
    expect(speed).toBeLessThanOrEqual(e.maxSpeed + 0.001);
  });
});
