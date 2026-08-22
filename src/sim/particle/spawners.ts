import type { ParticleCtx } from "./context";

/**
 * Spawner presets. Each resets the world (via e.clear()) and seeds a new
 * scene. Undo is recorded by clear() / spawnBatch() as in the original.
 */

export function spawnBurst(e: ParticleCtx, count: number = 100, x?: number, y?: number) {
  e.pushUndo();
  const cx = x !== undefined ? x : e.width / 2;
  const cy = y !== undefined ? y : e.height / 2;

  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = Math.random() * 8 + 2;
    e.addParticle({
      x: cx,
      y: cy,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      radius: Math.random() * 3 + 2,
      charge: i % 2 === 0 ? 1 : -1,
    });
  }
}

export function spawnGalaxy(e: ParticleCtx, count: number = 300) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;
  e.vortexForce = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;
  const bhMass = 80;
  const G = bhMass * 200; // 16000

  // Add Central Black Hole (anchored in space)
  e.addParticle({
    x: cx,
    y: cy,
    vx: 0,
    vy: 0,
    radius: 14,
    mass: bhMass,
    color: "#f43f5e",
    type: "blackhole",
    fixed: true,
    ignoreGravity: true,
  });

  for (let i = 0; i < count; i++) {
    const dist = Math.random() * (Math.min(e.width, e.height) * 0.42) + 30;
    const angle = Math.random() * Math.PI * 2;
    const orbitalSpeed = Math.sqrt(G / dist) * (0.96 + Math.random() * 0.08);

    e.addParticle({
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      vx: -Math.sin(angle) * orbitalSpeed,
      vy: Math.cos(angle) * orbitalSpeed,
      radius: Math.random() * 2 + 1,
      color: `hsl(${(dist * 2.8) % 360}, 95%, 70%)`,
      ignoreGravity: true,
      originX: cx,
      originY: cy,
    });
  }
}

export function spawnWaterfall(e: ParticleCtx, count: number = 250) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0.4;

  const startX = e.width * 0.3;
  const widthRange = e.width * 0.4;

  for (let i = 0; i < count; i++) {
    const wx = startX + Math.random() * widthRange;
    const wy = Math.random() * (e.height * 0.9) + 10;
    e.addParticle({
      x: wx,
      y: wy,
      vx: (Math.random() - 0.5) * 1.5,
      vy: Math.random() * 4 + 2,
      color: "#38bdf8",
      radius: Math.random() * 2.5 + 2,
      originX: startX,
      originY: 20,
    });
  }
}

export function spawnShockwave(e: ParticleCtx, count: number = 300) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;
  for (let i = 0; i < count; i++) {
    const angle = (i / count) * Math.PI * 2;
    const speed = 7 + Math.random() * 3;
    e.addParticle({
      x: cx + Math.cos(angle) * 12,
      y: cy + Math.sin(angle) * 12,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      color: `hsl(${((i / count) * 360) % 360}, 100%, 65%)`,
      radius: 3,
      ignoreGravity: true,
    });
  }
}

export function spawnBlackHole(e: ParticleCtx, count: number = 250) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;
  const bhMass = 100;
  const G = bhMass * 200; // 20000

  e.addParticle({
    x: cx,
    y: cy,
    vx: 0,
    vy: 0,
    radius: 16,
    mass: bhMass,
    color: "#f43f5e",
    type: "blackhole",
    fixed: true,
    ignoreGravity: true,
  });

  for (let i = 0; i < count; i++) {
    const dist = Math.random() * (Math.min(e.width, e.height) * 0.4) + 35;
    const angle = Math.random() * Math.PI * 2;
    const orbitalSpeed = Math.sqrt(G / dist) * (0.95 + Math.random() * 0.1);

    e.addParticle({
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      vx: -Math.sin(angle) * orbitalSpeed,
      vy: Math.cos(angle) * orbitalSpeed,
      radius: Math.random() * 2.5 + 1,
      color: `hsl(${(30 + dist * 2) % 360}, 100%, 65%)`,
      ignoreGravity: true,
      originX: cx,
      originY: cy,
    });
  }
}

export function spawnDoubleVortex(e: ParticleCtx, count: number = 300) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const c1x = e.width * 0.35;
  const c2x = e.width * 0.65;
  const cy = e.height * 0.5;
  const bhMass = 50;
  const G = bhMass * 200; // 10000

  e.addParticle({ x: c1x, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: "#3b82f6", type: "blackhole", fixed: true, ignoreGravity: true });
  e.addParticle({ x: c2x, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: "#f97316", type: "blackhole", fixed: true, ignoreGravity: true });

  for (let i = 0; i < count; i++) {
    const isLeft = i % 2 === 0;
    const center = isLeft ? { x: c1x, y: cy, dir: 1, hue: 200 } : { x: c2x, y: cy, dir: -1, hue: 30 };
    const dist = Math.random() * 130 + 25;
    const angle = Math.random() * Math.PI * 2;
    const orbitalSpeed = Math.sqrt(G / dist) * (0.92 + Math.random() * 0.16);

    e.addParticle({
      x: center.x + Math.cos(angle) * dist,
      y: center.y + Math.sin(angle) * dist,
      vx: -Math.sin(angle) * orbitalSpeed * center.dir,
      vy: Math.cos(angle) * orbitalSpeed * center.dir,
      radius: 2.5,
      color: `hsl(${center.hue + Math.random() * 30}, 95%, 65%)`,
      ignoreGravity: true,
      originX: center.x,
      originY: center.y,
    });
  }
}

export function spawnRepulsor(e: ParticleCtx) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;

  e.addParticle({
    x: cx,
    y: cy,
    vx: 0,
    vy: 0,
    radius: 14,
    mass: 60,
    color: "#a855f7",
    type: "repulsor",
    fixed: true,
    ignoreGravity: true,
  });

  for (let i = 0; i < 200; i++) {
    const dist = Math.random() * 160 + 60;
    const angle = Math.random() * Math.PI * 2;
    e.addParticle({
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      vx: (Math.random() - 0.5) * 2,
      vy: (Math.random() - 0.5) * 2,
      radius: 2.5,
      color: "#10b981",
      ignoreGravity: true,
      originX: cx,
      originY: cy,
    });
  }
}

export function spawnSolarFlare(e: ParticleCtx, count: number = 350) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;

  // Sun Core
  e.addParticle({
    x: cx,
    y: cy,
    vx: 0,
    vy: 0,
    radius: 18,
    mass: 50,
    color: "#f97316",
    type: "glow",
    fixed: true,
    ignoreGravity: true,
  });

  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = 2 + Math.random() * 8;
    const hue = 15 + Math.random() * 45; // Flame heat orange/red/gold
    const maxLife = 150 + Math.floor(Math.random() * 200);

    e.addParticle({
      x: cx + Math.cos(angle) * 20,
      y: cy + Math.sin(angle) * 20,
      vx: Math.cos(angle) * speed + (Math.random() - 0.5),
      vy: Math.sin(angle) * speed + (Math.random() - 0.5),
      radius: Math.random() * 3 + 1.5,
      color: `hsl(${hue}, 100%, 60%)`,
      ignoreGravity: true,
      originX: cx,
      originY: cy,
      lifespan: Math.floor(Math.random() * maxLife),
      maxLife,
    });
  }
}

export function spawnQuantumLattice(e: ParticleCtx, rows: number = 18, cols: number = 24) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const startX = e.width * 0.2;
  const startY = e.height * 0.2;
  const stepX = (e.width * 0.6) / cols;
  const stepY = (e.height * 0.6) / rows;

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const isPos = (r + c) % 2 === 0;
      const ox = startX + c * stepX;
      const oy = startY + r * stepY;
      e.addParticle({
        x: ox,
        y: oy,
        vx: (Math.random() - 0.5) * 0.2,
        vy: (Math.random() - 0.5) * 0.2,
        radius: 3,
        mass: 2,
        charge: isPos ? 1 : -1,
        color: isPos ? "#38bdf8" : "#f43f5e",
        ignoreGravity: true,
        originX: ox,
        originY: oy,
      });
    }
  }
}

export function spawnDnaHelix(e: ParticleCtx, count: number = 280) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const startX = e.width * 0.1;
  const endX = e.width * 0.9;
  const cy = e.height / 2;
  const wavelength = 120;

  for (let i = 0; i < count; i++) {
    const progress = i / count;
    const px = startX + progress * (endX - startX);
    const angle = (px / wavelength) * Math.PI * 2;

    // Strand A
    e.addParticle({
      x: px,
      y: cy + Math.sin(angle) * 50,
      vx: 1.2,
      vy: 0,
      radius: 2.5,
      charge: 1,
      color: "#06b6d4",
      ignoreGravity: true,
      originX: startX,
      originY: cy,
    });

    // Strand B
    e.addParticle({
      x: px,
      y: cy - Math.sin(angle) * 50,
      vx: 1.2,
      vy: 0,
      radius: 2.5,
      charge: -1,
      color: "#a855f7",
      ignoreGravity: true,
      originX: startX,
      originY: cy,
    });
  }
}

export function spawnCosmicFountain(e: ParticleCtx, count: number = 250) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0.3;

  const cx = e.width / 2;
  const bottomY = e.height - 20;

  for (let i = 0; i < count; i++) {
    const angle = -Math.PI / 2 + (Math.random() - 0.5) * 0.7;
    const speed = Math.random() * 9 + 5;
    const maxLife = 120 + Math.floor(Math.random() * 150);
    e.addParticle({
      x: cx + (Math.random() - 0.5) * 30,
      y: bottomY - Math.random() * (e.height * 0.6),
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      radius: Math.random() * 2.5 + 1.5,
      color: `hsl(${(i * 12) % 360}, 100%, 65%)`,
      originX: cx,
      originY: bottomY,
      lifespan: Math.floor(Math.random() * maxLife),
      maxLife,
    });
  }
}

export function spawnSynchrotron(e: ParticleCtx, count: number = 300) {
  e.clear();
  e.gravityX = 0;
  e.gravityY = 0;

  const cx = e.width / 2;
  const cy = e.height / 2;
  const bhMass = 60;
  const G = bhMass * 200; // 12000

  e.addParticle({ x: cx - 130, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: "#ec4899", type: "blackhole", fixed: true, ignoreGravity: true });
  e.addParticle({ x: cx + 130, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: "#3b82f6", type: "blackhole", fixed: true, ignoreGravity: true });

  for (let i = 0; i < count; i++) {
    const angle = Math.random() * Math.PI * 2;
    const dist = Math.random() * 180 + 30;
    const orbitalSpeed = Math.sqrt(G / dist) * (0.95 + Math.random() * 0.1);

    e.addParticle({
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      vx: -Math.sin(angle) * orbitalSpeed,
      vy: Math.cos(angle) * orbitalSpeed,
      radius: 2,
      color: `hsl(${(i * 7) % 360}, 95%, 70%)`,
      ignoreGravity: true,
      originX: cx,
      originY: cy,
    });
  }
}

export function spawnPour(e: ParticleCtx, count = 400) {
  e.clear();
  e.gravityY = 0.38;
  e.fluidEnabled = true;
  e.collisionsEnabled = true;
  const x = e.width * 0.5;
  for (let i = 0; i < count; i++) {
    e.addParticle({
      x: x + (Math.random() - 0.5) * 40,
      y: 20 + Math.random() * 40,
      vx: (Math.random() - 0.5) * 0.4,
      vy: 0.4 + Math.random(),
      radius: 2.4,
      color: `hsl(${200 + Math.random() * 30}, 80%, 65%)`,
    });
  }
}

export function spawnFlock(e: ParticleCtx, count = 220) {
  e.clear();
  e.gravityY = 0;
  e.flockEnabled = true;
  for (let i = 0; i < count; i++) {
    e.addParticle({
      x: Math.random() * e.width,
      y: Math.random() * e.height,
      vx: (Math.random() - 0.5) * 3,
      vy: (Math.random() - 0.5) * 3,
      radius: 2.2,
      color: `hsl(${140 + Math.random() * 50}, 80%, 62%)`,
    });
  }
}

export function spawnNbody(e: ParticleCtx, count = 240) {
  e.clear();
  e.gravityY = 0;
  e.nbodyEnabled = true;
  const cx = e.width / 2;
  const cy = e.height / 2;
  for (let i = 0; i < count; i++) {
    const a = Math.random() * Math.PI * 2;
    const d = 30 + Math.random() * Math.min(e.width, e.height) * 0.3;
    e.addParticle({
      x: cx + Math.cos(a) * d,
      y: cy + Math.sin(a) * d,
      vx: -Math.sin(a) * 1.4,
      vy: Math.cos(a) * 1.4,
      radius: 2,
      mass: 1,
      color: `hsl(${i * 9 % 360}, 90%, 65%)`,
    });
  }
}

export function spawnCloth(e: ParticleCtx, cols = 16, rows = 12) {
  e.clear();
  e.gravityY = 0.35;
  e.springs = [];
  const gap = Math.min(18, Math.floor(e.width / (cols + 2)));
  const ox = (e.width - cols * gap) / 2;
  const oy = 36;
  const start = e.particles.length;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      e.addParticle({
        x: ox + x * gap,
        y: oy + y * gap,
        vx: 0,
        vy: 0,
        radius: 2.4,
        color: `hsl(${200 + x * 4}, 70%, 70%)`,
        fixed: y === 0 && (x === 0 || x === cols - 1 || x % 4 === 0),
      });
    }
  }
  const idx = (x: number, y: number) => start + y * cols + x;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      if (x + 1 < cols) e.springs.push({ a: idx(x, y), b: idx(x + 1, y), rest: gap, k: 0.18 });
      if (y + 1 < rows) e.springs.push({ a: idx(x, y), b: idx(x, y + 1), rest: gap, k: 0.18 });
    }
  }
}

export function spawnRope(e: ParticleCtx, n = 32) {
  e.clear();
  e.gravityY = 0.4;
  e.springs = [];
  const cx = e.width / 2;
  const gap = 10;
  const start = e.particles.length;
  for (let i = 0; i < n; i++) {
    e.addParticle({
      x: cx,
      y: 24 + i * gap,
      vx: 0,
      vy: 0,
      radius: 2.6,
      color: "#e7e5e4",
      fixed: i === 0,
    });
  }
  for (let i = 0; i < n - 1; i++) e.springs.push({ a: start + i, b: start + i + 1, rest: gap, k: 0.28 });
}

export function spawnBlob(e: ParticleCtx, n = 24) {
  e.clear();
  e.gravityY = 0.22;
  e.springs = [];
  const cx = e.width / 2;
  const cy = e.height * 0.4;
  const r = 42;
  const start = e.particles.length;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    e.addParticle({
      x: cx + Math.cos(a) * r,
      y: cy + Math.sin(a) * r,
      vx: 0,
      vy: 0,
      radius: 3,
      color: `hsl(${320 + i * 3}, 80%, 68%)`,
    });
  }
  for (let i = 0; i < n; i++) {
    e.springs.push({ a: start + i, b: start + ((i + 1) % n), rest: (2 * Math.PI * r) / n, k: 0.22 });
    e.springs.push({ a: start + i, b: start + ((i + Math.floor(n / 2)) % n), rest: r * 2, k: 0.05 });
  }
}

/** Place a draggable gravity well (black hole). */
export function placeWell(e: ParticleCtx, x: number, y: number) {
  e.addParticle({
    x,
    y,
    vx: 0,
    vy: 0,
    radius: 14,
    mass: 90,
    color: "#fb7185",
    type: "blackhole",
    fixed: true,
    ignoreGravity: true,
  });
}
