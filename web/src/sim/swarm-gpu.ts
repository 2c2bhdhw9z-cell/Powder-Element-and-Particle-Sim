const WGSL = /* wgsl */ `
struct Params {
  n: u32,
  cols: u32,
  rows: u32,
  flags: u32,
  width: f32,
  height: f32,
  gx: f32,
  gy: f32,
  damp: f32,
  bounce: f32,
  cell: f32,
  force: f32,
  mx: f32,
  my: f32,
  radius: f32,
  pad: f32,
}

@group(0) @binding(0) var<storage, read_write> xy: array<vec2<f32>>;
@group(0) @binding(1) var<storage, read_write> vel: array<vec2<f32>>;
@group(0) @binding(2) var<storage, read_write> grid: array<atomic<i32>>;
@group(0) @binding(3) var<uniform> p: Params;
@group(0) @binding(4) var<storage, read_write> nextp: array<i32>;

@compute @workgroup_size(256)
fn integrate(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.n) { return; }
  var v = vel[i];
  var pos = xy[i];
  v = v * p.damp + vec2<f32>(p.gx, p.gy);
  if ((p.flags & 2u) != 0u) {
    let d = vec2<f32>(p.mx, p.my) - pos;
    let d2 = dot(d, d);
    let r2 = p.radius * p.radius;
    if (d2 < r2 && d2 > 0.5) {
      let inv = p.force / sqrt(d2);
      let s = select(-1.0, 1.0, (p.flags & 4u) != 0u);
      v += d * inv * s;
    }
  }
  pos += v;
  if (pos.x < 1.0) { pos.x = 1.0; v.x *= -p.bounce; }
  else if (pos.x > p.width - 1.0) { pos.x = p.width - 1.0; v.x *= -p.bounce; }
  if (pos.y < 1.0) { pos.y = 1.0; v.y *= -p.bounce; }
  else if (pos.y > p.height - 1.0) { pos.y = p.height - 1.0; v.y *= -p.bounce; }
  xy[i] = pos;
  vel[i] = v;
}

@compute @workgroup_size(256)
fn clearGrid(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.cols * p.rows) { return; }
  atomicStore(&grid[i], -1);
}

@compute @workgroup_size(256)
fn occupy(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.n) { return; }
  let pos = xy[i];
  let cx = clamp(i32(pos.x / p.cell), 0, i32(p.cols) - 1);
  let cy = clamp(i32(pos.y / p.cell), 0, i32(p.rows) - 1);
  let b = u32(cy) * p.cols + u32(cx);
  let old = atomicExchange(&grid[b], i32(i));
  nextp[i] = old;
}

@compute @workgroup_size(256)
fn collide(@builtin(global_invocation_id) gid: vec3<u32>) {
  let i = gid.x;
  if (i >= p.n) { return; }
  if ((p.flags & 1u) == 0u) { return; }
  var pi = xy[i];
  var vi = vel[i];
  let diam = max(p.cell * 0.88, 3.2);
  let cx = clamp(i32(pi.x / p.cell), 0, i32(p.cols) - 1);
  let cy = clamp(i32(pi.y / p.cell), 0, i32(p.rows) - 1);
  for (var oy = -1; oy <= 1; oy++) {
    for (var ox = -1; ox <= 1; ox++) {
      let ncx = clamp(cx + ox, 0, i32(p.cols) - 1);
      let ncy = clamp(cy + oy, 0, i32(p.rows) - 1);
      let nb = u32(ncy) * p.cols + u32(ncx);
      var j = atomicLoad(&grid[nb]);
      var steps = 0;
      while (j >= 0 && steps < 8) {
        steps = steps + 1;
        let ju = u32(j);
        if (ju >= p.n) { break; }
        if (ju != i) {
          let pj = xy[ju];
          let d = pi - pj;
          let dist2 = dot(d, d);
          if (dist2 < diam * diam && dist2 > 0.0001) {
            let dist = sqrt(dist2);
            let nrm = d / dist;
            let overlap = diam - dist;
            pi += nrm * (overlap * 0.5);
            let vj = vel[ju];
            let vn = dot(vi - vj, nrm);
            if (vn < 0.0) {
              vi -= nrm * (vn * 0.92);
            }
            let rel = vi - vj;
            let vt = rel - nrm * dot(rel, nrm);
            vi -= vt * 0.18;
          }
        }
        j = nextp[ju];
      }
    }
  }
  vi *= 0.996;
  if (pi.x < 1.0) { pi.x = 1.0; vi.x *= -p.bounce; }
  else if (pi.x > p.width - 1.0) { pi.x = p.width - 1.0; vi.x *= -p.bounce; }
  if (pi.y < 1.0) { pi.y = 1.0; vi.y *= -p.bounce; }
  else if (pi.y > p.height - 1.0) { pi.y = p.height - 1.0; vi.y *= -p.bounce; }
  xy[i] = pi;
  vel[i] = vi;
}
`;

const DRAW_WGSL = /* wgsl */ `
struct DrawP {
  res: vec2<f32>,
  size: f32,
  pad: f32,
}
@group(0) @binding(0) var<uniform> d: DrawP;
struct VSOut {
  @builtin(position) pos: vec4<f32>,
  @builtin(point_size) ps: f32,
  @location(0) col: vec4<f32>,
}
@vertex
fn vs(@location(0) xy: vec2<f32>, @location(1) col: vec4<f32>) -> VSOut {
  var o: VSOut;
  let clip = (xy / d.res) * 2.0 - vec2<f32>(1.0, 1.0);
  o.pos = vec4<f32>(clip.x, -clip.y, 0.0, 1.0);
  o.ps = max(d.size, 1.4);
  o.col = col;
  return o;
}
@fragment
fn fs(o: VSOut, @builtin(point_coord) pc: vec2<f32>) -> @location(0) vec4<f32> {
  let p = pc * 2.0 - vec2<f32>(1.0, 1.0);
  if (dot(p, p) > 1.0) { discard; }
  return vec4<f32>(max(o.col.rgb, vec3<f32>(0.35, 0.55, 0.95)), 1.0);
}
`;

export class SwarmGPU {
  ok = false;
  busy = false;
  private device: GPUDevice | null = null;
  private pipeI: GPUComputePipeline | null = null;
  private pipeC: GPUComputePipeline | null = null;
  private pipeO: GPUComputePipeline | null = null;
  private pipeX: GPUComputePipeline | null = null;
  private xyBuf: GPUBuffer | null = null;
  private vBuf: GPUBuffer | null = null;
  private gridBuf: GPUBuffer | null = null;
  private nextBuf: GPUBuffer | null = null;
  private nextCap = 0;
  private uniBuf: GPUBuffer | null = null;
  private layout: GPUBindGroupLayout | null = null;
  private cap = 0;
  private gridCap = 0;
  private readXy: [GPUBuffer | null, GPUBuffer | null] = [null, null];
  private readV: [GPUBuffer | null, GPUBuffer | null] = [null, null];
  private slotBusy = [false, false];
  private bind: unknown = null;
  private bindKey = "";
  private vtxBuf: GPUBuffer | null = null;
  private colGpu: GPUBuffer | null = null;
  private drawUni: GPUBuffer | null = null;
  private pipeDraw: GPURenderPipeline | null = null;
  private drawLayout: GPUBindGroupLayout | null = null;
  private ctx: GPUCanvasContext | null = null;
  private lastColorTick = -1;
  private frames = 0;
  private readCap = 0;
  resident = 0;
  dirty = true;

  async init() {
    if (this.ok || this.device) return this.ok;
    try {
      if (!navigator.gpu) return false;
      const adapter = await navigator.gpu.requestAdapter();
      if (!adapter) return false;
      const device = await adapter.requestDevice();
      this.device = device;
      const module = device.createShaderModule({ code: WGSL });
      this.layout = device.createBindGroupLayout({
        entries: [
          { binding: 0, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
          { binding: 1, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
          { binding: 2, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
          { binding: 3, visibility: GPUShaderStage.COMPUTE, buffer: { type: "uniform" } },
          { binding: 4, visibility: GPUShaderStage.COMPUTE, buffer: { type: "storage" } },
        ],
      });
      const pl = device.createPipelineLayout({ bindGroupLayouts: [this.layout] });
      this.pipeI = device.createComputePipeline({ layout: pl, compute: { module, entryPoint: "integrate" } });
      this.pipeC = device.createComputePipeline({ layout: pl, compute: { module, entryPoint: "clearGrid" } });
      this.pipeO = device.createComputePipeline({ layout: pl, compute: { module, entryPoint: "occupy" } });
      this.pipeX = device.createComputePipeline({ layout: pl, compute: { module, entryPoint: "collide" } });
      this.uniBuf = device.createBuffer({ size: 64, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      this.drawUni = device.createBuffer({ size: 16, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
      this.ok = true;
      return true;
    } catch {
      this.ok = false;
      return false;
    }
  }

  private fit(n: number, gridN: number) {
    const device = this.device!;
    const need = Math.max(256, n) * 8;
    if (!this.xyBuf || this.cap < need) {
      this.xyBuf?.destroy();
      this.vBuf?.destroy();
      this.readXy[0]?.destroy();
      this.readXy[1]?.destroy();
      this.readV[0]?.destroy();
      this.readV[1]?.destroy();
      this.cap = need;
      this.readCap = need;
      this.xyBuf = device.createBuffer({ size: need, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC });
      this.vBuf = device.createBuffer({ size: need, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC });
      this.vtxBuf?.destroy();
      this.colGpu?.destroy();
      this.vtxBuf = device.createBuffer({ size: need, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
      this.colGpu = device.createBuffer({ size: need / 2, usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST });
      this.readXy[0] = device.createBuffer({ size: need, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      this.readXy[1] = device.createBuffer({ size: need, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      this.readV[0] = device.createBuffer({ size: need, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      this.readV[1] = device.createBuffer({ size: need, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
      this.slotBusy = [false, false];
      this.bind = null;
      this.dirty = true;
      this.resident = 0;
    }
    if (!this.nextBuf || this.nextCap < need / 2) {
      this.nextBuf?.destroy();
      this.nextCap = need / 2;
      this.nextBuf = device.createBuffer({ size: this.nextCap, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
      this.bind = null;
    }
    const gbytes = Math.max(256, gridN) * 4;
    if (!this.gridBuf || this.gridCap < gbytes) {
      this.gridBuf?.destroy();
      this.gridCap = gbytes;
      this.gridBuf = device.createBuffer({ size: gbytes, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
      this.bind = null;
    }
  }

  tick(
    xy: Float32Array,
    v: Float32Array,
    n: number,
    opts: {
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
    },
  ) {
    if (!this.ok || !this.device || n < 1) return false;
    const slot = !this.slotBusy[0] ? 0 : !this.slotBusy[1] ? 1 : -1;
    if (slot !== 0 && slot !== 1) return false;
    const device = this.device;
    const cell = n > 120000 ? 7 : n > 40000 ? 6 : 4;
    const cols = Math.max(1, Math.ceil(opts.width / cell));
    const rows = Math.max(1, Math.ceil(opts.height / cell));
    this.fit(n, cols * rows);
    const flags = (opts.collide ? 1 : 0) | (opts.mouse ? 2 : 0) | (opts.attract ? 4 : 0);
    const u = new ArrayBuffer(64);
    const u32 = new Uint32Array(u);
    const f32 = new Float32Array(u);
    u32[0] = n;
    u32[1] = cols;
    u32[2] = rows;
    u32[3] = flags;
    f32[4] = opts.width;
    f32[5] = opts.height;
    f32[6] = opts.gx;
    f32[7] = opts.gy;
    f32[8] = opts.damp;
    f32[9] = opts.bounce;
    f32[10] = cell;
    f32[11] = opts.mouseForce * 0.08;
    f32[12] = opts.mx;
    f32[13] = opts.my;
    f32[14] = opts.mouseRadius;
    device.queue.writeBuffer(this.uniBuf!, 0, u);
    if (this.dirty || this.resident !== n) {
      device.queue.writeBuffer(this.xyBuf!, 0, xy.subarray(0, n * 2));
      device.queue.writeBuffer(this.vBuf!, 0, v.subarray(0, n * 2));
      this.dirty = false;
      this.resident = n;
    }
    const key = `${this.cap}:${this.gridCap}`;
    if (!this.bind || this.bindKey !== key) {
      this.bind = device.createBindGroup({
        layout: this.layout!,
        entries: [
          { binding: 0, resource: { buffer: this.xyBuf! } },
          { binding: 1, resource: { buffer: this.vBuf! } },
          { binding: 2, resource: { buffer: this.gridBuf! } },
          { binding: 3, resource: { buffer: this.uniBuf! } },
          { binding: 4, resource: { buffer: this.nextBuf! } },
        ],
      });
      this.bindKey = key;
    }
    const bg = this.bind;
    const enc = device.createCommandEncoder();
    const groups = Math.ceil(n / 256);
    const gGroups = Math.ceil((cols * rows) / 256);
    const pass1 = enc.beginComputePass();
    pass1.setBindGroup(0, bg);
    pass1.setPipeline(this.pipeI!);
    pass1.dispatchWorkgroups(groups);
    pass1.end();
    if (opts.collide) {
      const pass2 = enc.beginComputePass();
      pass2.setBindGroup(0, bg);
      pass2.setPipeline(this.pipeC!);
      pass2.dispatchWorkgroups(gGroups);
      pass2.end();
      const pass3 = enc.beginComputePass();
      pass3.setBindGroup(0, bg);
      pass3.setPipeline(this.pipeO!);
      pass3.dispatchWorkgroups(groups);
      pass3.end();
      const pass4 = enc.beginComputePass();
      pass4.setBindGroup(0, bg);
      pass4.setPipeline(this.pipeX!);
      pass4.dispatchWorkgroups(groups);
      pass4.end();
      const pass5 = enc.beginComputePass();
      pass5.setBindGroup(0, bg);
      pass5.setPipeline(this.pipeC!);
      pass5.dispatchWorkgroups(gGroups);
      pass5.end();
      const pass6 = enc.beginComputePass();
      pass6.setBindGroup(0, bg);
      pass6.setPipeline(this.pipeO!);
      pass6.dispatchWorkgroups(groups);
      pass6.end();
      const pass7 = enc.beginComputePass();
      pass7.setBindGroup(0, bg);
      pass7.setPipeline(this.pipeX!);
      pass7.dispatchWorkgroups(groups);
      pass7.end();
    }
    if (this.vtxBuf) enc.copyBufferToBuffer(this.xyBuf!, 0, this.vtxBuf, 0, n * 8);
    this.frames++;
    const doRead = n < 120000 || this.frames % 2 === 1;
    if (doRead) {
      const readXy = this.readXy[slot]!;
      const readV = this.readV[slot]!;
      enc.copyBufferToBuffer(this.xyBuf!, 0, readXy, 0, n * 8);
      enc.copyBufferToBuffer(this.vBuf!, 0, readV, 0, n * 8);
      device.queue.submit([enc.finish()]);
      this.slotBusy[slot] = true;
      this.busy = this.slotBusy[0] && this.slotBusy[1];
      void Promise.all([readXy.mapAsync(GPUMapMode.READ), readV.mapAsync(GPUMapMode.READ)])
        .then(() => {
          const srcX = new Float32Array(readXy.getMappedRange());
          const srcV = new Float32Array(readV.getMappedRange());
          xy.set(srcX.subarray(0, n * 2));
          v.set(srcV.subarray(0, n * 2));
          readXy.unmap();
          readV.unmap();
          this.slotBusy[slot] = false;
          this.busy = this.slotBusy[0] && this.slotBusy[1];
        })
        .catch(() => {
          this.slotBusy[slot] = false;
          this.busy = false;
          this.ok = false;
          this.dirty = true;
        });
    } else {
      device.queue.submit([enc.finish()]);
    }
    return true;
  }

  present(
    canvas: HTMLCanvasElement,
    xy: Float32Array,
    color: Uint32Array,
    n: number,
    width: number,
    height: number,
    pointSize: number,
    colorTick: number,
  ) {
    if (!this.ok || !this.device || !this.vtxBuf || n < 1) return false;
    try {
      const device = this.device;
      if (!this.ctx || this.ctx.canvas !== canvas) {
        const ctx = canvas.getContext("webgpu");
        if (!ctx) return false;
        ctx.configure({
          device,
          format: navigator.gpu?.getPreferredCanvasFormat?.() || "bgra8unorm",
          alphaMode: "opaque",
        });
        this.ctx = ctx;
        const module = device.createShaderModule({ code: DRAW_WGSL });
        this.drawLayout = device.createBindGroupLayout({
          entries: [{ binding: 0, visibility: GPUShaderStage.VERTEX, buffer: { type: "uniform" } }],
        });
        this.pipeDraw = device.createRenderPipeline({
          layout: device.createPipelineLayout({ bindGroupLayouts: [this.drawLayout] }),
          vertex: {
            module,
            entryPoint: "vs",
            buffers: [
              { arrayStride: 8, attributes: [{ shaderLocation: 0, offset: 0, format: "float32x2" }] },
              { arrayStride: 4, attributes: [{ shaderLocation: 1, offset: 0, format: "unorm8x4" }] },
            ],
          },
          fragment: {
            module,
            entryPoint: "fs",
            targets: [{ format: navigator.gpu?.getPreferredCanvasFormat?.() || "bgra8unorm" }],
          },
          primitive: { topology: "point-list" },
        });
      }
      if (this.lastColorTick !== colorTick && this.colGpu) {
        device.queue.writeBuffer(this.colGpu, 0, color.subarray(0, n));
        this.lastColorTick = colorTick;
      }
      if (this.dirty && this.vtxBuf) {
        device.queue.writeBuffer(this.vtxBuf, 0, xy.subarray(0, n * 2));
      }
      const du = new Float32Array([width, height, Math.max(1.4, pointSize + 0.4), 0]);
      device.queue.writeBuffer(this.drawUni!, 0, du);
      const bg = device.createBindGroup({
        layout: this.drawLayout!,
        entries: [{ binding: 0, resource: { buffer: this.drawUni! } }],
      });
      const enc = device.createCommandEncoder();
      const pass = enc.beginRenderPass({
        colorAttachments: [
          {
            view: this.ctx.getCurrentTexture().createView(),
            loadOp: "clear",
            storeOp: "store",
            clearValue: { r: 0.039, g: 0.039, b: 0.047, a: 1 },
          },
        ],
      });
      pass.setPipeline(this.pipeDraw!);
      pass.setBindGroup(0, bg);
      pass.setVertexBuffer(0, this.vtxBuf);
      pass.setVertexBuffer(1, this.colGpu!);
      pass.draw(n);
      pass.end();
      device.queue.submit([enc.finish()]);
      return true;
    } catch {
      return false;
    }
  }
}

let gpu: SwarmGPU | null = null;

export function getSwarmGPU() {
  if (!gpu) {
    gpu = new SwarmGPU();
    void gpu.init();
  }
  return gpu;
}
