import { ParticleObject } from '../types/physics';

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
  public mouseMode: 'attract' | 'repel' | 'vortex' | 'emitter' | 'painter' | 'gravity_well' | 'freeze' | 'hyper_drive' = 'attract';
  public mouseRadius: number = 120;
  public mouseForceMultiplier: number = 1.0;
  public lastMouseX: number = 0;
  public lastMouseY: number = 0;
  public lastMouseActive: boolean = false;
  public colorMode: 'element' | 'velocity' | 'charge' | 'rainbow' | 'density' | 'lifespan' = 'element';
  public particleSize: number = 2;
  public maxParticles: number = 1000000;
  public showTrails: boolean = true;
  public decaySpeed: number = 0; // 0 = infinite life

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
    if (total === 0) return;

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
          } else if (this.mouseMode === 'repel') {
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

    const approxMemoryBytes = this.particles.length * 128 + (this.imgData ? this.imgData.data.byteLength : 0);

    return {
      particleCount: this.particles.length,
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
