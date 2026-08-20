import { getSwarmGPU } from "./swarm-gpu";

const MAX = 1_000_000;

export class Swarm {
  n = 0;
  xy = new Float32Array(0);
  v = new Float32Array(0);
  color = new Uint32Array(0);
  colorTick = 0;
  private occ: Uint8Array | null = null;
  private owner: Int32Array | null = null;
  private link: Int32Array | null = null;

  get count() {
    return this.n;
  }

  clear() {
    this.n = 0;
    this.colorTick++;
    getSwarmGPU().dirty = true;
    getSwarmGPU().resident = 0;
  }

  private grow(need: number) {
    const cur = this.xy.length / 2;
    const cap = Math.min(MAX, Math.max(need, cur ? cur * 2 : 8192));
    if (cur >= cap) return;
    const nxy = new Float32Array(cap * 2);
    const nv = new Float32Array(cap * 2);
    const nc = new Uint32Array(cap);
    if (this.n) {
      nxy.set(this.xy.subarray(0, this.n * 2));
      nv.set(this.v.subarray(0, this.n * 2));
      nc.set(this.color.subarray(0, this.n));
    }
    this.xy = nxy;
    this.v = nv;
    this.color = nc;
  }

  spawn(count: number, width: number, height: number, colorUint32: number, maxParticles: number) {
    const space = Math.max(0, Math.min(MAX, maxParticles) - this.n);
    const add = Math.min(count, space);
    if (add <= 0) return;
    this.grow(this.n + add);
    const cx = width * 0.5;
    const cy = height * 0.5;
    const span = Math.min(width, height) * 0.42;
    const xy = this.xy;
    const v = this.v;
    const col = this.color;
    let i = this.n;
    const end = i + add;
    for (; i < end; i++) {
      const a = Math.random() * Math.PI * 2;
      const d = Math.random() * span + 20;
      const i2 = i * 2;
      xy[i2] = cx + Math.cos(a) * d;
      xy[i2 + 1] = cy + Math.sin(a) * d;
      v[i2] = (Math.random() - 0.5) * 6;
      v[i2 + 1] = (Math.random() - 0.5) * 6;
      col[i] = colorUint32 || (0xff000000 | ((i * 97) & 255) | (((i * 57) & 255) << 8) | (((i * 13) & 255) << 16));
    }
    this.n = end;
    this.colorTick++;
    getSwarmGPU().dirty = true;
    void getSwarmGPU().init();
  }

  step(opts: {
    width: number;
    height: number;
    gx: number;
    gy: number;
    damp: number;
    bounce: number;
    collide: boolean;
    mx: number;
    my: number;
    mouse: boolean;
    mouseForce: number;
    mouseRadius: number;
    attract: boolean;
  }) {
    const n = this.n;
    if (!n) return;
    const gpu = getSwarmGPU();
    if (n >= 8000 && gpu.ok) {
      if (!gpu.busy) {
        gpu.tick(this.xy, this.v, n, opts);
      }
      return;
    }
    const xy = this.xy;
    const vel = this.v;
    const w = opts.width;
    const h = opts.height;
    const gx = opts.gx;
    const gy = opts.gy;
    const damp = opts.damp;
    const bounce = opts.bounce;
    const mx = opts.mx;
    const my = opts.my;
    const r2 = opts.mouseRadius * opts.mouseRadius;
    const force = (opts.attract ? 1 : -1) * opts.mouseForce * 0.08;
    const mouse = opts.mouse;

    for (let i = 0; i < n; i++) {
      const i2 = i * 2;
      vel[i2] = vel[i2] * damp + gx;
      vel[i2 + 1] = vel[i2 + 1] * damp + gy;
      if (mouse) {
        const dx = mx - xy[i2];
        const dy = my - xy[i2 + 1];
        const d2 = dx * dx + dy * dy;
        if (d2 < r2 && d2 > 0.5) {
          const inv = force / Math.sqrt(d2);
          vel[i2] += dx * inv;
          vel[i2 + 1] += dy * inv;
        }
      }
      xy[i2] += vel[i2];
      xy[i2 + 1] += vel[i2 + 1];
      if (xy[i2] < 1) {
        xy[i2] = 1;
        vel[i2] *= -bounce;
      } else if (xy[i2] > w - 1) {
        xy[i2] = w - 1;
        vel[i2] *= -bounce;
      }
      if (xy[i2 + 1] < 1) {
        xy[i2 + 1] = 1;
        vel[i2 + 1] *= -bounce;
      } else if (xy[i2 + 1] > h - 1) {
        xy[i2 + 1] = h - 1;
        vel[i2 + 1] *= -bounce;
      }
    }

    if (opts.collide && n > 1) {
      this.collide(w, h);
      this.collide(w, h);
    }
  }

  private collide(width: number, height: number) {
    const n = this.n;
    const cell = n > 120000 ? 7 : n > 40000 ? 5 : 4;
    const cols = Math.max(1, Math.ceil(width / cell));
    const rows = Math.max(1, Math.ceil(height / cell));
    const size = cols * rows;
    if (!this.owner || this.owner.length !== size) this.owner = new Int32Array(size);
    else this.owner.fill(-1);
    if (!this.link || this.link.length < n) this.link = new Int32Array(Math.max(n, 8192));
    const owner = this.owner;
    const link = this.link;
    const xy = this.xy;
    const vel = this.v;
    const diam = Math.max(3.2, cell * 0.88);
    const diam2 = diam * diam;
    owner.fill(-1);
    const stride = n > 250000 ? 2 : 1;
    for (let i = 0; i < n; i += stride) {
      const i2 = i * 2;
      let cx = (xy[i2] / cell) | 0;
      let cy = (xy[i2 + 1] / cell) | 0;
      if (cx < 0) cx = 0;
      else if (cx >= cols) cx = cols - 1;
      if (cy < 0) cy = 0;
      else if (cy >= rows) cy = rows - 1;
      const b = cy * cols + cx;
      link[i] = owner[b];
      owner[b] = i;
    }
    for (let i = 0; i < n; i += stride) {
      const i2 = i * 2;
      let px = xy[i2];
      let py = xy[i2 + 1];
      let vx = vel[i2];
      let vy = vel[i2 + 1];
      let cx = (px / cell) | 0;
      let cy = (py / cell) | 0;
      for (let oy = -1; oy <= 1; oy++) {
        const ny = cy + oy;
        if (ny < 0 || ny >= rows) continue;
        for (let ox = -1; ox <= 1; ox++) {
          const nx = cx + ox;
          if (nx < 0 || nx >= cols) continue;
          let j = owner[ny * cols + nx];
          let steps = 0;
          while (j >= 0 && steps < 8) {
            steps++;
            if (j !== i) {
              const j2 = j * 2;
              const dx = px - xy[j2];
              const dy = py - xy[j2 + 1];
              const d2 = dx * dx + dy * dy;
              if (d2 < diam2 && d2 > 0.0001) {
                const dist = Math.sqrt(d2);
                const nxn = dx / dist;
                const nyn = dy / dist;
                const overlap = diam - dist;
                px += nxn * overlap * 0.5;
                py += nyn * overlap * 0.5;
                const vn = (vx - vel[j2]) * nxn + (vy - vel[j2 + 1]) * nyn;
                if (vn < 0) {
                  vx -= nxn * vn * 0.92;
                  vy -= nyn * vn * 0.92;
                }
                const rvx = vx - vel[j2];
                const rvy = vy - vel[j2 + 1];
                const vtx = rvx - nxn * (rvx * nxn + rvy * nyn);
                const vty = rvy - nyn * (rvx * nxn + rvy * nyn);
                vx -= vtx * 0.18;
                vy -= vty * 0.18;
              }
            }
            j = link[j];
          }
        }
      }
      vx *= 0.996;
      vy *= 0.996;
      if (px < 1) {
        px = 1;
        vx *= -0.55;
      } else if (px > width - 1) {
        px = width - 1;
        vx *= -0.55;
      }
      if (py < 1) {
        py = 1;
        vy *= -0.55;
      } else if (py > height - 1) {
        py = height - 1;
        vy *= -0.55;
      }
      xy[i2] = px;
      xy[i2 + 1] = py;
      vel[i2] = vx;
      vel[i2 + 1] = vy;
    }
  }

  toSplit(limit = this.n) {
    const n = Math.min(this.n, limit);
    const x = new Array<number>(n);
    const y = new Array<number>(n);
    const vx = new Array<number>(n);
    const vy = new Array<number>(n);
    const c = new Array<number>(n);
    const xy = this.xy;
    const vel = this.v;
    for (let i = 0; i < n; i++) {
      const i2 = i * 2;
      x[i] = xy[i2];
      y[i] = xy[i2 + 1];
      vx[i] = vel[i2];
      vy[i] = vel[i2 + 1];
      c[i] = this.color[i];
    }
    return { n, x, y, vx, vy, c };
  }

  fromSplit(
    s: { n: number; x: number[]; y: number[]; vx: number[]; vy: number[]; c: number[] },
    width: number,
    height: number,
    maxParticles: number,
  ) {
    const n = Math.min(s.n, s.x.length);
    this.clear();
    this.spawn(n, width, height, 0xffd4c8c8, maxParticles);
    this.n = n;
    const xy = this.xy;
    const vel = this.v;
    for (let i = 0; i < n; i++) {
      const i2 = i * 2;
      xy[i2] = s.x[i];
      xy[i2 + 1] = s.y[i];
      vel[i2] = s.vx[i];
      vel[i2 + 1] = s.vy[i];
    }
    this.color.set(s.c);
    this.colorTick++;
    getSwarmGPU().dirty = true;
  }
}
