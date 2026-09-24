import type { ParticleObject } from "../types";
import type { ParticleCtx } from "./context";

/** Emitter Mouse Mode: continuous spawn at the cursor. */
export function spawnEmitter(e: ParticleCtx, mouseX: number, mouseY: number) {
  for (let em = 0; em < 6; em++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = Math.random() * 6 + 1;
    e.addParticle({
      x: mouseX,
      y: mouseY,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      radius: Math.random() * 3 + 1,
      color: `hsl(${Math.random() * 360}, 90%, 65%)`,
    });
  }
}

/**
 * Full physics integration step for the object-based particle list:
 * lifespans/trails, attractors, vortex, electrostatics, mouse forces,
 * springs-aware integration, gravity/damping and boundary conditions.
 * The swarm, springs and flock sub-steps follow (see the engine).
 */
export function stepParticles(e: ParticleCtx, mouseX?: number, mouseY?: number, mouseActive?: boolean) {
  const total = e.particles.length;

  // 1. Update lifespans & trails & recycling
  let hasExpired = false;
  const updateTrails = e.showTrails && total <= 1000;

  for (let i = 0; i < total; i++) {
    const p = e.particles[i];
    if (!p) continue;

    if (p.fixed) {
      p.vx = 0;
      p.vy = 0;
    }

    if (updateTrails && !p.fixed) {
      p.trail.push({ x: p.x, y: p.y });
      if (p.trail.length > 6) p.trail.shift();
    } else if (p.trail.length > 0) {
      // Discard a stale trail the moment trails stop being recorded, whether that is
      // the user switching them off or the count crossing the threshold. Left in
      // place, every particle drew a six-point streak from wherever it happened to be
      // when recording stopped.
      p.trail.length = 0;
    }

    // Automatic decay speed if configured globally
    if (e.decaySpeed > 0 && p.lifespan === undefined) {
      p.lifespan = Math.floor(100 / e.decaySpeed);
    }

    if (p.lifespan !== undefined) {
      p.lifespan--;
      if (p.lifespan <= 0) {
        if (p.originX !== undefined && p.originY !== undefined) {
          // Recycle particle rather than deleting!
          //
          // The lifespan is restored unconditionally. When `maxLife` was absent the
          // old code left it at zero or below, so the particle was teleported to its
          // origin once and then frozen there forever — skipped by the force loop,
          // never removed by the filter, but still drawn and still counted toward
          // every level-of-detail threshold.
          p.lifespan = p.maxLife && p.maxLife > 0 ? p.maxLife : 100;
          // The trail has to go too, or the next frame draws a line from wherever it
          // died clear across the world to its origin.
          p.trail.length = 0;
          const angle = Math.random() * Math.PI * 2;
          const speed = 2 + Math.random() * 7;
          p.x = p.originX + Math.cos(angle) * 15;
          p.y = p.originY + Math.sin(angle) * 15;

          if (p.originY > e.height - 50) {
            // Fountain at bottom
            const fAngle = -Math.PI / 2 + (Math.random() - 0.5) * 0.7;
            const fSpeed = Math.random() * 9 + 5;
            p.x = p.originX + (Math.random() - 0.5) * 30;
            p.y = p.originY;
            p.vx = Math.cos(fAngle) * fSpeed;
            p.vy = Math.sin(fAngle) * fSpeed;
          } else {
            p.vx = Math.cos(angle) * speed;
            p.vy = Math.sin(angle) * speed;
          }
        } else {
          hasExpired = true;
        }
      }
    }
  }

  if (hasExpired) {
    e.removeParticles((p) => p.lifespan !== undefined && p.lifespan <= 0);
  }

  const count = e.particles.length;

  // Extract special attractor/repulsor objects for O(N) interaction
  const attractors: ParticleObject[] = [];
  for (let i = 0; i < count; i++) {
    const pt = e.particles[i];
    if (pt.type === "blackhole" || pt.type === "repulsor") {
      attractors.push(pt);
    }
  }

  // Center Vortex Force
  const cx = e.width / 2;
  const cy = e.height / 2;

  // Pairwise electrostatic sampling limit
  const doPairwise = count <= 300;

  for (let i = 0; i < count; i++) {
    const p1 = e.particles[i];
    if (!p1 || (p1.lifespan !== undefined && p1.lifespan <= 0)) continue;

    // Special Attractors/Repulsors O(N)
    for (let k = 0; k < attractors.length; k++) {
      const att = attractors[k];
      if (att === p1) continue;

      // Resolved once, with fallbacks. These were guarded in the event-horizon test
      // but used bare two lines later, and imported scenes and multiplayer payloads
      // assign unvalidated values — so an undefined radius or mass wrote
      // not-a-number straight into a position or velocity, which then spread to every
      // other particle through the distance terms in the same frame.
      const attRadius = att.radius || 12;
      const attMass = att.mass || 80;

      const dx = att.x - p1.x;
      const dy = att.y - p1.y;
      const distSq = dx * dx + dy * dy + 10;
      const dist = Math.sqrt(distSq);

      if (att.type === "blackhole") {
        if (dist < attRadius + (p1.radius || 2) + 2) {
          // Particle entered event horizon! Re-emit into outer Keplerian orbit or jet!
          const G = attMass * 200;
          const isJet = Math.random() < 0.15;
          if (isJet) {
            const jetAngle = Math.random() * Math.PI * 2;
            const jetSpeed = Math.sqrt(G / 40) * 1.2;
            p1.x = att.x + Math.cos(jetAngle) * (attRadius + 8);
            p1.y = att.y + Math.sin(jetAngle) * (attRadius + 8);
            p1.vx = Math.cos(jetAngle) * jetSpeed;
            p1.vy = Math.sin(jetAngle) * jetSpeed;
          } else {
            const orbitDist = Math.random() * (Math.min(e.width, e.height) * 0.4) + 40;
            const orbitAngle = Math.random() * Math.PI * 2;
            const orbitSpeed = Math.sqrt(G / orbitDist);
            p1.x = att.x + Math.cos(orbitAngle) * orbitDist;
            p1.y = att.y + Math.sin(orbitAngle) * orbitDist;
            p1.vx = -Math.sin(orbitAngle) * orbitSpeed;
            p1.vy = Math.cos(orbitAngle) * orbitSpeed;
          }
          // The trail would otherwise stretch from the event horizon to the new orbit.
          p1.trail.length = 0;
          continue;
        }
        const force = (attMass * 200) / distSq;
        p1.vx += (dx / dist) * force;
        p1.vy += (dy / dist) * force;
      } else if (att.type === "repulsor") {
        const force = (attMass * 150) / distSq;
        p1.vx -= (dx / dist) * force;
        p1.vy -= (dy / dist) * force;
      }
    }

    // Center Vortex Attractor Force
    if (e.vortexForce !== 0) {
      const vdx = cx - p1.x;
      const vdy = cy - p1.y;
      const vdistSq = vdx * vdx + vdy * vdy + 20;
      const vdist = Math.sqrt(vdistSq);
      const vF = (e.vortexForce * 10) / vdistSq;
      // Tangential swirl + radial pull
      p1.vx += (-vdy / vdist) * vF + (vdx / vdist) * (vF * 0.2);
      p1.vy += (vdx / vdist) * vF + (vdy / vdist) * (vF * 0.2);
    }

    // Small-scale O(N^2) Electrostatic Coulomb Force
    if (doPairwise) {
      for (let j = i + 1; j < count; j++) {
        const p2 = e.particles[j];
        if (!p2 || p2.type === "blackhole" || p2.type === "repulsor") continue;

        const dx = p2.x - p1.x;
        const dy = p2.y - p1.y;
        const distSq = dx * dx + dy * dy + 10;
        const dist = Math.sqrt(distSq);

        if (p1.charge !== 0 && p2.charge !== 0) {
          const chargeProduct = p1.charge * p2.charge;
          const force = (chargeProduct * e.electrostaticFactor) / distSq;
          const fx = (dx / dist) * force;
          const fy = (dy / dist) * force;

          if (!p1.fixed) {
            p1.vx -= fx / p1.mass;
            p1.vy -= fy / p1.mass;
          }
          if (!p2.fixed) {
            p2.vx += fx / p2.mass;
            p2.vy += fy / p2.mass;
          }
        }
      }
    }

    // Mouse Interaction Force Modes
    if (mouseActive && mouseX !== undefined && mouseY !== undefined && !p1.fixed) {
      const mdx = mouseX - p1.x;
      const mdy = mouseY - p1.y;
      const mDistSq = mdx * mdx + mdy * mdy + 30;
      const mDist = Math.sqrt(mDistSq);

      const radiusCap = e.mouseRadius >= 800 ? 999999 : e.mouseRadius;
      if (mDist <= radiusCap) {
        const falloff = radiusCap > 5000 ? 1 : Math.max(0, 1 - mDist / radiusCap);
        const mult = e.mouseForceMultiplier;

        if (e.mouseMode === "attract") {
          const mForce = (1800 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
          p1.vx += (mdx / mDist) * mForce;
          p1.vy += (mdy / mDist) * mForce;
        } else if (e.mouseMode === "repel" || e.mouseMode === "hawk") {
          const mForce = (2000 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
          p1.vx -= (mdx / mDist) * mForce;
          p1.vy -= (mdy / mDist) * mForce;
        } else if (e.mouseMode === "vortex") {
          const mForce = (1400 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
          p1.vx += (-mdy / mDist) * mForce + (mdx / mDist) * (mForce * 0.1);
          p1.vy += (mdx / mDist) * mForce + (mdy / mDist) * (mForce * 0.1);
        } else if (e.mouseMode === "painter") {
          const hue = Math.floor((performance.now() / 10 + i * 5) % 360);
          p1.color = `hsl(${hue}, 95%, 65%)`;
          p1.colorUint32 = e.parseColorToUint32(p1.color);
        } else if (e.mouseMode === "gravity_well") {
          const mForce = (3500 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
          p1.vx += (mdx / mDist) * mForce - (mdy / mDist) * (mForce * 0.3);
          p1.vy += (mdy / mDist) * mForce + (mdx / mDist) * (mForce * 0.3);
        } else if (e.mouseMode === "freeze") {
          p1.vx *= 0.7;
          p1.vy *= 0.7;
        } else if (e.mouseMode === "hyper_drive") {
          p1.vx += (mdx / mDist) * (12 * mult);
          p1.vy += (mdy / mDist) * (12 * mult);
          p1.color = "#f43f5e";
          p1.colorUint32 = e.parseColorToUint32("#f43f5e");
        }
      }
    }

    if (!p1.fixed) {
      // Quantum Lattice restoring force toward its origin.
      //
      // Gated on `latticeBound`, which only the lattice preset sets. The condition
      // used to be inferred from "has an origin, ignores gravity and is charged" —
      // and because addParticle defaults an omitted charge to a random plus or minus
      // one, that description also fitted the galaxy, black hole, double vortex,
      // repulsor, solar flare, synchrotron and DNA helix presets. All seven were
      // getting a spring pull toward the centre roughly ten times stronger than the
      // orbital physics they were built around, quietly crushing them inward.
      if (p1.latticeBound && p1.originX !== undefined && p1.originY !== undefined) {
        p1.vx += (p1.originX - p1.x) * 0.02;
        p1.vy += (p1.originY - p1.y) * 0.02;
      }

      // Waterfall bottom recycling
      if (p1.originX !== undefined && p1.originY === 20 && p1.y >= e.height - 10) {
        p1.x = p1.originX + Math.random() * (e.width * 0.4);
        p1.y = 15;
        p1.vy = Math.random() * 4 + 2;
        p1.vx = (Math.random() - 0.5) * 1.5;
      }

      // DNA Helix horizontal wrapping & undulation.
      //
      // Driven by the explicit `helixStrand` flag. This used to compare `color`
      // against two hex strings, so any mouse mode that repaints a particle — painter
      // and hyper-drive both do, permanently — silently dropped it out of the helix
      // for good. Behaviour belongs to a property, not to a shade.
      if (p1.helixStrand !== undefined && p1.vx > 0) {
        if (p1.x > e.width - 10) {
          p1.x = 10;
          // Wrapping to the far side otherwise leaves the trail stretched across the
          // whole world.
          p1.trail.length = 0;
        }
        const wavelength = 120;
        const angle = (p1.x / wavelength) * Math.PI * 2;
        const targetY = e.height / 2 + Math.sin(angle) * 50 * p1.helixStrand;
        p1.vy += (targetY - p1.y) * 0.2;
      }

      // Environmental Gravity & Friction. Orbital particles are exempt so their
      // orbital energy is not continuously bled away by global damping.
      if (!p1.ignoreGravity) {
        p1.vx += e.gravityX;
        p1.vy += e.gravityY;
        p1.vx *= e.damping;
        p1.vy *= e.damping;
      }

      // Speed limit, applied to everything.
      //
      // This clamp used to live in the `else` above, so it only ever reached orbital
      // particles: every ordinary particle was completely uncapped, despite the
      // interface presenting one global "max speed" slider and the diagnostics
      // repair applying it to all particles. Uncapped speed is also what let
      // particles cross a whole world in one frame and escape the wrap boundary.
      const spdSq = p1.vx * p1.vx + p1.vy * p1.vy;
      const limitSq = e.maxSpeed * e.maxSpeed;
      if (spdSq > limitSq && spdSq > 0) {
        const scale = e.maxSpeed / Math.sqrt(spdSq);
        p1.vx *= scale;
        p1.vy *= scale;
      }

      p1.x += p1.vx;
      p1.y += p1.vy;
    }

    // Boundary Conditions.
    //
    // Pinned particles are exempt. This whole block used to sit outside the
    // `if (!p1.fixed)` above, so a fixed black hole placed near an edge was shoved
    // inward on its very first step — and since velocity is only zeroed for fixed
    // particles at the top of the tick, the bounce code was acting on velocity that
    // the force loop had accumulated since.
    if (p1.fixed) {
      p1.vx = 0;
      p1.vy = 0;
      continue;
    }

    const rad = p1.radius || e.particleSize;

    if (e.boundaryMode === "bounce") {
      if (p1.x - rad < 0) {
        p1.x = rad;
        p1.vx *= -e.elasticity;
      } else if (p1.x + rad > e.width) {
        p1.x = e.width - rad;
        p1.vx *= -e.elasticity;
      }

      if (p1.y - rad < 0) {
        p1.y = rad;
        p1.vy *= -e.elasticity;
      } else if (p1.y + rad > e.height) {
        p1.y = e.height - rad;
        p1.vy *= -e.elasticity;
      }
    } else if (e.boundaryMode === "wrap") {
      // True modulo rather than a single add or subtract. One correction per frame
      // left anything travelling more than a world-width per frame permanently
      // outside the world, and `x === width` exactly stayed one pixel past the edge
      // the renderer draws.
      if (e.width > 0) p1.x = ((p1.x % e.width) + e.width) % e.width;
      if (e.height > 0) p1.y = ((p1.y % e.height) + e.height) % e.height;
    } else if (e.boundaryMode === "void") {
      if (p1.x < -10 || p1.x > e.width + 10 || p1.y < -10 || p1.y > e.height + 10) {
        p1.lifespan = 0;
        hasExpired = true;
      }
    }
  }

  if (hasExpired) {
    e.removeParticles((p) => p.lifespan !== undefined && p.lifespan <= 0);
  }
}

/**
 * Boids-style flocking for up to 360 particles: cohesion + alignment + separation.
 */
export function stepFlock(e: ParticleCtx) {
  const ps = e.particles;
  const n = Math.min(ps.length, 360);
  for (let i = 0; i < n; i++) {
    const p = ps[i];
    if (!p || p.fixed) continue;
    let cx = 0, cy = 0, cvx = 0, cvy = 0, sepX = 0, sepY = 0, c = 0;
    for (let j = 0; j < n; j++) {
      if (i === j) continue;
      const q = ps[j];
      // Guarded and pinned-aware, like `p` above. A missing neighbour threw, and a
      // fixed neighbour was averaged into the flock's velocity as though it were
      // flying with them.
      if (!q || q.fixed) continue;
      const dx = q.x - p.x;
      const dy = q.y - p.y;
      const d2 = dx * dx + dy * dy;
      if (d2 > 3600 || d2 < 0.01) continue;
      c++;
      cx += q.x;
      cy += q.y;
      cvx += q.vx;
      cvy += q.vy;
      if (d2 < 400) {
        // Divided by distance, so closer neighbours push harder. Accumulating the
        // raw offset made separation *weaker* the closer two particles got — exactly
        // backwards for collision avoidance, and the reason flocks clumped.
        const d = Math.sqrt(d2);
        sepX -= dx / d;
        sepY -= dy / d;
      }
    }
    if (!c) continue;
    // Separation is scaled up to compensate for now being normalised by distance.
    p.vx += (cx / c - p.x) * 0.002 + (cvx / c - p.vx) * 0.04 + sepX * 0.24;
    p.vy += (cy / c - p.y) * 0.002 + (cvy / c - p.vy) * 0.04 + sepY * 0.24;
  }
}

/** Hookean spring constraints (cloth / rope / blob). */
export function stepSprings(e: ParticleCtx) {
  if (!e.springs.length) return;
  const ps = e.particles;
  for (const s of e.springs) {
    const a = ps[s.a];
    const b = ps[s.b];
    if (!a || !b) continue;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const d = Math.sqrt(dx * dx + dy * dy) || 0.001;
    // A rest length of zero made `d > rest * 4.5` true for every spring, so a cloth
    // spawned on a canvas too narrow to give it any spacing had no working springs
    // at all.
    if (s.rest > 0 && d > s.rest * 4.5) continue;
    const f = ((d - s.rest) / d) * s.k;
    const fx = dx * f;
    const fy = dy * f;
    // Divided by mass, like the electrostatic force is. Without it a heavier
    // particle responded correctly to charge but far too strongly to springs.
    if (!a.fixed) {
      const am = a.mass || 1;
      a.vx += fx / am;
      a.vy += fy / am;
    }
    if (!b.fixed) {
      const bm = b.mass || 1;
      b.vx -= fx / bm;
      b.vy -= fy / bm;
    }
  }
}

/**
 * Mouse modes that mean something to the swarm, and which way they pull.
 *
 * The swarm only understands "pull toward" or "push away", so every mode has to map
 * onto one of those or be ignored. Previously anything that was not attract or
 * gravity_well was treated as repulsion, which meant painter, freeze and emitter —
 * modes with well-defined and quite different meanings for the object particles —
 * silently blew the swarm outward instead.
 */
function swarmMouseEffect(mode: ParticleCtx["mouseMode"]): "attract" | "repel" | null {
  switch (mode) {
    case "attract":
    case "gravity_well":
    case "hawk":
      return "attract";
    case "repel":
    case "hyper_drive":
      return "repel";
    case "vortex":
    case "emitter":
    case "painter":
    case "freeze":
      // Nothing sensible to do to a million positions, so the swarm is left alone
      // rather than being pushed around by a mode that means something else.
      return null;
  }
}

/** Step the SoA swarm (GPU above threshold, CPU otherwise). */
export function stepSwarm(e: ParticleCtx, mouseX?: number, mouseY?: number, mouseActive?: boolean) {
  if (!e.swarm.n) return;
  const effect = swarmMouseEffect(e.mouseMode);
  e.swarm.step({
    width: e.width,
    height: e.height,
    gx: e.gravityX,
    gy: e.gravityY,
    damp: e.damping,
    bounce: e.elasticity,
    collide: e.collisionsEnabled,
    maxSpeed: e.maxSpeed,
    boundaryMode: e.boundaryMode,
    mx: mouseX ?? e.lastMouseX,
    my: mouseY ?? e.lastMouseY,
    mouse: !!mouseActive && effect !== null,
    mouseForce: e.mouseForceMultiplier * (e.mouseMode === "hawk" ? 2.4 : 1),
    mouseRadius: e.mouseRadius,
    attract: effect === "attract",
  });
}
