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
    // The probe sits well inside the world, with an explicit zero velocity.
    //
    // It used to be placed at `width / 2 + 100`, which on this 200-wide test engine is
    // exactly the right-hand wall — so the probe bounced on its very first step and
    // the bounce flipped the sign of whatever inward pull it had been given. What the
    // test actually measured was the wall, and it only passed when the random velocity
    // addParticle seeds happened to exceed the pull, roughly one time in twenty.
    e.addParticle({ x: e.width / 2 + 60, y: e.height / 2, vx: 0, vy: 0, charge: 0, ignoreGravity: false });
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


/**
 * Regression guards for the particle-field bugs found during the native port audit.
 *
 * Each one failed before its fix. They are written against observable behaviour
 * rather than internals, so the native port can be held to exactly the same
 * expectations.
 */
describe("ParticleEngine — audit regressions", () => {
  it("springs survive particle removal instead of re-wiring to the wrong pairs", () => {
    // The worst bug on this side. Springs store absolute indices into `particles`,
    // and six separate code paths used to drop or shift elements without touching
    // them — silently re-pointing every spring below the removal at a different pair
    // whose rest length no longer matched, which sheared cloth and pumped energy in
    // on every frame afterwards.
    const e = makeEngine(400, 400);
    e.spawnCloth(8, 6);
    const springsBefore = e.springs.length;
    expect(springsBefore).toBeGreaterThan(0);

    // Record the actual pairs, by identity rather than by index.
    const pairsBefore = e.springs.map((s) => [e.particles[s.a], e.particles[s.b]] as const);

    // Remove a particle from the middle, which shifts every index after it.
    const victim = e.particles[3];
    const removed = e.removeParticles((p) => p === victim);
    expect(removed).toBe(1);

    // Every surviving spring must still join the same two particles it did before.
    for (const s of e.springs) {
      const pair = [e.particles[s.a], e.particles[s.b]] as const;
      expect(pair[0]).toBeDefined();
      expect(pair[1]).toBeDefined();
      const matched = pairsBefore.some((before) => before[0] === pair[0] && before[1] === pair[1]);
      expect(matched).toBe(true);
    }

    // And the springs that touched the removed particle are gone, not dangling.
    expect(e.springs.length).toBeLessThan(springsBefore);
    for (const s of e.springs) {
      expect(e.particles[s.a]).not.toBe(victim);
      expect(e.particles[s.b]).not.toBe(victim);
    }
  });

  it("the speed limit applies to ordinary particles, not just orbital ones", () => {
    // The clamp used to sit in the `else` of the gravity branch, so it only ever
    // reached particles that ignore gravity. Every normal particle was uncapped,
    // despite the interface offering one global speed slider.
    const e = makeEngine();
    e.gravityX = 0;
    e.gravityY = 0;
    e.maxSpeed = 5;
    e.addParticle({ x: 100, y: 100, vx: 500, vy: 0, ignoreGravity: false });
    e.step();
    const speed = Math.hypot(e.particles[0].vx, e.particles[0].vy);
    expect(speed).toBeLessThanOrEqual(5.001);
  });

  it("a fast particle cannot escape a wrapping world", () => {
    // Wrapping corrected by a single add or subtract, so anything travelling more
    // than one world-width per frame stayed outside the world permanently.
    const e = makeEngine();
    e.gravityX = 0;
    e.gravityY = 0;
    e.maxSpeed = 10_000; // deliberately let it move absurdly fast
    e.boundaryMode = "wrap";
    e.addParticle({ x: 100, y: 100, vx: 5000, vy: 3000, ignoreGravity: true });
    for (let i = 0; i < 5; i++) e.step();
    const p = e.particles[0];
    expect(p.x).toBeGreaterThanOrEqual(0);
    expect(p.x).toBeLessThan(e.width);
    expect(p.y).toBeGreaterThanOrEqual(0);
    expect(p.y).toBeLessThan(e.height);
  });

  it("a recycled particle without maxLife keeps living instead of freezing forever", () => {
    // Recycling only restored the lifespan when `maxLife` was set. Without it the
    // particle was teleported to its origin once and then frozen there for good —
    // skipped by the force loop, never removed, but still drawn and still counted
    // toward every level-of-detail threshold.
    const e = makeEngine();
    e.addParticle({ x: 100, y: 100, originX: 100, originY: 100, lifespan: 2 });
    for (let i = 0; i < 10; i++) e.step();
    expect(e.particles.length).toBe(1);
    expect(e.particles[0].lifespan).toBeGreaterThan(0);
  });

  it("recycling clears the trail so it does not streak across the world", () => {
    const e = makeEngine();
    e.showTrails = true;
    e.addParticle({ x: 20, y: 20, originX: 180, originY: 20, lifespan: 3, maxLife: 30 });
    // Build up a trail, then let it die and recycle.
    for (let i = 0; i < 4; i++) e.step();
    const p = e.particles[0];
    // Immediately after recycling the trail must not still contain the old position.
    for (const point of p.trail) {
      expect(Math.hypot(point.x - p.x, point.y - p.y)).toBeLessThan(100);
    }
  });

  it("turning trails off discards the stale trail", () => {
    const e = makeEngine();
    e.showTrails = true;
    e.addParticle({ x: 50, y: 50, vx: 1, vy: 1 });
    for (let i = 0; i < 5; i++) e.step();
    expect(e.particles[0].trail.length).toBeGreaterThan(0);
    e.showTrails = false;
    e.step();
    expect(e.particles[0].trail.length).toBe(0);
  });

  it("a pinned particle is never moved by the boundary", () => {
    // The boundary block sat outside the "not fixed" guard, so a fixed black hole
    // placed near an edge was shoved inward on its first step.
    const e = makeEngine();
    e.placeWell(8, 100);
    const well = e.particles[0];
    const x0 = well.x;
    const y0 = well.y;
    for (let i = 0; i < 20; i++) e.step();
    expect(well.x).toBe(x0);
    expect(well.y).toBe(y0);
    expect(well.vx).toBe(0);
    expect(well.vy).toBe(0);
  });

  it("the lattice restoring force does not crush orbital presets", () => {
    // The force was inferred from "has an origin, ignores gravity and is charged",
    // which also described seven orbital presets — and since an omitted charge
    // defaults to a random plus or minus one, they all got a spring pull to the
    // centre about ten times stronger than the orbital physics they were built on.
    const e = makeEngine(400, 400);
    e.spawnGalaxy(200);
    const cx = e.width / 2;
    const cy = e.height / 2;
    const meanRadius = () => {
      let sum = 0;
      let n = 0;
      for (const p of e.particles) {
        if (p.type !== "standard") continue;
        sum += Math.hypot(p.x - cx, p.y - cy);
        n++;
      }
      return n > 0 ? sum / n : 0;
    };

    const before = meanRadius();
    expect(before).toBeGreaterThan(0);
    for (const p of e.particles) expect(p.latticeBound).toBeFalsy();

    for (let i = 0; i < 30; i++) e.step();
    // The galaxy must not have collapsed toward its own centre.
    expect(meanRadius()).toBeGreaterThan(before * 0.5);
  });

  it("the lattice preset does still spring back to its origin", () => {
    const e = makeEngine(400, 400);
    e.spawnQuantumLattice(6, 6);
    const bound = e.particles.filter((p) => p.latticeBound);
    expect(bound.length).toBeGreaterThan(0);

    const p = bound[0];
    const originX = p.originX!;
    p.x = originX + 40;
    p.vx = 0;
    e.step();
    // Pulled back toward where it belongs.
    expect(p.vx).toBeLessThan(0);
  });

  it("undo restores springs and the swarm, not just the particles", () => {
    // clear() pushes an undo entry and then wipes springs, the swarm and three
    // toggles, but the snapshot only held `particles` — so undoing a clear returned
    // loose beads with no structure and an empty swarm.
    const e = makeEngine(400, 400);
    e.spawnCloth(8, 6);
    e.spawnBatch(5000);
    const particlesBefore = e.particles.length;
    const springsBefore = e.springs.length;
    const swarmBefore = e.swarm.n;
    expect(springsBefore).toBeGreaterThan(0);
    expect(swarmBefore).toBeGreaterThan(0);

    e.clear();
    expect(e.particles.length).toBe(0);
    expect(e.springs.length).toBe(0);
    expect(e.swarm.n).toBe(0);

    expect(e.undo()).toBe(true);
    expect(e.particles.length).toBe(particlesBefore);
    expect(e.springs.length).toBe(springsBefore);
    expect(e.swarm.n).toBe(swarmBefore);
  });

  it("clamping an infinite velocity does not manufacture corruption", () => {
    // Dividing the limit by infinity gives zero, and infinity times zero is
    // not-a-number — so this repair action used to create exactly the corruption it
    // exists to remove, and the pass that followed reported success.
    const e = makeEngine();
    e.addParticle({ x: 50, y: 50, vx: Infinity, vy: -Infinity });
    const { clamped } = e.clampVelocities();
    expect(clamped).toBe(1);
    expect(Number.isFinite(e.particles[0].vx)).toBe(true);
    expect(Number.isFinite(e.particles[0].vy)).toBe(true);
  });

  it("diagnostics notice an infinite velocity, not just a not-a-number one", () => {
    const e = makeEngine();
    e.addParticle({ x: 50, y: 50, vx: Infinity, vy: 0 });
    expect(e.getDiagnostics().isHealthy).toBe(false);
  });

  it("diagnostics notice corruption in the swarm", () => {
    // Every count used to cover the object particles only, while the headline figure
    // included the swarm — so a corrupt swarm reported a perfectly healthy world.
    const e = makeEngine();
    e.spawnBatch(5000);
    expect(e.getDiagnostics().isHealthy).toBe(true);
    e.swarm.v[0] = NaN;
    expect(e.getDiagnostics().isHealthy).toBe(false);
  });

  it("recentring an escaped particle stops it being pushed straight back out", () => {
    // The repair clamped the position but left the outward velocity untouched, so the
    // particle was shoved out and re-clamped every frame — stuck against the wall
    // rather than recovered.
    const e = makeEngine();
    e.addParticle({ x: e.width + 500, y: 100, vx: 50, vy: 0, ignoreGravity: true });
    e.recentreOutOfBounds();
    const p = e.particles[0];
    expect(p.x).toBeLessThanOrEqual(e.width);
    expect(p.vx).toBeLessThanOrEqual(0);
  });

  it("lowering the particle cap trims the swarm too", () => {
    // The cap covers the whole field, but lowering it only ever trimmed the objects —
    // leaving the swarm above a limit the diagnostics panel was advertising.
    const e = makeEngine();
    e.spawnBatch(50_000);
    expect(e.swarm.n).toBeGreaterThan(1000);
    e.setMaxParticles(1000);
    expect(e.bodyCount()).toBeLessThanOrEqual(1000);
  });

  it("the whole field respects the cap, objects and swarm together", () => {
    const e = makeEngine();
    e.setMaxParticles(5000);
    for (let i = 0; i < 100; i++) e.addParticle({ x: 10, y: 10 });
    e.spawnBatch(10_000);
    expect(e.bodyCount()).toBeLessThanOrEqual(5000);
  });

  it("particle ids are unique across both spawn paths", () => {
    // Batch ids were built from `particles.length + i` while length grew with each
    // push, so they skipped values and collided outright between two batches.
    const e = makeEngine();
    e.spawnBatch(50);
    e.spawnBatch(50);
    for (let i = 0; i < 20; i++) e.addParticle({ x: 5, y: 5 });
    const ids = e.particles.map((p) => p.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("an explicit radius of zero is respected", () => {
    const e = makeEngine();
    e.addParticle({ x: 10, y: 10, radius: 0 });
    expect(e.particles[0].radius).toBe(0);
  });

  it("clearing resets the world's settings, not only its contents", () => {
    // Only one of fourteen presets sets vortexForce explicitly, so switching from a
    // swirling preset into a calm one left the vortex spinning.
    const e = makeEngine();
    e.vortexForce = 5;
    e.decaySpeed = 3;
    e.boundaryMode = "void";
    e.clear();
    expect(e.vortexForce).toBe(0);
    expect(e.decaySpeed).toBe(0);
    expect(e.boundaryMode).toBe("bounce");
  });

  it("the swarm obeys the world's boundary mode", () => {
    // The swarm always bounced regardless, so switching to wrap changed the handful
    // of objects while the hundreds of thousands beside them behaved differently.
    const e = makeEngine();
    e.boundaryMode = "wrap";
    e.spawnBatch(5000);
    for (let i = 0; i < 20; i++) e.step();
    for (let i = 0; i < e.swarm.n; i++) {
      expect(e.swarm.xy[i * 2]).toBeGreaterThanOrEqual(0);
      expect(e.swarm.xy[i * 2]).toBeLessThanOrEqual(e.width);
    }
  });

  it("a spring with no rest length still works", () => {
    // `d > rest * 4.5` is true for every distance when rest is zero, so a cloth
    // spawned on a canvas too narrow to give it spacing had no working springs.
    const e = makeEngine();
    e.addParticle({ x: 100, y: 100, vx: 0, vy: 0, ignoreGravity: true });
    e.addParticle({ x: 140, y: 100, vx: 0, vy: 0, ignoreGravity: true });
    e.springs.push({ a: 0, b: 1, rest: 0, k: 0.2 });
    e.step();
    // They should be pulled together rather than ignored.
    expect(e.particles[0].vx).toBeGreaterThan(0);
    expect(e.particles[1].vx).toBeLessThan(0);
  });

  it("heavier particles respond less to a spring", () => {
    // The spring force skipped the division by mass that the electrostatic force
    // performs, so a heavy particle responded correctly to charge but far too
    // strongly to springs.
    const light = makeEngine();
    light.gravityX = 0;
    light.gravityY = 0;
    light.addParticle({ x: 100, y: 100, vx: 0, vy: 0, mass: 1, ignoreGravity: true });
    light.addParticle({ x: 160, y: 100, vx: 0, vy: 0, mass: 1, fixed: true });
    light.springs.push({ a: 0, b: 1, rest: 20, k: 0.2 });
    light.step();

    const heavy = makeEngine();
    heavy.gravityX = 0;
    heavy.gravityY = 0;
    heavy.addParticle({ x: 100, y: 100, vx: 0, vy: 0, mass: 10, ignoreGravity: true });
    heavy.addParticle({ x: 160, y: 100, vx: 0, vy: 0, mass: 1, fixed: true });
    heavy.springs.push({ a: 0, b: 1, rest: 20, k: 0.2 });
    heavy.step();

    expect(Math.abs(heavy.particles[0].vx)).toBeLessThan(Math.abs(light.particles[0].vx));
  });
});
