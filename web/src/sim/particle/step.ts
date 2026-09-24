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
          if (p.maxLife) p.lifespan = p.maxLife;
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
    e.particles = e.particles.filter((p) => p && (p.lifespan === undefined || p.lifespan > 0));
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

      const dx = att.x - p1.x;
      const dy = att.y - p1.y;
      const distSq = dx * dx + dy * dy + 10;
      const dist = Math.sqrt(distSq);

      if (att.type === "blackhole") {
        if (dist < (att.radius || 12) + (p1.radius || 2) + 2) {
          // Particle entered event horizon! Re-emit into outer Keplerian orbit or jet!
          const G = (att.mass || 80) * 200;
          const isJet = Math.random() < 0.15;
          if (isJet) {
            const jetAngle = Math.random() * Math.PI * 2;
            const jetSpeed = Math.sqrt(G / 40) * 1.2;
            p1.x = att.x + Math.cos(jetAngle) * (att.radius + 8);
            p1.y = att.y + Math.sin(jetAngle) * (att.radius + 8);
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
          continue;
        }
        const force = (att.mass * 200) / distSq;
        p1.vx += (dx / dist) * force;
        p1.vy += (dy / dist) * force;
      } else if (att.type === "repulsor") {
        const force = (att.mass * 150) / distSq;
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
      // Quantum Lattice spring restoring force to origin
      if (p1.originX !== undefined && p1.originY !== undefined && p1.ignoreGravity && p1.charge !== 0) {
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

      // DNA Helix horizontal wrapping & undulation
      if (p1.ignoreGravity && p1.vx > 0 && (p1.color === "#06b6d4" || p1.color === "#a855f7")) {
        if (p1.x > e.width - 10) {
          p1.x = 10;
        }
        const wavelength = 120;
        const angle = (p1.x / wavelength) * Math.PI * 2;
        const dir = p1.color === "#06b6d4" ? 1 : -1;
        const targetY = e.height / 2 + Math.sin(angle) * 50 * dir;
        p1.vy += (targetY - p1.y) * 0.2;
      }

      // Environmental Gravity & Friction
      if (!p1.ignoreGravity) {
        p1.vx += e.gravityX;
        p1.vy += e.gravityY;
        p1.vx *= e.damping;
        p1.vy *= e.damping;
      } else {
        // Speed check for orbital particles so orbital energy isn't continuously bled by global damping
        const spdSq = p1.vx * p1.vx + p1.vy * p1.vy;
        if (spdSq > e.maxSpeed * e.maxSpeed) {
          const spd = Math.sqrt(spdSq);
          p1.vx = (p1.vx / spd) * e.maxSpeed;
          p1.vy = (p1.vy / spd) * e.maxSpeed;
        }
      }

      p1.x += p1.vx;
      p1.y += p1.vy;
    }

    // Boundary Conditions
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
      if (p1.x < 0) p1.x += e.width;
      if (p1.x > e.width) p1.x -= e.width;
      if (p1.y < 0) p1.y += e.height;
      if (p1.y > e.height) p1.y -= e.height;
    } else if (e.boundaryMode === "void") {
      if (p1.x < -10 || p1.x > e.width + 10 || p1.y < -10 || p1.y > e.height + 10) {
        p1.lifespan = 0;
        hasExpired = true;
      }
    }
  }

  if (hasExpired) {
    e.particles = e.particles.filter((p) => p && (p.lifespan === undefined || p.lifespan > 0));
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
        sepX -= dx;
        sepY -= dy;
      }
    }
    if (!c) continue;
    p.vx += (cx / c - p.x) * 0.002 + (cvx / c - p.vx) * 0.04 + sepX * 0.012;
    p.vy += (cy / c - p.y) * 0.002 + (cvy / c - p.vy) * 0.04 + sepY * 0.012;
  }
}

/** Verlet-style spring constraints (cloth / rope / blob). */
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
    if (d > s.rest * 4.5) continue;
    const f = ((d - s.rest) / d) * s.k;
    const fx = dx * f;
    const fy = dy * f;
    if (!a.fixed) {
      a.vx += fx;
      a.vy += fy;
    }
    if (!b.fixed) {
      b.vx -= fx;
      b.vy -= fy;
    }
  }
}

/** Step the SoA swarm (GPU above threshold, CPU otherwise). */
export function stepSwarm(e: ParticleCtx, mouseX?: number, mouseY?: number, mouseActive?: boolean) {
  if (!e.swarm.n) return;
  e.swarm.step({
    width: e.width,
    height: e.height,
    gx: e.gravityX,
    gy: e.gravityY,
    damp: e.damping,
    bounce: e.elasticity,
    collide: e.collisionsEnabled,
    mx: mouseX ?? e.lastMouseX,
    my: mouseY ?? e.lastMouseY,
    mouse: !!mouseActive,
    mouseForce: e.mouseForceMultiplier * (e.mouseMode === "hawk" ? 2.4 : 1),
    mouseRadius: e.mouseRadius,
    attract: e.mouseMode === "attract" || e.mouseMode === "gravity_well",
  });
}
