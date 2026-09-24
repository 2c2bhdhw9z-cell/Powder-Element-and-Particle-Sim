import { getParticleEngine, getPowderEngine } from "./engines";

const KEY = "crucible.autosave.v1";

export function writeAutosave() {
  if (typeof localStorage === "undefined") return;
  try {
    const pe = getParticleEngine();
    const list = pe.particles.slice(0, 4000);
    localStorage.setItem(
      KEY,
      JSON.stringify({
        at: Date.now(),
        powder: getPowderEngine().serializeState(),
        particle: {
          gx: pe.gravityX,
          gy: pe.gravityY,
          damp: pe.damping,
          collide: pe.collisionsEnabled,
          fluid: pe.fluidEnabled,
          swarm: pe.swarm.n > 0 && pe.swarm.n <= 12000 ? pe.swarm.toSplit() : undefined,
          particles: list.map((p) => ({
            x: p.x,
            y: p.y,
            vx: p.vx,
            vy: p.vy,
            r: p.radius,
            c: p.color,
            t: p.type,
            f: p.fixed ? 1 : 0,
          })),
        },
      }),
    );
  } catch {
    /* quota */
  }
}

export function readAutosave(): boolean {
  if (typeof localStorage === "undefined") return false;
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return false;
    const data = JSON.parse(raw) as {
      powder?: string;
      particle?: {
        gx: number;
        gy: number;
        damp: number;
        collide: boolean;
        fluid?: boolean;
        swarm?: { n: number; x: number[]; y: number[]; vx: number[]; vy: number[]; c: number[] };
        particles: Array<{
          x: number;
          y: number;
          vx: number;
          vy: number;
          r: number;
          c: string;
          t?: string;
          f?: number;
        }>;
      };
    };
    const powder = getPowderEngine();
    const pe = getParticleEngine();
    if (data.powder) powder.deserializeState(data.powder);
    powder.keepWorld = true;
    if (data.particle) {
      pe.gravityX = data.particle.gx;
      pe.gravityY = data.particle.gy;
      pe.damping = data.particle.damp;
      pe.collisionsEnabled = data.particle.collide;
      pe.fluidEnabled = !!data.particle.fluid;
      pe.particles = [];
      pe.swarm.clear();
      const sw = data.particle.swarm;
      if (sw && sw.n) {
        pe.swarm.fromSplit(sw, pe.width, pe.height, pe.maxParticles);
      }
      for (const p of data.particle.particles || []) {
        pe.addParticle({
          x: p.x,
          y: p.y,
          vx: p.vx,
          vy: p.vy,
          radius: p.r,
          color: p.c,
          type: (p.t as "standard") || "standard",
          fixed: p.f === 1,
        });
      }
      pe.keepWorld = true;
    }
    return true;
  } catch {
    return false;
  }
}

export function clearAutosave() {
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* ignore */
  }
}
