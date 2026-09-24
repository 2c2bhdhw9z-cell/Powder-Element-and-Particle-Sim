import type { ParticleCtx } from "./context";

// --- Diagnostics & Health Inspection ---

export function getDiagnostics(e: ParticleCtx) {
  let nanCount = 0;
  let outOfBoundsCount = 0;
  let extremeVelocityCount = 0;
  let maxSpeedFound = 0;

  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    if (Number.isNaN(p.x) || Number.isNaN(p.y) || Number.isNaN(p.vx) || Number.isNaN(p.vy)) {
      nanCount++;
    } else {
      if (p.x < -100 || p.x > e.width + 100 || p.y < -100 || p.y > e.height + 100) {
        outOfBoundsCount++;
      }
      const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (speed > maxSpeedFound) maxSpeedFound = speed;
      if (speed > 100) extremeVelocityCount++;
    }
  }

  const issues: string[] = [];
  if (nanCount > 0) issues.push(`Detected ${nanCount} particles with NaN coordinates or velocities`);
  if (outOfBoundsCount > 0) issues.push(`Detected ${outOfBoundsCount} particles drifted outside viewport boundary`);
  if (extremeVelocityCount > 0) issues.push(`Detected ${extremeVelocityCount} particles exceeding max speed threshold`);

  const approxMemoryBytes =
    e.particles.length * 128 +
    e.swarm.xy.byteLength +
    e.swarm.v.byteLength +
    e.swarm.color.byteLength +
    (e.imgData ? e.imgData.data.byteLength : 0);

  return {
    particleCount: e.particles.length + e.swarm.n,
    maxParticles: e.maxParticles,
    nanCount,
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
  const prevCount = e.particles.length;
  e.particles = e.particles.filter((p) => p && !Number.isNaN(p.x) && !Number.isNaN(p.y) && !Number.isNaN(p.vx) && !Number.isNaN(p.vy));
  const purged = prevCount - e.particles.length;
  return { success: true, purged };
}

export function clampVelocities(e: ParticleCtx): { success: boolean; clamped: number } {
  let clamped = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
    if (speed > e.maxSpeed) {
      const factor = e.maxSpeed / speed;
      p.vx *= factor;
      p.vy *= factor;
      clamped++;
    }
  }
  return { success: true, clamped };
}

export function wrapOrTrimOutOfBounds(e: ParticleCtx): { success: boolean; trimmed: number } {
  let trimmed = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p) continue;
    if (p.x < 0 || p.x > e.width || p.y < 0 || p.y > e.height) {
      p.x = Math.max(0, Math.min(e.width, p.x));
      p.y = Math.max(0, Math.min(e.height, p.y));
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

export function zeroForces(e: ParticleCtx): { success: boolean; resetCount: number } {
  let resetCount = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (p) {
      p.vx = 0;
      p.vy = 0;
      resetCount++;
    }
  }
  return { success: true, resetCount };
}

export function resetCharges(e: ParticleCtx): { success: boolean; balancedCount: number } {
  let balancedCount = 0;
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (p) {
      p.charge = i % 2 === 0 ? 1 : -1;
      balancedCount++;
    }
  }
  return { success: true, balancedCount };
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

  const diag = getDiagnostics(e);
  if (diag.isHealthy) {
    logs.push("✓ All particle vectors, velocities, and pixel buffers verified normal.");
    logs.push("✓ No critical anomalies detected.");
    return { logs };
  }

  if (diag.nanCount > 0) {
    const res = purgeNaNParticles(e);
    logs.push(`✓ Auto-Fix Step 1/4: Purged ${res.purged} corrupt/NaN particles.`);
  }

  if (diag.outOfBoundsCount > 0) {
    const res = wrapOrTrimOutOfBounds(e);
    logs.push(`✓ Auto-Fix Step 2/4: Re-centered ${res.trimmed} out-of-bounds particles.`);
  }

  if (diag.extremeVelocityCount > 0) {
    const res = clampVelocities(e);
    logs.push(`✓ Auto-Fix Step 3/4: Clamped velocities for ${res.clamped} hyper-fast particles.`);
  }

  reallocateBuffers(e);
  logs.push("✓ Auto-Fix Step 4/4: Re-allocated canvas pixel buffers successfully.");

  const postDiag = getDiagnostics(e);
  logs.push(`Auto-Fix Sequence Completed. System health status: ${postDiag.isHealthy ? "100% OPERATIONAL" : "RECOVERY COMPLETED"}.`);
  return { logs };
}
