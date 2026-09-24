import { parseColorToUint32 } from "../color";
import type { ParticleCtx } from "./context";

/**
 * Re-exported because callers outside this module use it.
 *
 * The conversion itself lives in `../color`, shared with the powder renderer. The two had
 * their own copies and the copies drifted: this one was fixed while the other went on
 * reading every fractional hue wrongly, so a request for flame orange came back white.
 */
export { parseColorToUint32 };

/** Canvas renderer: pixel-buffer fast path above 1000, vector path below. */
export function render(e: ParticleCtx, ctx: CanvasRenderingContext2D) {
  const total = e.particles.length;

  // High performance pixel buffer rendering for large particle counts (>1000)
  if (total > 1000) {
    if (!e.imgData || e.imgData.width !== e.width || e.imgData.height !== e.height) {
      e.imgData = ctx.createImageData(e.width, e.height);
      e.buf32 = new Uint32Array(e.imgData.data.buffer);
    }

    const w = e.width;
    const h = e.height;
    const buf = e.buf32!;
    // Built only when it will actually be read.
    const density = e.colorMode === "density" ? buildDensityGrid(e, w, h) : null;

    // Background fill (#0a0a0c in ABGR format = 0xFF0C0A0A)
    buf.fill(0xff0c0a0a);

    for (let i = 0; i < total; i++) {
      const p = e.particles[i];
      if (!p) continue;
      // Skipped explicitly. The bitwise truncation below turns not-a-number into 0,
      // so corrupt particles used to pile into a bright dot in the top-left corner —
      // the diagnostics panel reported them while the renderer hid where they were.
      if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) continue;
      const px = (p.x + 0.5) | 0;
      const py = (p.y + 0.5) | 0;
      if (px >= 0 && px < w && py >= 0 && py < h) {
        // `!== undefined`, not truthiness: a legitimately black particle has a packed
        // colour of 0 and used to be drawn white.
        let c32 = p.colorUint32 !== undefined ? p.colorUint32 : 0xffffffff;

        if (e.colorMode === "velocity") {
          const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
          const hue = Math.max(0, Math.min(240, 240 - Math.floor(speed * 20)));
          c32 = parseColorToUint32(`hsl(${hue}, 100%, 65%)`);
        } else if (e.colorMode === "charge") {
          c32 = p.charge > 0 ? 0xff3b82f6 : p.charge < 0 ? 0xffef4444 : 0xffffffff;
        } else if (e.colorMode === "rainbow") {
          const hue = (p.x + p.y) % 360;
          c32 = parseColorToUint32(`hsl(${hue}, 90%, 65%)`);
        } else if (e.colorMode === "density") {
          // Genuinely local crowding. This used to compute speed and map it to a
          // slightly different hue range than "velocity" did, so two modes the
          // interface offers as distinct were measuring exactly the same thing.
          const crowd = densityAt(density, w, h, px, py);
          const hue = Math.max(0, Math.min(300, 280 - crowd * 26));
          c32 = parseColorToUint32(`hsl(${hue}, 100%, 60%)`);
        } else if (e.colorMode === "lifespan") {
          c32 = parseColorToUint32(`hsl(${Math.floor(lifespanRatio(p) * 120)}, 100%, 60%)`);
        }

        buf[py * w + px] = c32;
      }
    }

    ctx.putImageData(e.imgData, 0, 0);
    // A cloth is still a cloth above the pixel-path threshold.
    drawSprings(e, ctx);
    if (e.lastMouseActive) {
      renderMouseIndicator(e, ctx);
    }
    return;
  }

  // Standard vector path rendering for smaller particle counts with motion glow & trails
  const vectorDensity = e.colorMode === "density" ? buildDensityGrid(e, e.width, e.height) : null;
  ctx.fillStyle = e.showTrails ? "rgba(10, 10, 12, 0.25)" : "#0a0a0c";
  ctx.fillRect(0, 0, e.width, e.height);

  for (let i = 0; i < total; i++) {
    const p = e.particles[i];
    if (!p) continue;

    let renderColor = p.color || "#fff";
    if (e.colorMode === "velocity") {
      const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
      const hue = Math.max(0, Math.min(240, 240 - Math.floor(speed * 20)));
      renderColor = `hsl(${hue}, 100%, 65%)`;
    } else if (e.colorMode === "charge") {
      renderColor = p.charge > 0 ? "#3b82f6" : p.charge < 0 ? "#ef4444" : "#ffffff";
    } else if (e.colorMode === "rainbow") {
      const hue = (p.x + p.y) % 360;
      renderColor = `hsl(${hue}, 90%, 65%)`;
    } else if (e.colorMode === "density") {
      const crowd = densityAt(vectorDensity, e.width, e.height, p.x | 0, p.y | 0);
      const hue = Math.max(0, Math.min(300, 280 - crowd * 26));
      renderColor = `hsl(${hue}, 100%, 60%)`;
    } else if (e.colorMode === "lifespan") {
      renderColor = `hsl(${Math.floor(lifespanRatio(p) * 120)}, 100%, 60%)`;
    }

    // Draw Trail
    if (e.showTrails && p.trail && p.trail.length > 1) {
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
        ctx.lineWidth = (p.radius || e.particleSize) * 0.8;
        ctx.stroke();
        ctx.globalAlpha = 1.0;
      }
    }

    // Draw Particle Body
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.radius || e.particleSize, 0, Math.PI * 2);
    ctx.fillStyle = renderColor;
    ctx.fill();

    // Outer Glow for Special Types
    if (p.type === "blackhole" || p.type === "repulsor") {
      ctx.beginPath();
      ctx.arc(p.x, p.y, (p.radius || 10) + 6, 0, Math.PI * 2);
      ctx.strokeStyle = renderColor;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }

  // Springs are part of the world, so they draw whether or not the mouse is down.
  // drawSprings used to be called from the last line of the mouse indicator, which
  // only runs while the mouse is held — so cloth and rope structure appeared on
  // press and vanished on release.
  drawSprings(e, ctx);

  if (e.lastMouseActive) {
    renderMouseIndicator(e, ctx);
  }
}

function renderMouseIndicator(e: ParticleCtx, ctx: CanvasRenderingContext2D) {
  // The radius the physics actually uses. Capping the drawing at half the smaller
  // world dimension meant the circle the user saw was never the circle that acted —
  // and at the slider's maximum the physics treats the reach as unlimited, so that is
  // drawn as covering the world rather than as a misleadingly small ring.
  const unlimited = e.mouseRadius >= 800;
  const radiusCap = unlimited ? Math.hypot(e.width, e.height) : e.mouseRadius;
  ctx.save();
  ctx.beginPath();
  ctx.arc(e.lastMouseX, e.lastMouseY, radiusCap, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(34, 211, 238, 0.85)";
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = "rgba(34, 211, 238, 0.12)";
  ctx.fill();

  ctx.beginPath();
  ctx.arc(e.lastMouseX, e.lastMouseY, 3, 0, Math.PI * 2);
  ctx.fillStyle = "#22d3ee";
  ctx.fill();
  ctx.restore();
}

function drawSprings(e: ParticleCtx, ctx: CanvasRenderingContext2D) {
  if (!e.springs.length) return;
  ctx.save();
  ctx.strokeStyle = "rgba(200,204,212,0.45)";
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (const s of e.springs) {
    const a = e.particles[s.a];
    const b = e.particles[s.b];
    if (!a || !b) continue;
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
  }
  ctx.stroke();
  ctx.restore();
}

/** PNG data URL of the current frame ("" in non-DOM environments). */
export function captureThumbnail(e: ParticleCtx): string {
  try {
    if (typeof document === "undefined") return "";
    const canvas = document.createElement("canvas");
    canvas.width = e.width;
    canvas.height = e.height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return "";
    // Render into scratch buffers and restore the live ones. Above the pixel-path
    // threshold render() replaces imgData and buf32, so capturing a thumbnail forced
    // the next real frame to reallocate both.
    const liveImg = e.imgData;
    const liveBuf = e.buf32;
    e.imgData = null;
    e.buf32 = null;
    try {
      render(e, ctx);
      return canvas.toDataURL("image/png");
    } finally {
      e.imgData = liveImg;
      e.buf32 = liveBuf;
    }
  } catch {
    return "";
  }
}

/** Cell size of the crowding grid used by the "density" colour mode. */
const DENSITY_CELL = 16;

/**
 * Counts how many particles fall in each coarse cell of the world.
 *
 * Used only by the "density" colour mode, which previously did not measure density at
 * all — it measured speed, exactly like "velocity", just with a different hue range.
 */
function buildDensityGrid(e: ParticleCtx, w: number, h: number): Uint16Array {
  const cols = Math.max(1, Math.ceil(w / DENSITY_CELL));
  const rows = Math.max(1, Math.ceil(h / DENSITY_CELL));
  const grid = new Uint16Array(cols * rows);
  for (let i = 0; i < e.particles.length; i++) {
    const p = e.particles[i];
    if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) continue;
    let cx = (p.x / DENSITY_CELL) | 0;
    let cy = (p.y / DENSITY_CELL) | 0;
    if (cx < 0) cx = 0;
    else if (cx >= cols) cx = cols - 1;
    if (cy < 0) cy = 0;
    else if (cy >= rows) cy = rows - 1;
    const at = cy * cols + cx;
    if (grid[at] < 0xffff) grid[at]++;
  }
  return grid;
}

/** How crowded the cell containing a pixel is. */
function densityAt(grid: Uint16Array | null, w: number, h: number, px: number, py: number): number {
  if (!grid) return 0;
  const cols = Math.max(1, Math.ceil(w / DENSITY_CELL));
  const rows = Math.max(1, Math.ceil(h / DENSITY_CELL));
  let cx = (px / DENSITY_CELL) | 0;
  let cy = (py / DENSITY_CELL) | 0;
  if (cx < 0) cx = 0;
  else if (cx >= cols) cx = cols - 1;
  if (cy < 0) cy = 0;
  else if (cy >= rows) cy = rows - 1;
  return grid[cy * cols + cx];
}

/**
 * How much life a particle has left, from 1 (new) to 0 (about to die).
 *
 * The original expression was `p.maxLife && p.lifespan ? p.lifespan / p.maxLife : 1`,
 * whose falsy test on `lifespan` made a particle one frame from deletion report a
 * full ratio — so the colour mode painted dying particles as brand new, the exact
 * inverse of its purpose.
 */
function lifespanRatio(p: { lifespan?: number; maxLife?: number }): number {
  if (!p.maxLife || p.maxLife <= 0) return 1;
  const left = p.lifespan ?? p.maxLife;
  return Math.max(0, Math.min(1, left / p.maxLife));
}
