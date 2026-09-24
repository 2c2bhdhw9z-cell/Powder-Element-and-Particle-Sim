import type { ParticleCtx } from "./context";

// --- Diagnostics & Health Inspection ---

export function getDiagnostics(e: ParticleCtx) {
  let nanCount = 0;
  let outOfBoundsCount = 0;
  let extremeVelocityCount = 0;
  let maxSpeedFound = 0;
  // Accumulated in the main pass rather than in a second walk of the same array.
  // Counting trail points used to be a separate loop over every particle, which on a
  // large field is a second million-element traversal for one addition per element.
  let trailPoints = 0;

  // The threshold is the world's own speed limit, not a hardcoded 100. With the two
  // out of step, particles well past the limit were reported "healthy" while the
  // repair action clamped them anyway, and at a high limit nothing in between was
  // reported at all.
  const speedLimit = e.maxSpeed > 0 ? e.maxSpeed : Infinity;

  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    if (p.trail) trailPoints += p.trail.length;
    // `isFinite`, not `!isNaN`: an infinite coordinate or velocity is just as corrupt
    // and used to pass straight through as healthy.
    if (!Number.isFinite(p.x) || !Number.isFinite(p.y) || !Number.isFinite(p.vx) || !Number.isFinite(p.vy)) {
      nanCount++;
    } else {
      if (p.x < -100 || p.x > e.width + 100 || p.y < -100 || p.y > e.height + 100) {
        outOfBoundsCount++;
      }
      const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (speed > maxSpeedFound) maxSpeedFound = speed;
      if (speed > speedLimit) extremeVelocityCount++;
    }
  }

  // The swarm is inspected too. Every count above used to cover only the object
  // particles while the headline particle count included the swarm, so a swarm gone
  // corrupt — entirely possible, since its gravity comes straight from the device's
  // motion sensors — reported a perfectly healthy world.
  let swarmCorruptCount = 0;
  const swarmXY = e.swarm.xy;
  const swarmV = e.swarm.v;
  for (let i = 0; i < e.swarm.n; i++) {
    const i2 = i * 2;
    if (
      !Number.isFinite(swarmXY[i2]) ||
      !Number.isFinite(swarmXY[i2 + 1]) ||
      !Number.isFinite(swarmV[i2]) ||
      !Number.isFinite(swarmV[i2 + 1])
    ) {
      swarmCorruptCount++;
      continue;
    }
    const speed = Math.sqrt(swarmV[i2] * swarmV[i2] + swarmV[i2 + 1] * swarmV[i2 + 1]);
    if (speed > maxSpeedFound) maxSpeedFound = speed;
    // Counted, like the object particles. The swarm only fed the headline top speed, so
    // the report could show a top speed of 900 beside a count of zero particles over
    // the limit — and an escaped swarm was invisible to the automatic pass.
    if (speed > speedLimit) extremeVelocityCount++;
  }
  nanCount += swarmCorruptCount;

  const issues: string[] = [];
  if (nanCount > 0) issues.push(`Detected ${nanCount} particles with corrupt coordinates or velocities`);
  if (outOfBoundsCount > 0) issues.push(`Detected ${outOfBoundsCount} particles drifted outside viewport boundary`);
  if (extremeVelocityCount > 0) issues.push(`Detected ${extremeVelocityCount} particles exceeding the ${Math.round(speedLimit)} speed limit`);

  const approxMemoryBytes =
    e.particles.length * 128 +
    trailPoints * 32 +
    e.swarm.xy.byteLength +
    e.swarm.v.byteLength +
    e.swarm.color.byteLength +
    (e.imgData ? e.imgData.data.byteLength : 0);

  return {
    particleCount: e.particles.length + e.swarm.n,
    maxParticles: e.maxParticles,
    nanCount,
    /**
     * How much of `nanCount` belongs to the swarm.
     *
     * Reported separately because the two halves need different repairs: the object
     * particles are removed, the swarm's entries are reset in place. Without this the
     * automatic pass could only reach the object half, so it announced "purged 0" for a
     * corrupt swarm and left the issue on the list permanently.
     */
    swarmCorruptCount,
    outOfBoundsCount,
    extremeVelocityCount,
    maxSpeedFound: Math.round(maxSpeedFound),
    memoryBytes: approxMemoryBytes,
    isHealthy: issues.length === 0,
    issues,
  };
}

// --- Manual Fix Actions ---

export function purgeNaNParticles(e: ParticleCtx): { success: boolean; purged: number } {
  // `isFinite`, not `!isNaN`: infinities are just as corrupt and used to pass
  // straight through here. Routed through removeParticles so spring endpoints
  // survive the purge.
  const purged = e.removeParticles(
    (p) => !Number.isFinite(p.x) || !Number.isFinite(p.y) || !Number.isFinite(p.vx) || !Number.isFinite(p.vy),
  );
  return { success: true, purged };
}

export function clampVelocities(e: ParticleCtx): { success: boolean; clamped: number } {
  let clamped = 0;
  // The same reading of the limit the inspection uses: a limit of zero or less means
  // "no limit", not "freeze everything". Taken literally — and `maxSpeed` is a plain
  // field, so anything can put a zero there — every particle in the world was
  // multiplied by a factor of zero and stopped dead, while the inspection that
  // triggered the repair had treated the same value as no limit at all and reported
  // nothing wrong.
  const limit = e.maxSpeed > 0 ? e.maxSpeed : Infinity;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    // Non-finite velocity is reset rather than scaled. Dividing the limit by
    // infinity gives zero, and infinity times zero is not-a-number — so this repair
    // action used to manufacture exactly the corruption it exists to remove, and the
    // pass that followed reported success because it had already decided what to do.
    if (!Number.isFinite(p.vx) || !Number.isFinite(p.vy)) {
      p.vx = 0;
      p.vy = 0;
      clamped++;
      continue;
    }
    const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
    if (speed > limit && speed > 0) {
      const factor = limit / speed;
      p.vx *= factor;
      p.vy *= factor;
      clamped++;
    }
  }
  return { success: true, clamped };
}

/**
 * Zeroes any swarm position or velocity that is not a real number.
 *
 * The swarm had no repair at all. Its corruption was counted into the headline figure,
 * so the report said "17 corrupt particles", the purge said it had removed none — it
 * only ever touched the object list — and the issue stayed on the list forever with no
 * way to clear it.
 *
 * Corrupt entries are reset rather than removed: the swarm is a flat pair of buffers
 * with no per-body identity, so removing one would mean compacting a million entries
 * to no visible benefit.
 */
export function repairSwarm(e: ParticleCtx): { success: boolean; repaired: number } {
  let repaired = 0;
  const xy = e.swarm.xy;
  const v = e.swarm.v;
  const limit = e.maxSpeed > 0 ? e.maxSpeed : Infinity;
  for (let i = 0; i < e.swarm.n; i++) {
    const i2 = i * 2;
    let touched = false;
    if (!Number.isFinite(xy[i2]) || !Number.isFinite(xy[i2 + 1])) {
      // Back to the middle of the world, which is the only position guaranteed valid.
      xy[i2] = e.width / 2;
      xy[i2 + 1] = e.height / 2;
      touched = true;
    }
    if (!Number.isFinite(v[i2]) || !Number.isFinite(v[i2 + 1])) {
      v[i2] = 0;
      v[i2 + 1] = 0;
      touched = true;
    } else if (Number.isFinite(limit)) {
      const speed = Math.sqrt(v[i2] * v[i2] + v[i2 + 1] * v[i2 + 1]);
      if (speed > limit && speed > 0) {
        const factor = limit / speed;
        v[i2] *= factor;
        v[i2 + 1] *= factor;
        touched = true;
      }
    }
    if (touched) repaired++;
  }
  return { success: true, repaired };
}

/**
 * Brings escaped particles back inside the world.
 *
 * Renamed from `wrapOrTrimOutOfBounds`, which described neither of the two things
 * it does. It also now clamps to the particle's radius rather than to the exact
 * edge, and zeroes the outward velocity component — without that, a "repaired"
 * particle was pushed straight back out and re-clamped every frame, leaving it
 * stuck against the wall rather than recovered.
 */
export function recentreOutOfBounds(e: ParticleCtx): { success: boolean; trimmed: number } {
  let trimmed = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    // `!== undefined`, not a truthiness test. A radius of exactly zero is a legitimate
    // value that `addParticle` goes out of its way to preserve, and a falsy test
    // silently replaced it with the default size — quietly resizing a particle inside
    // a repair that is only supposed to move it.
    const rad = p.radius !== undefined && Number.isFinite(p.radius) ? p.radius : e.particleSize;
    const minX = Math.min(rad, e.width / 2);
    const maxX = Math.max(minX, e.width - rad);
    const minY = Math.min(rad, e.height / 2);
    const maxY = Math.max(minY, e.height - rad);
    if (p.x < minX || p.x > maxX || p.y < minY || p.y > maxY) {
      if (p.x < minX) {
        p.x = minX;
        if (p.vx < 0) p.vx = 0;
      } else if (p.x > maxX) {
        p.x = maxX;
        if (p.vx > 0) p.vx = 0;
      }
      if (p.y < minY) {
        p.y = minY;
        if (p.vy < 0) p.vy = 0;
      } else if (p.y > maxY) {
        p.y = maxY;
        if (p.vy > 0) p.vy = 0;
      }
      trimmed++;
    }
  }
  return { success: true, trimmed };
}

export function reallocateBuffers(e: ParticleCtx): { success: boolean } {
  e.imgData = null;
  e.buf32 = null;
  return { success: true };
}

/**
 * Brings every particle to rest.
 *
 * Renamed from `zeroForces`: this engine has no force accumulators, so the old name
 * described something that does not exist. It also now skips pinned particles and
 * attractors — stopping a black hole was never the intent — and counts only the
 * particles it actually changed rather than every particle it looked at.
 */
export function haltAllMotion(e: ParticleCtx): { success: boolean; resetCount: number } {
  let resetCount = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p || p.fixed) continue;
    if (p.vx === 0 && p.vy === 0) continue;
    p.vx = 0;
    p.vy = 0;
    resetCount++;
  }
  return { success: true, resetCount };
}

/**
 * Rebalances charge across the charged particles.
 *
 * Only touches particles that already carry a charge, and leaves attractors alone.
 * The original assigned plus or minus one to *every* particle, which destroyed
 * deliberately neutral ones — zero charge is how a particle opts out of the Coulomb
 * force entirely — and gave black holes and repulsors a charge they should not have.
 * With an odd count it also reported a balance it had not achieved.
 */
export function resetCharges(e: ParticleCtx): { success: boolean; balancedCount: number } {
  const charged: number[] = [];
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p || p.charge === 0) continue;
    if (p.type === "blackhole" || p.type === "repulsor") continue;
    charged.push(i);
  }
  // Alternating plus and minus over an even number of particles, and the odd one out —
  // if there is one — made neutral so the total really does come to zero.
  //
  // It used to be skipped entirely, which left it carrying whatever it had before,
  // possibly a charge of five. The function reported a balanced field and had not
  // produced one.
  const paired = charged.length - (charged.length % 2);
  for (let k = 0; k < paired; k++) {
    const p = e.particles[charged[k]];
    // Re-checked rather than assumed. Nothing mutates the list between the two loops
    // today, but the indices were captured earlier and a stale one would otherwise be
    // dereferenced blindly.
    if (p) p.charge = k % 2 === 0 ? 1 : -1;
  }
  if (paired !== charged.length) {
    const odd = e.particles[charged[charged.length - 1]];
    if (odd) odd.charge = 0;
  }
  return { success: true, balancedCount: charged.length };
}

// --- Stress Test Injectors (for testing debug diagnostics) ---

export function injectCorruptVectorParticles(e: ParticleCtx): { success: boolean } {
  for (let i = 0; i < 15; i++) {
    e.addParticle({
      x: NaN,
      y: NaN,
      vx: 1000,
      vy: NaN,
      radius: 4,
      color: "#ff0055",
    });
  }
  return { success: true };
}

export function injectHyperVelocityExplosion(e: ParticleCtx): { success: boolean } {
  const cx = e.width / 2;
  const cy = e.height / 2;
  for (let i = 0; i < 50; i++) {
    const angle = Math.random() * Math.PI * 2;
    e.addParticle({
      x: cx,
      y: cy,
      vx: Math.cos(angle) * 250,
      vy: Math.sin(angle) * 250,
      radius: 5,
      color: "#f97316",
    });
  }
  return { success: true };
}

// --- Automated Diagnostics Pass ---

export function runAutoFix(e: ParticleCtx): { logs: string[] } {
  const logs: string[] = [];
  logs.push("Initiating Particle Simulator Automated Diagnostics Pass...");

  if (getDiagnostics(e).isHealthy) {
    logs.push("✓ All particle vectors, velocities, and pixel buffers verified normal.");
    logs.push("✓ No critical anomalies detected.");
    return { logs };
  }

  // Each stage re-inspects the world instead of all of them deciding from one
  // snapshot taken before any repair. That, combined with clamping running last,
  // meant a clamp that produced fresh corruption was never purged — and the final
  // report cheerfully called it "RECOVERY COMPLETED".
  //
  // Velocities are clamped BEFORE the purge for the same reason: clamping is the
  // stage that can introduce a bad value, so the purge has to come after it.
  const steps: string[] = [];

  if (getDiagnostics(e).extremeVelocityCount > 0) {
    const res = clampVelocities(e);
    steps.push(`Clamped velocities for ${res.clamped} hyper-fast particles.`);
  }

  const beforePurge = getDiagnostics(e);
  // The object half and the swarm half are counted together but repaired differently,
  // so each is checked against its own figure. Purging only ever touched the object
  // list, so a corrupt swarm produced "Purged 0 corrupt particles" and an issue that
  // could never be cleared.
  if (beforePurge.nanCount - beforePurge.swarmCorruptCount > 0) {
    const res = purgeNaNParticles(e);
    steps.push(`Purged ${res.purged} corrupt particles.`);
  }

  if (getDiagnostics(e).swarmCorruptCount > 0) {
    const res = repairSwarm(e);
    steps.push(`Repaired ${res.repaired} corrupt swarm particles.`);
  }

  if (getDiagnostics(e).outOfBoundsCount > 0) {
    const res = recentreOutOfBounds(e);
    steps.push(`Brought ${res.trimmed} escaped particles back inside the world.`);
  }

  reallocateBuffers(e);
  steps.push("Re-allocated canvas pixel buffers successfully.");

  steps.forEach((message, i) => logs.push(`✓ Auto-Fix Step ${i + 1}/${steps.length}: ${message}`));

  const postDiag = getDiagnostics(e);
  if (postDiag.isHealthy) {
    logs.push("Auto-Fix Sequence Completed. System health status: 100% OPERATIONAL.");
  } else {
    // Says so plainly rather than dressing a failure up as a recovery.
    logs.push(`Auto-Fix Sequence Completed, but ${postDiag.issues.length} issue(s) remain:`);
    for (const issue of postDiag.issues) logs.push(`  • ${issue}`);
  }
  return { logs };
}
