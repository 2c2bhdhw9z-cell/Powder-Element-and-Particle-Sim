import type { ParticleObject } from "./types";
import { Swarm } from "./swarm";
import { getSwarmGPU } from "./swarm-gpu";
import { packSwarmSnap, unpackSwarmSnap, packXY, unpackXY } from "./live-pack";
import { parseColorToUint32, render, captureThumbnail } from "./particle/render";
import {
  spawnBurst,
  spawnGalaxy,
  spawnWaterfall,
  spawnShockwave,
  spawnBlackHole,
  spawnDoubleVortex,
  spawnRepulsor,
  spawnSolarFlare,
  spawnQuantumLattice,
  spawnDnaHelix,
  spawnCosmicFountain,
  spawnSynchrotron,
  spawnPour,
  spawnFlock,
  spawnNbody,
  spawnCloth,
  spawnRope,
  spawnBlob,
  placeWell,
} from "./particle/spawners";
import { stepParticles, stepFlock, stepSwarm, stepSprings, spawnEmitter } from "./particle/step";
import {
  getDiagnostics,
  purgeNaNParticles,
  clampVelocities,
  wrapOrTrimOutOfBounds,
  reallocateBuffers,
  zeroForces,
  resetCharges,
  injectCorruptVectorParticles,
  injectHyperVelocityExplosion,
  runAutoFix,
} from "./particle/diagnostics";
import type { ParticleCtx } from "./particle/context";

/**
 * Deep-enough copy of the particle list for undo/redo snapshots.
 * Shallow-copies each object (positions/velocities are numbers) and copies
 * the trail array — far cheaper than the old JSON.stringify round-trip.
 */
function snapshotParticles(particles: ParticleObject[]): ParticleObject[] {
  return particles.map((p) => ({ ...p, trail: p.trail.map((t) => ({ ...t })) }));
}

/**
 * Swarm + cloth/blob/rope particle field (1,000,000 cap).
 *
 * The engine owns state and orchestration; each concern lives in its own
 * module under `src/sim/particle/` operating on the `ParticleCtx`
 * structural interface (this class satisfies it):
 *
 *   spawners.ts      scene presets (galaxy, black hole, cloth, rope, …)
 *   step.ts          forces, integration, boundaries, flock, springs, swarm
 *   render.ts        pixel-buffer / vector renderers + color mapping
 *   diagnostics.ts   health inspection & repair actions
 */
export class ParticleEngine implements ParticleCtx {
  public particles: ParticleObject[] = [];
  public width: number;
  public height: number;

  public gravityX: number = 0;
  public gravityY: number = 0.3;
  public damping: number = 0.99; // Air friction
  public elasticity: number = 0.8; // Boundary bounce
  public electrostaticFactor: number = 100;
  public vortexForce: number = 0;
  public maxSpeed: number = 30;
  public boundaryMode: "bounce" | "wrap" | "void" = "bounce";
  public mouseMode:
    | "attract"
    | "repel"
    | "vortex"
    | "emitter"
    | "painter"
    | "gravity_well"
    | "freeze"
    | "hawk"
    | "hyper_drive" = "attract";
  public mouseRadius: number = 120;
  public mouseForceMultiplier: number = 1.0;
  public lastMouseX: number = 0;
  public lastMouseY: number = 0;
  public lastMouseActive: boolean = false;
  public colorMode: "element" | "velocity" | "charge" | "rainbow" | "density" | "lifespan" = "element";
  public particleSize: number = 2;
  public maxParticles: number = 1000000;
  public showTrails: boolean = true;
  public decaySpeed: number = 0;
  public collisionsEnabled = true;
  public fluidEnabled = false;
  public flockEnabled = false;
  public nbodyEnabled = false;
  public keepWorld = false;
  public swarm = new Swarm();
  public springs: { a: number; b: number; rest: number; k: number }[] = [];
  public onAfterStep: (() => void) | null = null;

  // Undo / Redo History (object snapshots)
  private undoStack: ParticleObject[][] = [];
  private redoStack: ParticleObject[][] = [];
  private maxUndoSteps: number = 20;

  public imgData: ImageData | null = null;
  public buf32: Uint32Array | null = null;

  constructor(width: number = 800, height: number = 600) {
    this.width = width;
    this.height = height;
  }

  public resize(newWidth: number, newHeight: number) {
    if (this.width === newWidth && this.height === newHeight) return;
    this.width = newWidth;
    this.height = newHeight;
    this.imgData = null;
    this.buf32 = null;
  }

  public clear() {
    this.pushUndo();
    this.particles = [];
    this.springs = [];
    this.flockEnabled = false;
    this.nbodyEnabled = false;
    this.fluidEnabled = false;
    this.swarm.clear();
  }

  public bodyCount() {
    return this.particles.length + this.swarm.n;
  }

  public setMaxParticles(limit: number) {
    const next = Math.max(1000, Math.min(1_000_000, Math.round(limit)));
    this.maxParticles = next;
    if (this.particles.length > next) this.particles = this.particles.slice(0, next);
    return next;
  }

  // --- Undo / Redo for Particle snapshots ---
  public serializeParticles(): string {
    try {
      return JSON.stringify(this.particles);
    } catch {
      return "[]";
    }
  }
  public deserializeParticles(json: string) {
    try {
      const arr = JSON.parse(json);
      if (Array.isArray(arr)) this.particles = arr;
    } catch {
      /* ignore */
    }
  }
  public pushUndo() {
    try {
      this.undoStack.push(snapshotParticles(this.particles));
      if (this.undoStack.length > this.maxUndoSteps) this.undoStack.shift();
      this.redoStack = [];
    } catch {
      /* never break a stroke over a snapshot failure */
    }
  }
  public canUndo(): boolean {
    return this.undoStack.length > 0;
  }
  public canRedo(): boolean {
    return this.redoStack.length > 0;
  }
  public undo(): boolean {
    if (this.undoStack.length === 0) return false;
    this.redoStack.push(snapshotParticles(this.particles));
    this.particles = this.undoStack.pop()!;
    return true;
  }
  public redo(): boolean {
    if (this.redoStack.length === 0) return false;
    this.undoStack.push(snapshotParticles(this.particles));
    this.particles = this.redoStack.pop()!;
    return true;
  }
  public clearHistory() {
    this.undoStack = [];
    this.redoStack = [];
  }
  public captureThumbnail(): string {
    return captureThumbnail(this);
  }

  public parseColorToUint32(colorStr: string): number {
    return parseColorToUint32(colorStr);
  }

  public addParticle(particle: Partial<ParticleObject>) {
    if (this.particles.length >= this.maxParticles) {
      this.particles.shift(); // Remove oldest
    }

    const color = particle.color || `hsl(${Math.random() * 360}, 85%, 65%)`;

    const newP: ParticleObject = {
      id: Math.random().toString(36).slice(2, 11),
      x: particle.x !== undefined ? particle.x : this.width / 2,
      y: particle.y !== undefined ? particle.y : this.height / 2,
      vx: particle.vx !== undefined ? particle.vx : (Math.random() - 0.5) * 4,
      vy: particle.vy !== undefined ? particle.vy : (Math.random() - 0.5) * 4,
      radius: particle.radius || Math.random() * 3 + 2,
      mass: particle.mass || 1,
      charge: particle.charge !== undefined ? particle.charge : Math.random() > 0.5 ? 1 : -1,
      color,
      colorUint32: this.parseColorToUint32(color),
      type: particle.type || "standard",
      fixed: particle.fixed || false,
      ignoreGravity: particle.ignoreGravity || false,
      originX: particle.originX,
      originY: particle.originY,
      trail: [],
      lifespan: particle.lifespan,
      maxLife: particle.maxLife || particle.lifespan,
    };

    this.particles.push(newP);
  }

  // Fast Batch Spawner for up to 1,000,000 particles
  public spawnBatch(count: number, color?: string) {
    this.pushUndo();
    if (count >= 4000) {
      const u32 = color ? this.parseColorToUint32(color) : 0;
      this.swarm.spawn(count, this.width, this.height, u32, this.maxParticles);
      if (typeof window !== "undefined") window.dispatchEvent(new Event("crucible:live-dump"));
      return;
    }
    const spaceLeft = this.maxParticles - this.particles.length;
    const toSpawn = Math.min(count, Math.max(0, spaceLeft));
    if (toSpawn <= 0) return;

    const cx = this.width / 2;
    const cy = this.height / 2;

    const blackHole = this.particles.find((p) => p.type === "blackhole");
    const bhX = blackHole ? blackHole.x : cx;
    const bhY = blackHole ? blackHole.y : cy;
    const G = blackHole ? (blackHole.mass || 80) * 200 : 0;

    for (let i = 0; i < toSpawn; i++) {
      const angle = Math.random() * Math.PI * 2;
      const dist = Math.random() * (Math.min(this.width, this.height) * 0.42) + 25;
      const px = Math.min(this.width - 2, Math.max(2, bhX + Math.cos(angle) * dist));
      const py = Math.min(this.height - 2, Math.max(2, bhY + Math.sin(angle) * dist));
      const particleColor = color || `hsl(${(i * 137) % 360}, 85%, 65%)`;

      let vx = (Math.random() - 0.5) * 6;
      let vy = (Math.random() - 0.5) * 6;
      let ignoreGrav = false;

      if (blackHole && G > 0) {
        const orbitalSpeed = Math.sqrt(G / Math.max(10, dist)) * (0.95 + Math.random() * 0.1);
        vx = -Math.sin(angle) * orbitalSpeed;
        vy = Math.cos(angle) * orbitalSpeed;
        ignoreGrav = true;
      }

      this.particles.push({
        id: (this.particles.length + i).toString(),
        x: px,
        y: py,
        vx,
        vy,
        radius: 1.5,
        mass: 1,
        charge: i % 2 === 0 ? 1 : -1,
        color: particleColor,
        colorUint32: this.parseColorToUint32(particleColor),
        type: "standard",
        ignoreGravity: ignoreGrav,
        originX: bhX,
        originY: bhY,
        trail: [],
      });
    }
  }

  // Spawner Presets
  public spawnBurst(count: number = 100, x?: number, y?: number) {
    spawnBurst(this, count, x, y);
  }

  public spawnGalaxy(count: number = 300) {
    spawnGalaxy(this, count);
  }

  public spawnWaterfall(count: number = 250) {
    spawnWaterfall(this, count);
  }

  public spawnShockwave(count: number = 300) {
    spawnShockwave(this, count);
  }

  public spawnBlackHole(count: number = 250) {
    spawnBlackHole(this, count);
  }

  public spawnDoubleVortex(count: number = 300) {
    spawnDoubleVortex(this, count);
  }

  public spawnRepulsor() {
    spawnRepulsor(this);
  }

  public spawnSolarFlare(count: number = 350) {
    spawnSolarFlare(this, count);
  }

  public spawnQuantumLattice(rows: number = 18, cols: number = 24) {
    spawnQuantumLattice(this, rows, cols);
  }

  public spawnDnaHelix(count: number = 280) {
    spawnDnaHelix(this, count);
  }

  public spawnCosmicFountain(count: number = 250) {
    spawnCosmicFountain(this, count);
  }

  public spawnSynchrotron(count: number = 300) {
    spawnSynchrotron(this, count);
  }

  public spawnPour(count = 400) {
    spawnPour(this, count);
  }

  public spawnFlock(count = 220) {
    spawnFlock(this, count);
  }

  public spawnNbody(count = 240) {
    spawnNbody(this, count);
  }

  public spawnCloth(cols = 16, rows = 12) {
    spawnCloth(this, cols, rows);
  }

  public spawnRope(n = 32) {
    spawnRope(this, n);
  }

  public spawnBlob(n = 24) {
    spawnBlob(this, n);
  }

  public placeWell(x: number, y: number) {
    placeWell(this, x, y);
  }

  public liveSnapshot(limit = 1600) {
    const bodies = this.particles.slice(0, 400).map((p) => ({
      x: p.x,
      y: p.y,
      vx: p.vx,
      vy: p.vy,
      r: p.radius,
      c: p.color,
      t: p.type,
      f: p.fixed ? 1 : 0,
    }));
    const n = this.swarm.n;
    const take = Math.min(n, limit);
    const step = n > take ? Math.ceil(n / take) : 1;
    const sx: number[] = [];
    const sy: number[] = [];
    const svx: number[] = [];
    const svy: number[] = [];
    for (let i = 0; i < n && sx.length < take; i += step) {
      const i2 = i * 2;
      sx.push(this.swarm.xy[i2]);
      sy.push(this.swarm.xy[i2 + 1]);
      svx.push(this.swarm.v[i2]);
      svy.push(this.swarm.v[i2 + 1]);
    }
    const pack = sx.length ? packSwarmSnap(sx, sy, svx, svy) : null;
    return {
      gx: this.gravityX,
      gy: this.gravityY,
      damp: this.damping,
      collide: this.collisionsEnabled,
      fluid: this.fluidEnabled,
      bodies,
      swarmN: n,
      bin: pack?.b,
      binN: pack?.n,
    };
  }

  public applyLive(s: {
    gx: number;
    gy: number;
    damp: number;
    collide: boolean;
    fluid?: boolean;
    bodies: Array<{ x: number; y: number; vx: number; vy: number; r: number; c: string; t?: string; f?: number }>;
    bin?: string;
    binN?: number;
    sx?: number[];
    sy?: number[];
    svx?: number[];
    svy?: number[];
  }) {
    if (!s) return;
    this.gravityX = s.gx;
    this.gravityY = s.gy;
    this.damping = s.damp;
    this.collisionsEnabled = s.collide;
    this.fluidEnabled = !!s.fluid;
    const bodies = s.bodies || [];
    if (this.particles.length === bodies.length && bodies.length) {
      for (let i = 0; i < bodies.length; i++) {
        const p = this.particles[i];
        const b = bodies[i];
        p.x += (b.x - p.x) * 0.62;
        p.y += (b.y - p.y) * 0.62;
        p.vx = b.vx;
        p.vy = b.vy;
      }
    } else {
      this.particles = [];
      for (const p of bodies) {
        this.addParticle({
          x: p.x,
          y: p.y,
          vx: p.vx,
          vy: p.vy,
          radius: p.r,
          color: p.c,
          type: (p.t as ParticleObject["type"]) || "standard",
          fixed: p.f === 1,
        });
      }
    }
    let sx = s.sx || [];
    let sy = s.sy || [];
    let svx = s.svx || [];
    let svy = s.svy || [];
    if (s.bin && s.binN) {
      const u = unpackSwarmSnap(s.binN, s.bin);
      sx = u.sx;
      sy = u.sy;
      svx = u.svx;
      svy = u.svy;
    }
    const m = sx.length;
    if (!m) return;
    if (this.swarm.n === m) {
      const xy = this.swarm.xy;
      const vel = this.swarm.v;
      for (let i = 0; i < m; i++) {
        const i2 = i * 2;
        xy[i2] += (sx[i] - xy[i2]) * 0.62;
        xy[i2 + 1] += (sy[i] - xy[i2 + 1]) * 0.62;
        vel[i2] = svx[i];
        vel[i2 + 1] = svy[i];
      }
      return;
    }
    this.swarm.fromSplit(
      { n: m, x: sx, y: sy, vx: svx, vy: svy, c: new Array(m).fill(0xffd4c8c8) },
      this.width,
      this.height,
      this.maxParticles
    );
  }

  public livePos(limit = 2400) {
    const n = this.swarm.n;
    const take = Math.min(n, limit);
    const step = n > take ? Math.ceil(n / take) : 1;
    const sx: number[] = [];
    const sy: number[] = [];
    for (let i = 0; i < n && sx.length < take; i += step) {
      sx.push(this.swarm.xy[i * 2]);
      sy.push(this.swarm.xy[i * 2 + 1]);
    }
    if (!sx.length) return null;
    return packXY(sx, sy);
  }

  public applyPos(n: number, b: string) {
    const { sx, sy } = unpackXY(n, b);
    const m = sx.length;
    if (!m) return;
    if (this.swarm.n === 0) {
      this.swarm.fromSplit(
        { n: m, x: sx, y: sy, vx: new Array(m).fill(0), vy: new Array(m).fill(0), c: new Array(m).fill(0xffd4c8c8) },
        this.width,
        this.height,
        this.maxParticles
      );
      return;
    }
    const take = Math.min(m, this.swarm.n);
    const xy = this.swarm.xy;
    for (let i = 0; i < take; i++) {
      const i2 = i * 2;
      xy[i2] += (sx[i] - xy[i2]) * 0.72;
      xy[i2 + 1] += (sy[i] - xy[i2 + 1]) * 0.72;
    }
    getSwarmGPU().dirty = true;
  }

  // Physics Integration Step
  public step(mouseX?: number, mouseY?: number, mouseActive?: boolean) {
    if (mouseX !== undefined) this.lastMouseX = mouseX;
    if (mouseY !== undefined) this.lastMouseY = mouseY;
    this.lastMouseActive = !!mouseActive;

    // Emitter Mouse Mode continuous spawn
    if (mouseActive && this.mouseMode === "emitter" && mouseX !== undefined && mouseY !== undefined) {
      spawnEmitter(this, mouseX, mouseY);
    }

    const total = this.particles.length;
    if (total === 0) {
      stepSwarm(this, mouseX, mouseY, mouseActive);
      this.onAfterStep?.();
      return;
    }

    stepParticles(this, mouseX, mouseY, mouseActive);

    stepSprings(this);
    if (this.flockEnabled) stepFlock(this);
    stepSwarm(this, mouseX, mouseY, mouseActive);
    this.onAfterStep?.();
  }

  // Canvas Renderer
  public render(ctx: CanvasRenderingContext2D) {
    render(this, ctx);
  }

  // --- Diagnostics & Health Inspection ---
  public getDiagnostics() {
    return getDiagnostics(this);
  }

  // --- Manual Fix Actions ---
  public purgeNaNParticles() {
    return purgeNaNParticles(this);
  }

  public clampVelocities() {
    return clampVelocities(this);
  }

  public wrapOrTrimOutOfBounds() {
    return wrapOrTrimOutOfBounds(this);
  }

  public reallocateBuffers() {
    return reallocateBuffers(this);
  }

  public zeroForces() {
    return zeroForces(this);
  }

  public resetCharges() {
    return resetCharges(this);
  }

  // --- Stress Test Injectors (for testing debug diagnostics) ---
  public injectCorruptVectorParticles() {
    return injectCorruptVectorParticles(this);
  }

  public injectHyperVelocityExplosion() {
    return injectHyperVelocityExplosion(this);
  }

  public runAutoFix() {
    return runAutoFix(this);
  }
}
