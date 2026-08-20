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

export function importLabScene(scene: LabScene) {
  if (!scene || scene.v !== 1) return false;
  try {
    if (scene.powder) getPowderEngine().deserializeState(scene.powder);
    const pe = getParticleEngine();
    const s = scene.particle;
    if (s) {
      pe.gravityX = s.gravityX;
      pe.gravityY = s.gravityY;
      pe.damping = s.damping;
      pe.elasticity = s.elasticity;
      pe.vortexForce = s.vortexForce;
      pe.maxSpeed = s.maxSpeed;
      pe.boundaryMode = (s.boundaryMode as typeof pe.boundaryMode) || "bounce";
      pe.collisionsEnabled = s.collisionsEnabled;
      pe.setMaxParticles(s.maxParticles || pe.maxParticles);
      pe.particles = [];
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
