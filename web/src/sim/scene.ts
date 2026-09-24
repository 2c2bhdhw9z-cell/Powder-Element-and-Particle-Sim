import { getParticleEngine, getPowderEngine } from "./engines";

export type LabScene = {
  v: 1;
  savedAt: string;
  powder: string;
  particle: {
    width: number;
    height: number;
    gravityX: number;
    gravityY: number;
    damping: number;
    elasticity: number;
    vortexForce: number;
    maxSpeed: number;
    boundaryMode: string;
    collisionsEnabled: boolean;
    maxParticles: number;
    swarm?: { n: number; x: number[]; y: number[]; vx: number[]; vy: number[]; c: number[] };
    particles: Array<{
      x: number;
      y: number;
      vx: number;
      vy: number;
      r: number;
      c: string;
      t?: string;
      m?: number;
      g?: number;
    }>;
  };
};

export function exportLabScene(): LabScene {
  const pe = getParticleEngine();
  const list = pe.particles.slice(0, 12000);
  const swarm = pe.swarm.n > 0 ? pe.swarm.toSplit(24000) : undefined;
  return {
    v: 1,
    savedAt: new Date().toISOString(),
    powder: getPowderEngine().serializeState(),
    particle: {
      width: pe.width,
      height: pe.height,
      gravityX: pe.gravityX,
      gravityY: pe.gravityY,
      damping: pe.damping,
      elasticity: pe.elasticity,
      vortexForce: pe.vortexForce,
      maxSpeed: pe.maxSpeed,
      boundaryMode: pe.boundaryMode,
      collisionsEnabled: pe.collisionsEnabled,
      maxParticles: pe.maxParticles,
      swarm,
      particles: list.map((p) => ({
        x: p.x,
        y: p.y,
        vx: p.vx,
        vy: p.vy,
        r: p.radius,
        c: p.color,
        t: p.type !== "standard" ? p.type : undefined,
        m: p.mass !== 1 ? p.mass : undefined,
        g: p.ignoreGravity ? 1 : undefined,
      })),
    },
  };
}

/**
 * A number from a file, or the existing value if the file's is unusable.
 *
 * Scene files are user data and may have been hand-edited, truncated, or written by a
 * different build. These settings used to be assigned straight through, so a single
 * `null` or `NaN` for `damping` poisoned every particle's velocity on the next step —
 * and because it spread through the forces, the whole field went to not-a-number in
 * one frame with nothing pointing at the cause.
 */
function finite(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

const BOUNDARY_MODES = ["bounce", "wrap", "void"] as const;

export function importLabScene(scene: LabScene) {
  if (!scene || scene.v !== 1) return false;
  try {
    if (scene.powder) getPowderEngine().deserializeState(scene.powder);
    const pe = getParticleEngine();
    const s = scene.particle;
    if (s) {
      // The canvas size is saved, and used to be ignored — so a scene captured on a
      // large display dropped most of its particles outside a smaller field, where
      // they sat against the walls or were deleted outright.
      pe.resize(finite(s.width, pe.width), finite(s.height, pe.height));
      pe.gravityX = finite(s.gravityX, pe.gravityX);
      pe.gravityY = finite(s.gravityY, pe.gravityY);
      pe.damping = finite(s.damping, pe.damping);
      pe.elasticity = finite(s.elasticity, pe.elasticity);
      pe.vortexForce = finite(s.vortexForce, pe.vortexForce);
      pe.maxSpeed = finite(s.maxSpeed, pe.maxSpeed);
      pe.boundaryMode = BOUNDARY_MODES.includes(s.boundaryMode as (typeof BOUNDARY_MODES)[number])
        ? (s.boundaryMode as typeof pe.boundaryMode)
        : "bounce";
      pe.collisionsEnabled = !!s.collisionsEnabled;
      pe.setMaxParticles(finite(s.maxParticles, pe.maxParticles));
      // Through replaceParticles, which also drops the springs. Assigning the array
      // directly left every spring from the previous scene joining whichever two
      // particles now sat at its indices, with a rest length measured for a different
      // pair — a structure that pumps energy in on every frame and cannot be detected
      // by the spring step, which only checks for indices out of range.
      pe.replaceParticles([]);
      pe.swarm.clear();
      if (s.swarm && s.swarm.n) {
        pe.swarm.fromSplit(s.swarm, pe.width, pe.height, pe.maxParticles);
      }
      for (const p of s.particles || []) {
        pe.addParticle({
          x: p.x,
          y: p.y,
          vx: p.vx,
          vy: p.vy,
          radius: p.r,
          color: p.c,
          type: (p.t as "standard") || "standard",
          mass: p.m,
          ignoreGravity: p.g === 1,
          fixed: p.t === "blackhole" || p.t === "repulsor",
        });
      }
    }
    return true;
  } catch {
    return false;
  }
}

export function downloadLabScene() {
  const blob = new Blob([JSON.stringify(exportLabScene())], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `crucible-scene-${Date.now()}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
}

export function openLabSceneFile(): Promise<boolean> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "application/json";
    input.onchange = async () => {
      const file = input.files?.[0];
      if (!file) {
        resolve(false);
        return;
      }
      try {
        const text = await file.text();
        resolve(importLabScene(JSON.parse(text)));
      } catch {
        resolve(false);
      }
    };
    input.click();
  });
}
