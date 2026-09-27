import { getParticleEngine, getPowderEngine } from "./engines";

export const hybrid = {
  enabled: true,
};

let settleClock = 0;

export function wireHybrid() {
  getPowderEngine().onBurst = (x, y, r) => {
    if (!hybrid.enabled) return;
    burstFromPowder(x, y, r);
  };
  getParticleEngine().onAfterStep = () => {
    if (!hybrid.enabled) return;
    settleClock++;
    if (settleClock % 6 !== 0) return;
    autoSettle(6);
  };
}

export function burstFromPowder(gx: number, gy: number, radius: number) {
  const powder = getPowderEngine();
  const particles = getParticleEngine();
  const n = Math.min(220, Math.max(24, Math.round(radius * 4)));
  const sx = (gx / Math.max(1, powder.width)) * particles.width;
  const sy = (gy / Math.max(1, powder.height)) * particles.height;
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2;
    const spd = 2 + Math.random() * 7;
    particles.addParticle({
      x: sx + (Math.random() - 0.5) * 10,
      y: sy + (Math.random() - 0.5) * 10,
      vx: Math.cos(a) * spd,
      vy: Math.sin(a) * spd - 2,
      radius: 1.6 + Math.random(),
      color: Math.random() < 0.5 ? "#f97316" : "#eab308",
      lifespan: 90 + Math.floor(Math.random() * 50),
    });
  }
}

export function autoSettle(limit = 8): number {
  const powder = getPowderEngine();
  const particles = getParticleEngine();
  const floor = particles.height - 8;
  let settled = 0;
  for (let i = particles.particles.length - 1; i >= 0 && settled < limit; i--) {
    const p = particles.particles[i];
    if (!p || p.type === "blackhole" || p.type === "repulsor" || p.fixed) continue;
    const slow = p.vx * p.vx + p.vy * p.vy < 6;
    if (p.y < floor || !slow) continue;
    const gx = Math.floor((p.x / particles.width) * powder.width);
    const gy = Math.min(powder.height - 3, Math.floor((p.y / particles.height) * powder.height));
    if (!powder.isValid(gx, gy)) continue;
    if (powder.gridType[powder.getIndex(gx, gy)] !== 0) continue;
    const waterish = p.color?.includes("38bdf8") || p.color?.includes("06b6d4") || p.color?.includes("3b82f6");
    powder.setElementAt(gx, gy, waterish ? 2 : 1);
    particles.particles.splice(i, 1);
    settled++;
  }
  return settled;
}

export function settleToPowder(): number {
  const powder = getPowderEngine();
  const particles = getParticleEngine();
  let settled = 0;
  const keep = [];
  const floor = particles.height - 10;
  for (let i = 0; i < particles.particles.length; i++) {
    const p = particles.particles[i];
    if (!p || p.type === "blackhole" || p.type === "repulsor" || p.fixed) {
      keep.push(p);
      continue;
    }
    const slow = p.vx * p.vx + p.vy * p.vy < 9;
    if (p.y < floor && !slow) {
      keep.push(p);
      continue;
    }
    const gx = Math.floor((p.x / particles.width) * powder.width);
    const gy = Math.floor((p.y / particles.height) * powder.height);
    if (!powder.isValid(gx, gy)) {
      keep.push(p);
      continue;
    }
    const id = p.color?.includes("06b6d4") || p.color?.includes("3b82f6") ? 2 : 1;
    if (powder.gridType[powder.getIndex(gx, gy)] === 0) {
      powder.setElementAt(gx, gy, id);
      settled++;
    } else {
      keep.push(p);
    }
  }
  particles.particles = keep.filter(Boolean) as typeof particles.particles;
  return settled;
}
