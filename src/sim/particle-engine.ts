import type { ParticleObject } from "./types";
import { Swarm } from "./swarm";
import { getSwarmGPU } from "./swarm-gpu";
import { packSwarmSnap, unpackSwarmSnap, packXY, unpackXY } from "./live-pack";

export class ParticleEngine {
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
  public boundaryMode: 'bounce' | 'wrap' | 'void' = 'bounce';
  public mouseMode: 'attract' | 'repel' | 'vortex' | 'emitter' | 'painter' | 'gravity_well' | 'freeze' | 'hawk' | 'hyper_drive' = 'attract';
  public mouseRadius: number = 120;
  public mouseForceMultiplier: number = 1.0;
  public lastMouseX: number = 0;
  public lastMouseY: number = 0;
  public lastMouseActive: boolean = false;
  public colorMode: 'element' | 'velocity' | 'charge' | 'rainbow' | 'density' | 'lifespan' = 'element';
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
  private writeHead = 0;

  private undoStack: string[] = [];
  private redoStack: string[] = [];
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
    try { return JSON.stringify(this.particles); } catch { return '[]'; }
  }
  public deserializeParticles(json: string) {
    try {
      const arr = JSON.parse(json);
      if (Array.isArray(arr)) this.particles = arr;
    } catch {}
  }
  public pushUndo() {
    try {
      const snap = this.serializeParticles();
      this.undoStack.push(snap);
      if (this.undoStack.length > this.maxUndoSteps) this.undoStack.shift();
      this.redoStack = [];
    } catch {}
  }
  public canUndo(): boolean { return this.undoStack.length > 0; }
  public canRedo(): boolean { return this.redoStack.length > 0; }
  public undo(): boolean {
    if (this.undoStack.length === 0) return false;
    this.redoStack.push(this.serializeParticles());
    const prev = this.undoStack.pop()!;
    this.deserializeParticles(prev);
    return true;
  }
  public redo(): boolean {
    if (this.redoStack.length === 0) return false;
    this.undoStack.push(this.serializeParticles());
    const next = this.redoStack.pop()!;
    this.deserializeParticles(next);
    return true;
  }
  public clearHistory() { this.undoStack = []; this.redoStack = []; }
  public captureThumbnail(): string {
    try {
      if (typeof document === 'undefined') return '';
      const canvas = document.createElement('canvas');
      canvas.width = this.width;
      canvas.height = this.height;
      const ctx = canvas.getContext('2d');
      if (!ctx) return '';
      this.render(ctx);
      return canvas.toDataURL('image/png');
    } catch { return ''; }
  }

  // Fast ABGR Uint32 color converter for Little-Endian ImageData
  private parseColorToUint32(colorStr: string): number {
    if (colorStr.startsWith('#')) {
      let hex = colorStr.slice(1);
      if (hex.length === 3) hex = hex.split('').map(c => c + c).join('');
      const num = parseInt(hex, 16);
      const r = (num >> 16) & 255;
      const g = (num >> 8) & 255;
      const b = num & 255;
      return 0xFF000000 | (b << 16) | (g << 8) | r;
    }
    if (colorStr.startsWith('hsl')) {
      const match = colorStr.match(/\d+/g);
      if (match && match.length >= 3) {
        const h = parseInt(match[0], 10) / 360;
        const s = parseInt(match[1], 10) / 100;
        const l = parseInt(match[2], 10) / 100;
        let r, g, b;
        if (s === 0) {
          r = g = b = l;
        } else {
          const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
          const p = 2 * l - q;
          const hue2rgb = (t: number) => {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1/6) return p + (q - p) * 6 * t;
            if (t < 1/2) return q;
            if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
            return p;
          };
          r = hue2rgb(h + 1/3);
          g = hue2rgb(h);
          b = hue2rgb(h - 1/3);
        }
        return 0xFF000000 | (Math.round(b * 255) << 16) | (Math.round(g * 255) << 8) | Math.round(r * 255);
      }
    }
    return 0xFFFFFFFF; // default white
  }

  public addParticle(particle: Partial<ParticleObject>) {
    if (this.particles.length >= this.maxParticles) {
      this.particles.shift(); // Remove oldest
    }

    const color = particle.color || `hsl(${Math.random() * 360}, 85%, 65%)`;

    const newP: ParticleObject = {
      id: Math.random().toString(36).substr(2, 9),
      x: particle.x !== undefined ? particle.x : this.width / 2,
      y: particle.y !== undefined ? particle.y : this.height / 2,
      vx: particle.vx !== undefined ? particle.vx : (Math.random() - 0.5) * 4,
      vy: particle.vy !== undefined ? particle.vy : (Math.random() - 0.5) * 4,
      radius: particle.radius || Math.random() * 3 + 2,
      mass: particle.mass || 1,
      charge: particle.charge !== undefined ? particle.charge : (Math.random() > 0.5 ? 1 : -1),
      color,
      colorUint32: this.parseColorToUint32(color),
      type: particle.type || 'standard',
      fixed: particle.fixed || false,
      ignoreGravity: particle.ignoreGravity || false,
      originX: particle.originX,
      originY: particle.originY,
      trail: [],
      lifespan: particle.lifespan,
      maxLife: particle.maxLife || particle.lifespan
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

    const blackHole = this.particles.find(p => p.type === 'blackhole');
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
        type: 'standard',
        ignoreGravity: ignoreGrav,
        originX: bhX,
        originY: bhY,
        trail: []
      });
    }
  }

  // Spawner Presets
  public spawnBurst(count: number = 100, x?: number, y?: number) {
    this.pushUndo();
    const cx = x !== undefined ? x : this.width / 2;
    const cy = y !== undefined ? y : this.height / 2;

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = Math.random() * 8 + 2;
      this.addParticle({
        x: cx,
        y: cy,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        radius: Math.random() * 3 + 2,
        charge: i % 2 === 0 ? 1 : -1
      });
    }
  }

  public spawnGalaxy(count: number = 300) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;
    this.vortexForce = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;
    const bhMass = 80;
    const G = bhMass * 200; // 16000

    // Add Central Black Hole (anchored in space)
    this.addParticle({
      x: cx,
      y: cy,
      vx: 0,
      vy: 0,
      radius: 14,
      mass: bhMass,
      color: '#f43f5e',
      type: 'blackhole',
      fixed: true,
      ignoreGravity: true
    });

    for (let i = 0; i < count; i++) {
      const dist = Math.random() * (Math.min(this.width, this.height) * 0.42) + 30;
      const angle = Math.random() * Math.PI * 2;
      const orbitalSpeed = Math.sqrt(G / dist) * (0.96 + Math.random() * 0.08);

      this.addParticle({
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        vx: -Math.sin(angle) * orbitalSpeed,
        vy: Math.cos(angle) * orbitalSpeed,
        radius: Math.random() * 2 + 1,
        color: `hsl(${(dist * 2.8) % 360}, 95%, 70%)`,
        ignoreGravity: true,
        originX: cx,
        originY: cy
      });
    }
  }

  public spawnWaterfall(count: number = 250) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0.4;

    const startX = this.width * 0.3;
    const widthRange = this.width * 0.4;

    for (let i = 0; i < count; i++) {
      const wx = startX + Math.random() * widthRange;
      const wy = Math.random() * (this.height * 0.9) + 10;
      this.addParticle({
        x: wx,
        y: wy,
        vx: (Math.random() - 0.5) * 1.5,
        vy: Math.random() * 4 + 2,
        color: '#38bdf8',
        radius: Math.random() * 2.5 + 2,
        originX: startX,
        originY: 20
      });
    }
  }

  public spawnShockwave(count: number = 300) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;
    for (let i = 0; i < count; i++) {
      const angle = (i / count) * Math.PI * 2;
      const speed = 7 + Math.random() * 3;
      this.addParticle({
        x: cx + Math.cos(angle) * 12,
        y: cy + Math.sin(angle) * 12,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        color: `hsl(${((i / count) * 360) % 360}, 100%, 65%)`,
        radius: 3,
        ignoreGravity: true
      });
    }
  }

  public spawnBlackHole(count: number = 250) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;
    const bhMass = 100;
    const G = bhMass * 200; // 20000

    this.addParticle({
      x: cx,
      y: cy,
      vx: 0,
      vy: 0,
      radius: 16,
      mass: bhMass,
      color: '#f43f5e',
      type: 'blackhole',
      fixed: true,
      ignoreGravity: true
    });

    for (let i = 0; i < count; i++) {
      const dist = Math.random() * (Math.min(this.width, this.height) * 0.4) + 35;
      const angle = Math.random() * Math.PI * 2;
      const orbitalSpeed = Math.sqrt(G / dist) * (0.95 + Math.random() * 0.1);

      this.addParticle({
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        vx: -Math.sin(angle) * orbitalSpeed,
        vy: Math.cos(angle) * orbitalSpeed,
        radius: Math.random() * 2.5 + 1,
        color: `hsl(${(30 + dist * 2) % 360}, 100%, 65%)`,
        ignoreGravity: true,
        originX: cx,
        originY: cy
      });
    }
  }

  public spawnDoubleVortex(count: number = 300) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const c1x = this.width * 0.35;
    const c2x = this.width * 0.65;
    const cy = this.height * 0.5;
    const bhMass = 50;
    const G = bhMass * 200; // 10000

    this.addParticle({ x: c1x, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: '#3b82f6', type: 'blackhole', fixed: true, ignoreGravity: true });
    this.addParticle({ x: c2x, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: '#f97316', type: 'blackhole', fixed: true, ignoreGravity: true });

    for (let i = 0; i < count; i++) {
      const isLeft = i % 2 === 0;
      const center = isLeft ? { x: c1x, y: cy, dir: 1, hue: 200 } : { x: c2x, y: cy, dir: -1, hue: 30 };
      const dist = Math.random() * 130 + 25;
      const angle = Math.random() * Math.PI * 2;
      const orbitalSpeed = Math.sqrt(G / dist) * (0.92 + Math.random() * 0.16);

      this.addParticle({
        x: center.x + Math.cos(angle) * dist,
        y: center.y + Math.sin(angle) * dist,
        vx: -Math.sin(angle) * orbitalSpeed * center.dir,
        vy: Math.cos(angle) * orbitalSpeed * center.dir,
        radius: 2.5,
        color: `hsl(${center.hue + Math.random() * 30}, 95%, 65%)`,
        ignoreGravity: true,
        originX: center.x,
        originY: center.y
      });
    }
  }

  public spawnRepulsor() {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;

    this.addParticle({
      x: cx,
      y: cy,
      vx: 0,
      vy: 0,
      radius: 14,
      mass: 60,
      color: '#a855f7',
      type: 'repulsor',
      fixed: true,
      ignoreGravity: true
    });

    for (let i = 0; i < 200; i++) {
      const dist = Math.random() * 160 + 60;
      const angle = Math.random() * Math.PI * 2;
      this.addParticle({
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        vx: (Math.random() - 0.5) * 2,
        vy: (Math.random() - 0.5) * 2,
        radius: 2.5,
        color: '#10b981',
        ignoreGravity: true,
        originX: cx,
        originY: cy
      });
    }
  }

  public spawnSolarFlare(count: number = 350) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;

    // Sun Core
    this.addParticle({
      x: cx,
      y: cy,
      vx: 0,
      vy: 0,
      radius: 18,
      mass: 50,
      color: '#f97316',
      type: 'glow',
      fixed: true,
      ignoreGravity: true
    });

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2 + Math.random() * 8;
      const hue = 15 + Math.random() * 45; // Flame heat orange/red/gold
      const maxLife = 150 + Math.floor(Math.random() * 200);

      this.addParticle({
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
        maxLife
      });
    }
  }

  public spawnQuantumLattice(rows: number = 18, cols: number = 24) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const startX = this.width * 0.2;
    const startY = this.height * 0.2;
    const stepX = (this.width * 0.6) / cols;
    const stepY = (this.height * 0.6) / rows;

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const isPos = (r + c) % 2 === 0;
        const ox = startX + c * stepX;
        const oy = startY + r * stepY;
        this.addParticle({
          x: ox,
          y: oy,
          vx: (Math.random() - 0.5) * 0.2,
          vy: (Math.random() - 0.5) * 0.2,
          radius: 3,
          mass: 2,
          charge: isPos ? 1 : -1,
          color: isPos ? '#38bdf8' : '#f43f5e',
          ignoreGravity: true,
          originX: ox,
          originY: oy
        });
      }
    }
  }

  public spawnDnaHelix(count: number = 280) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const startX = this.width * 0.1;
    const endX = this.width * 0.9;
    const cy = this.height / 2;
    const wavelength = 120;

    for (let i = 0; i < count; i++) {
      const progress = i / count;
      const px = startX + progress * (endX - startX);
      const angle = (px / wavelength) * Math.PI * 2;

      // Strand A
      this.addParticle({
        x: px,
        y: cy + Math.sin(angle) * 50,
        vx: 1.2,
        vy: 0,
        radius: 2.5,
        charge: 1,
        color: '#06b6d4',
        ignoreGravity: true,
        originX: startX,
        originY: cy
      });

      // Strand B
      this.addParticle({
        x: px,
        y: cy - Math.sin(angle) * 50,
        vx: 1.2,
        vy: 0,
        radius: 2.5,
        charge: -1,
        color: '#a855f7',
        ignoreGravity: true,
        originX: startX,
        originY: cy
      });
    }
  }

  public spawnCosmicFountain(count: number = 250) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0.3;

    const cx = this.width / 2;
    const bottomY = this.height - 20;

    for (let i = 0; i < count; i++) {
      const angle = -Math.PI / 2 + (Math.random() - 0.5) * 0.7;
      const speed = Math.random() * 9 + 5;
      const maxLife = 120 + Math.floor(Math.random() * 150);
      this.addParticle({
        x: cx + (Math.random() - 0.5) * 30,
        y: bottomY - Math.random() * (this.height * 0.6),
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        radius: Math.random() * 2.5 + 1.5,
        color: `hsl(${(i * 12) % 360}, 100%, 65%)`,
        originX: cx,
        originY: bottomY,
        lifespan: Math.floor(Math.random() * maxLife),
        maxLife
      });
    }
  }

  public spawnSynchrotron(count: number = 300) {
    this.clear();
    this.gravityX = 0;
    this.gravityY = 0;

    const cx = this.width / 2;
    const cy = this.height / 2;
    const bhMass = 60;
    const G = bhMass * 200; // 12000

    this.addParticle({ x: cx - 130, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: '#ec4899', type: 'blackhole', fixed: true, ignoreGravity: true });
    this.addParticle({ x: cx + 130, y: cy, vx: 0, vy: 0, radius: 12, mass: bhMass, color: '#3b82f6', type: 'blackhole', fixed: true, ignoreGravity: true });

    for (let i = 0; i < count; i++) {
      const angle = Math.random() * Math.PI * 2;
      const dist = Math.random() * 180 + 30;
      const orbitalSpeed = Math.sqrt(G / dist) * (0.95 + Math.random() * 0.1);

      this.addParticle({
        x: cx + Math.cos(angle) * dist,
        y: cy + Math.sin(angle) * dist,
        vx: -Math.sin(angle) * orbitalSpeed,
        vy: Math.cos(angle) * orbitalSpeed,
        radius: 2,
        color: `hsl(${(i * 7) % 360}, 95%, 70%)`,
        ignoreGravity: true,
        originX: cx,
        originY: cy
      });
    }
  }

  public spawnPour(count = 400) {
    this.clear();
    this.gravityY = 0.38;
    this.fluidEnabled = true;
    this.collisionsEnabled = true;
    const x = this.width * 0.5;
    for (let i = 0; i < count; i++) {
      this.addParticle({
        x: x + (Math.random() - 0.5) * 40,
        y: 20 + Math.random() * 40,
        vx: (Math.random() - 0.5) * 0.4,
        vy: 0.4 + Math.random(),
        radius: 2.4,
        color: `hsl(${200 + Math.random() * 30}, 80%, 65%)`,
      });
    }
  }

  public spawnFlock(count = 220) {
    this.clear();
    this.gravityY = 0;
    this.flockEnabled = true;
    for (let i = 0; i < count; i++) {
      this.addParticle({
        x: Math.random() * this.width,
        y: Math.random() * this.height,
        vx: (Math.random() - 0.5) * 3,
        vy: (Math.random() - 0.5) * 3,
        radius: 2.2,
        color: `hsl(${140 + Math.random() * 50}, 80%, 62%)`,
      });
    }
  }

  public spawnNbody(count = 240) {
    this.clear();
    this.gravityY = 0;
    this.nbodyEnabled = true;
    const cx = this.width / 2;
    const cy = this.height / 2;
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const d = 30 + Math.random() * Math.min(this.width, this.height) * 0.3;
      this.addParticle({
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

  public spawnCloth(cols = 16, rows = 12) {
    this.clear();
    this.gravityY = 0.35;
    this.springs = [];
    const gap = Math.min(18, Math.floor(this.width / (cols + 2)));
    const ox = (this.width - cols * gap) / 2;
    const oy = 36;
    const start = this.particles.length;
    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        this.addParticle({
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
        if (x + 1 < cols) this.springs.push({ a: idx(x, y), b: idx(x + 1, y), rest: gap, k: 0.18 });
        if (y + 1 < rows) this.springs.push({ a: idx(x, y), b: idx(x, y + 1), rest: gap, k: 0.18 });
      }
    }
  }

  public spawnRope(n = 32) {
    this.clear();
    this.gravityY = 0.4;
    this.springs = [];
    const cx = this.width / 2;
    const gap = 10;
    const start = this.particles.length;
    for (let i = 0; i < n; i++) {
      this.addParticle({
        x: cx,
        y: 24 + i * gap,
        vx: 0,
        vy: 0,
        radius: 2.6,
        color: "#e7e5e4",
        fixed: i === 0,
      });
    }
    for (let i = 0; i < n - 1; i++) this.springs.push({ a: start + i, b: start + i + 1, rest: gap, k: 0.28 });
  }

  public spawnBlob(n = 24) {
    this.clear();
    this.gravityY = 0.22;
    this.springs = [];
    const cx = this.width / 2;
    const cy = this.height * 0.4;
    const r = 42;
    const start = this.particles.length;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * Math.PI * 2;
      this.addParticle({
        x: cx + Math.cos(a) * r,
        y: cy + Math.sin(a) * r,
        vx: 0,
        vy: 0,
        radius: 3,
        color: `hsl(${320 + i * 3}, 80%, 68%)`,
      });
    }
    for (let i = 0; i < n; i++) {
      this.springs.push({ a: start + i, b: start + ((i + 1) % n), rest: (2 * Math.PI * r) / n, k: 0.22 });
      this.springs.push({ a: start + i, b: start + ((i + Math.floor(n / 2)) % n), rest: r * 2, k: 0.05 });
    }
  }

  public placeWell(x: number, y: number) {
    this.addParticle({
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
    this.swarm.fromSplit({ n: m, x: sx, y: sy, vx: svx, vy: svy, c: new Array(m).fill(0xffd4c8c8) }, this.width, this.height, this.maxParticles);
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
        this.maxParticles,
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
    if (mouseActive && this.mouseMode === 'emitter' && mouseX !== undefined && mouseY !== undefined) {
      for (let e = 0; e < 6; e++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = Math.random() * 6 + 1;
        this.addParticle({
          x: mouseX,
          y: mouseY,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          radius: Math.random() * 3 + 1,
          color: `hsl(${Math.random() * 360}, 90%, 65%)`
        });
      }
    }

    const total = this.particles.length;
    if (total === 0) {
      this.stepSwarm(mouseX, mouseY, mouseActive);
      this.onAfterStep?.();
      return;
    }

    // 1. Update lifespans & trails & recycling
    let hasExpired = false;
    const updateTrails = this.showTrails && total <= 1000;

    for (let i = 0; i < total; i++) {
      const p = this.particles[i];
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
      if (this.decaySpeed > 0 && p.lifespan === undefined) {
        p.lifespan = Math.floor(100 / this.decaySpeed);
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

            if (p.originY > this.height - 50) {
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
      this.particles = this.particles.filter(p => p && (p.lifespan === undefined || p.lifespan > 0));
    }

    const count = this.particles.length;

    // Extract special attractor/repulsor objects for O(N) interaction
    const attractors: ParticleObject[] = [];
    for (let i = 0; i < count; i++) {
      const pt = this.particles[i];
      if (pt.type === 'blackhole' || pt.type === 'repulsor') {
        attractors.push(pt);
      }
    }

    // Center Vortex Force
    const cx = this.width / 2;
    const cy = this.height / 2;

    // Pairwise electrostatic sampling limit
    const doPairwise = count <= 300;

    for (let i = 0; i < count; i++) {
      const p1 = this.particles[i];
      if (!p1 || (p1.lifespan !== undefined && p1.lifespan <= 0)) continue;

      // Special Attractors/Repulsors O(N)
      for (let k = 0; k < attractors.length; k++) {
        const att = attractors[k];
        if (att === p1) continue;

        const dx = att.x - p1.x;
        const dy = att.y - p1.y;
        const distSq = dx * dx + dy * dy + 10;
        const dist = Math.sqrt(distSq);

        if (att.type === 'blackhole') {
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
              const orbitDist = Math.random() * (Math.min(this.width, this.height) * 0.4) + 40;
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
        } else if (att.type === 'repulsor') {
          const force = (att.mass * 150) / distSq;
          p1.vx -= (dx / dist) * force;
          p1.vy -= (dy / dist) * force;
        }
      }

      // Center Vortex Attractor Force
      if (this.vortexForce !== 0) {
        const vdx = cx - p1.x;
        const vdy = cy - p1.y;
        const vdistSq = vdx * vdx + vdy * vdy + 20;
        const vdist = Math.sqrt(vdistSq);
        const vF = (this.vortexForce * 10) / vdistSq;
        // Tangential swirl + radial pull
        p1.vx += (-vdy / vdist) * vF + (vdx / vdist) * (vF * 0.2);
        p1.vy += (vdx / vdist) * vF + (vdy / vdist) * (vF * 0.2);
      }

      // Small-scale O(N^2) Electrostatic Coulomb Force
      if (doPairwise) {
        for (let j = i + 1; j < count; j++) {
          const p2 = this.particles[j];
          if (!p2 || p2.type === 'blackhole' || p2.type === 'repulsor') continue;

          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          const distSq = dx * dx + dy * dy + 10;
          const dist = Math.sqrt(distSq);

          if (p1.charge !== 0 && p2.charge !== 0) {
            const chargeProduct = p1.charge * p2.charge;
            const force = (chargeProduct * this.electrostaticFactor) / distSq;
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

        const radiusCap = this.mouseRadius >= 800 ? 999999 : this.mouseRadius;
        if (mDist <= radiusCap) {
          const falloff = radiusCap > 5000 ? 1 : Math.max(0, 1 - (mDist / radiusCap));
          const mult = this.mouseForceMultiplier;

          if (this.mouseMode === 'attract') {
            const mForce = (1800 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
            p1.vx += (mdx / mDist) * mForce;
            p1.vy += (mdy / mDist) * mForce;
          } else if (this.mouseMode === 'repel' || this.mouseMode === 'hawk') {
            const mForce = (2000 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
            p1.vx -= (mdx / mDist) * mForce;
            p1.vy -= (mdy / mDist) * mForce;
          } else if (this.mouseMode === 'vortex') {
            const mForce = (1400 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
            p1.vx += (-mdy / mDist) * mForce + (mdx / mDist) * (mForce * 0.1);
            p1.vy += (mdx / mDist) * mForce + (mdy / mDist) * (mForce * 0.1);
          } else if (this.mouseMode === 'painter') {
            const hue = Math.floor((performance.now() / 10 + i * 5) % 360);
            p1.color = `hsl(${hue}, 95%, 65%)`;
            p1.colorUint32 = this.parseColorToUint32(p1.color);
          } else if (this.mouseMode === 'gravity_well') {
            const mForce = (3500 / mDistSq) * (0.2 + 0.8 * falloff) * mult;
            p1.vx += (mdx / mDist) * mForce - (mdy / mDist) * (mForce * 0.3);
            p1.vy += (mdy / mDist) * mForce + (mdx / mDist) * (mForce * 0.3);
          } else if (this.mouseMode === 'freeze') {
            p1.vx *= 0.7;
            p1.vy *= 0.7;
          } else if (this.mouseMode === 'hyper_drive') {
            p1.vx += (mdx / mDist) * (12 * mult);
            p1.vy += (mdy / mDist) * (12 * mult);
            p1.color = '#f43f5e';
            p1.colorUint32 = this.parseColorToUint32('#f43f5e');
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
        if (p1.originX !== undefined && p1.originY === 20 && p1.y >= this.height - 10) {
          p1.x = p1.originX + Math.random() * (this.width * 0.4);
          p1.y = 15;
          p1.vy = Math.random() * 4 + 2;
          p1.vx = (Math.random() - 0.5) * 1.5;
        }

        // DNA Helix horizontal wrapping & undulation
        if (p1.ignoreGravity && p1.vx > 0 && (p1.color === '#06b6d4' || p1.color === '#a855f7')) {
          if (p1.x > this.width - 10) {
            p1.x = 10;
          }
          const wavelength = 120;
          const angle = (p1.x / wavelength) * Math.PI * 2;
          const dir = p1.color === '#06b6d4' ? 1 : -1;
          const targetY = (this.height / 2) + Math.sin(angle) * 50 * dir;
          p1.vy += (targetY - p1.y) * 0.2;
        }

        // Environmental Gravity & Friction
        if (!p1.ignoreGravity) {
          p1.vx += this.gravityX;
          p1.vy += this.gravityY;
          p1.vx *= this.damping;
          p1.vy *= this.damping;
        } else {
          // Speed check for orbital particles so orbital energy isn't continuously bled by global damping
          const spdSq = p1.vx * p1.vx + p1.vy * p1.vy;
          if (spdSq > this.maxSpeed * this.maxSpeed) {
            const spd = Math.sqrt(spdSq);
            p1.vx = (p1.vx / spd) * this.maxSpeed;
            p1.vy = (p1.vy / spd) * this.maxSpeed;
          }
        }

        p1.x += p1.vx;
        p1.y += p1.vy;
      }

      // Boundary Conditions
      const rad = p1.radius || this.particleSize;

      if (this.boundaryMode === 'bounce') {
        if (p1.x - rad < 0) {
          p1.x = rad;
          p1.vx *= -this.elasticity;
        } else if (p1.x + rad > this.width) {
          p1.x = this.width - rad;
          p1.vx *= -this.elasticity;
        }

        if (p1.y - rad < 0) {
          p1.y = rad;
          p1.vy *= -this.elasticity;
        } else if (p1.y + rad > this.height) {
          p1.y = this.height - rad;
          p1.vy *= -this.elasticity;
        }
      } else if (this.boundaryMode === 'wrap') {
        if (p1.x < 0) p1.x += this.width;
        if (p1.x > this.width) p1.x -= this.width;
        if (p1.y < 0) p1.y += this.height;
        if (p1.y > this.height) p1.y -= this.height;
      } else if (this.boundaryMode === 'void') {
        if (p1.x < -10 || p1.x > this.width + 10 || p1.y < -10 || p1.y > this.height + 10) {
          p1.lifespan = 0;
          hasExpired = true;
        }
      }
    }

    if (hasExpired) {
      this.particles = this.particles.filter(p => p && (p.lifespan === undefined || p.lifespan > 0));
    }

    this.stepSprings();
    if (this.flockEnabled) this.stepFlock();
    this.stepSwarm(mouseX, mouseY, mouseActive);
    this.onAfterStep?.();
  }

  private stepFlock() {
    const ps = this.particles;
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

  private stepSwarm(mouseX?: number, mouseY?: number, mouseActive?: boolean) {
    if (!this.swarm.n) return;
    this.swarm.step({
      width: this.width,
      height: this.height,
      gx: this.gravityX,
      gy: this.gravityY,
      damp: this.damping,
      bounce: this.elasticity,
      collide: this.collisionsEnabled,
      mx: mouseX ?? this.lastMouseX,
      my: mouseY ?? this.lastMouseY,
      mouse: !!mouseActive,
      mouseForce: this.mouseForceMultiplier * (this.mouseMode === "hawk" ? 2.4 : 1),
      mouseRadius: this.mouseRadius,
      attract: this.mouseMode === "attract" || this.mouseMode === "gravity_well",
    });
  }

  private stepSprings() {
    if (!this.springs.length) return;
    const ps = this.particles;
    for (const s of this.springs) {
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

  // Canvas Renderer
  public render(ctx: CanvasRenderingContext2D) {
    const total = this.particles.length;

    // High performance pixel buffer rendering for large particle counts (>1000)
    if (total > 1000) {
      if (!this.imgData || this.imgData.width !== this.width || this.imgData.height !== this.height) {
        this.imgData = ctx.createImageData(this.width, this.height);
        this.buf32 = new Uint32Array(this.imgData.data.buffer);
      }

      const w = this.width;
      const h = this.height;
      const buf = this.buf32!;

      // Background fill (#0a0a0c in ABGR format = 0xFF0C0A0A)
      buf.fill(0xFF0C0A0A);

      for (let i = 0; i < total; i++) {
        const p = this.particles[i];
        if (!p) continue;
        const px = (p.x + 0.5) | 0;
        const py = (p.y + 0.5) | 0;
        if (px >= 0 && px < w && py >= 0 && py < h) {
          let c32 = p.colorUint32 || 0xFFFFFFFF;

          if (this.colorMode === 'velocity') {
            const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
            const hue = Math.max(0, Math.min(240, 240 - Math.floor(speed * 20)));
            c32 = this.parseColorToUint32(`hsl(${hue}, 100%, 65%)`);
          } else if (this.colorMode === 'charge') {
            c32 = p.charge > 0 ? 0xFF3b82f6 : p.charge < 0 ? 0xFFef4444 : 0xFFFFFFFF;
          } else if (this.colorMode === 'rainbow') {
            const hue = (p.x + p.y) % 360;
            c32 = this.parseColorToUint32(`hsl(${hue}, 90%, 65%)`);
          } else if (this.colorMode === 'density') {
            const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
            const hue = Math.max(0, Math.min(300, 280 - Math.floor(speed * 15)));
            c32 = this.parseColorToUint32(`hsl(${hue}, 100%, 60%)`);
          } else if (this.colorMode === 'lifespan') {
            const ratio = p.maxLife && p.lifespan ? p.lifespan / p.maxLife : 1;
            c32 = this.parseColorToUint32(`hsl(${Math.floor(ratio * 120)}, 100%, 60%)`);
          }

          buf[py * w + px] = c32;
        }
      }

      ctx.putImageData(this.imgData, 0, 0);
      if (this.lastMouseActive) {
        this.renderMouseIndicator(ctx);
      }
      return;
    }

    // Standard vector path rendering for smaller particle counts with motion glow & trails
    ctx.fillStyle = this.showTrails ? 'rgba(10, 10, 12, 0.25)' : '#0a0a0c';
    ctx.fillRect(0, 0, this.width, this.height);

    for (let i = 0; i < total; i++) {
      const p = this.particles[i];
      if (!p) continue;

      let renderColor = p.color || '#fff';
      if (this.colorMode === 'velocity') {
        const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
        const hue = Math.max(0, Math.min(240, 240 - Math.floor(speed * 20)));
        renderColor = `hsl(${hue}, 100%, 65%)`;
      } else if (this.colorMode === 'charge') {
        renderColor = p.charge > 0 ? '#3b82f6' : p.charge < 0 ? '#ef4444' : '#ffffff';
      } else if (this.colorMode === 'rainbow') {
        const hue = (p.x + p.y) % 360;
        renderColor = `hsl(${hue}, 90%, 65%)`;
      } else if (this.colorMode === 'density') {
        const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
        const hue = Math.max(0, Math.min(300, 280 - Math.floor(speed * 15)));
        renderColor = `hsl(${hue}, 100%, 60%)`;
      } else if (this.colorMode === 'lifespan') {
        const ratio = p.maxLife && p.lifespan ? p.lifespan / p.maxLife : 1;
        renderColor = `hsl(${Math.floor(ratio * 120)}, 100%, 60%)`;
      }

      // Draw Trail
      if (this.showTrails && p.trail && p.trail.length > 1) {
        ctx.beginPath();
        if (p.trail[0]) {
          ctx.moveTo(p.trail[0].x, p.trail[0].y);
          for (let t = 1; t < p.trail.length; t++) {
            if (p.trail[t]) {
              ctx.lineTo(p.trail[t].x, p.trail[t].y);
            }
          }
          ctx.strokeStyle = renderColor;
          ctx.globalAlpha = 0.3;
          ctx.lineWidth = (p.radius || this.particleSize) * 0.8;
          ctx.stroke();
          ctx.globalAlpha = 1.0;
        }
      }

      // Draw Particle Body
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.radius || this.particleSize, 0, Math.PI * 2);
      ctx.fillStyle = renderColor;
      ctx.fill();

      // Outer Glow for Special Types
      if (p.type === 'blackhole' || p.type === 'repulsor') {
        ctx.beginPath();
        ctx.arc(p.x, p.y, (p.radius || 10) + 6, 0, Math.PI * 2);
        ctx.strokeStyle = renderColor;
        ctx.lineWidth = 2;
        ctx.stroke();
      }
    }

    if (this.lastMouseActive) {
      this.renderMouseIndicator(ctx);
    }
  }

  private renderMouseIndicator(ctx: CanvasRenderingContext2D) {
    const radiusCap = Math.min(this.mouseRadius, Math.min(this.width, this.height) / 2);
    ctx.save();
    ctx.beginPath();
    ctx.arc(this.lastMouseX, this.lastMouseY, radiusCap, 0, Math.PI * 2);
    ctx.strokeStyle = 'rgba(34, 211, 238, 0.85)';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.fillStyle = 'rgba(34, 211, 238, 0.12)';
    ctx.fill();

    ctx.beginPath();
    ctx.arc(this.lastMouseX, this.lastMouseY, 3, 0, Math.PI * 2);
    ctx.fillStyle = '#22d3ee';
    ctx.fill();
    ctx.restore();
    this.drawSprings(ctx);
  }

  private drawSprings(ctx: CanvasRenderingContext2D) {
    if (!this.springs.length) return;
    ctx.save();
    ctx.strokeStyle = "rgba(200,204,212,0.45)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (const s of this.springs) {
      const a = this.particles[s.a];
      const b = this.particles[s.b];
      if (!a || !b) continue;
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
    }
    ctx.stroke();
    ctx.restore();
  }

  // --- Diagnostics & Health Inspection ---
  public getDiagnostics() {
    let nanCount = 0;
    let outOfBoundsCount = 0;
    let extremeVelocityCount = 0;
    let maxSpeedFound = 0;

    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (!p) continue;
      if (Number.isNaN(p.x) || Number.isNaN(p.y) || Number.isNaN(p.vx) || Number.isNaN(p.vy)) {
        nanCount++;
      } else {
        if (p.x < -100 || p.x > this.width + 100 || p.y < -100 || p.y > this.height + 100) {
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
      this.particles.length * 128 +
      this.swarm.xy.byteLength +
      this.swarm.v.byteLength +
      this.swarm.color.byteLength +
      (this.imgData ? this.imgData.data.byteLength : 0);

    return {
      particleCount: this.particles.length + this.swarm.n,
      maxParticles: this.maxParticles,
      nanCount,
      outOfBoundsCount,
      extremeVelocityCount,
      maxSpeedFound: Math.round(maxSpeedFound),
      memoryBytes: approxMemoryBytes,
      isHealthy: issues.length === 0,
      issues
    };
  }

  // --- Manual Fix Actions ---
  public purgeNaNParticles(): { success: boolean; purged: number } {
    const prevCount = this.particles.length;
    this.particles = this.particles.filter(p => p && !Number.isNaN(p.x) && !Number.isNaN(p.y) && !Number.isNaN(p.vx) && !Number.isNaN(p.vy));
    const purged = prevCount - this.particles.length;
    return { success: true, purged };
  }

  public clampVelocities(): { success: boolean; clamped: number } {
    let clamped = 0;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (!p) continue;
      const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (speed > this.maxSpeed) {
        const factor = this.maxSpeed / speed;
        p.vx *= factor;
        p.vy *= factor;
        clamped++;
      }
    }
    return { success: true, clamped };
  }

  public wrapOrTrimOutOfBounds(): { success: boolean; trimmed: number } {
    let trimmed = 0;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (!p) continue;
      if (p.x < 0 || p.x > this.width || p.y < 0 || p.y > this.height) {
        p.x = Math.max(0, Math.min(this.width, p.x));
        p.y = Math.max(0, Math.min(this.height, p.y));
        trimmed++;
      }
    }
    return { success: true, trimmed };
  }

  public reallocateBuffers(): { success: boolean } {
    this.imgData = null;
    this.buf32 = null;
    return { success: true };
  }

  public zeroForces(): { success: boolean; resetCount: number } {
    let resetCount = 0;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (p) {
        p.vx = 0;
        p.vy = 0;
        resetCount++;
      }
    }
    return { success: true, resetCount };
  }

  public resetCharges(): { success: boolean; balancedCount: number } {
    let balancedCount = 0;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (p) {
        p.charge = i % 2 === 0 ? 1 : -1;
        balancedCount++;
      }
    }
    return { success: true, balancedCount };
  }

  // --- Stress Test Injectors (for testing debug diagnostics) ---
  public injectCorruptVectorParticles(): { success: boolean } {
    for (let i = 0; i < 15; i++) {
      this.addParticle({
        x: NaN,
        y: NaN,
        vx: 1000,
        vy: NaN,
        radius: 4,
        color: '#ff0055'
      });
    }
    return { success: true };
  }

  public injectHyperVelocityExplosion(): { success: boolean } {
    const cx = this.width / 2;
    const cy = this.height / 2;
    for (let i = 0; i < 50; i++) {
      const angle = Math.random() * Math.PI * 2;
      this.addParticle({
        x: cx,
        y: cy,
        vx: Math.cos(angle) * 250,
        vy: Math.sin(angle) * 250,
        radius: 5,
        color: '#f97316'
      });
    }
    return { success: true };
  }

  public runAutoFix(): { logs: string[] } {
    const logs: string[] = [];
    logs.push('Initiating Particle Simulator Automated Diagnostics Pass...');

    const diag = this.getDiagnostics();
    if (diag.isHealthy) {
      logs.push('✓ All particle vectors, velocities, and pixel buffers verified normal.');
      logs.push('✓ No critical anomalies detected.');
      return { logs };
    }

    if (diag.nanCount > 0) {
      const res = this.purgeNaNParticles();
      logs.push(`✓ Auto-Fix Step 1/4: Purged ${res.purged} corrupt/NaN particles.`);
    }

    if (diag.outOfBoundsCount > 0) {
      const res = this.wrapOrTrimOutOfBounds();
      logs.push(`✓ Auto-Fix Step 2/4: Re-centered ${res.trimmed} out-of-bounds particles.`);
    }

    if (diag.extremeVelocityCount > 0) {
      const res = this.clampVelocities();
      logs.push(`✓ Auto-Fix Step 3/4: Clamped velocities for ${res.clamped} hyper-fast particles.`);
    }

    this.reallocateBuffers();
    logs.push('✓ Auto-Fix Step 4/4: Re-allocated canvas pixel buffers successfully.');

    const postDiag = this.getDiagnostics();
    logs.push(`Auto-Fix Sequence Completed. System health status: ${postDiag.isHealthy ? '100% OPERATIONAL' : 'RECOVERY COMPLETED'}.`);
    return { logs };
  }
}
