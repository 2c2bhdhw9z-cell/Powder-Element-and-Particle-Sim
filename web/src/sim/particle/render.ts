import type { ParticleCtx } from "./context";

/** Fast ABGR Uint32 color converter for Little-Endian ImageData */
export function parseColorToUint32(colorStr: string): number {
  if (colorStr.startsWith("#")) {
    let hex = colorStr.slice(1);
    if (hex.length === 3) hex = hex.split("").map((c) => c + c).join("");
    const num = parseInt(hex, 16);
    const r = (num >> 16) & 255;
    const g = (num >> 8) & 255;
    const b = num & 255;
    return 0xff000000 | (b << 16) | (g << 8) | r;
  }
  if (colorStr.startsWith("hsl")) {
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
          if (t < 1 / 6) return p + (q - p) * 6 * t;
          if (t < 1 / 2) return q;
          if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
          return p;
        };
        r = hue2rgb(h + 1 / 3);
        g = hue2rgb(h);
        b = hue2rgb(h - 1 / 3);
      }
      return 0xff000000 | (Math.round(b * 255) << 16) | (Math.round(g * 255) << 8) | Math.round(r * 255);
    }
  }
  return 0xffffffff; // default white
}

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

    // Background fill (#0a0a0c in ABGR format = 0xFF0C0A0A)
    buf.fill(0xff0c0a0a);

    for (let i = 0; i < total; i++) {
      const p = e.particles[i];
      if (!p) continue;
      const px = (p.x + 0.5) | 0;
      const py = (p.y + 0.5) | 0;
      if (px >= 0 && px < w && py >= 0 && py < h) {
        let c32 = p.colorUint32 || 0xffffffff;

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
          const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
          const hue = Math.max(0, Math.min(300, 280 - Math.floor(speed * 15)));
          c32 = parseColorToUint32(`hsl(${hue}, 100%, 60%)`);
        } else if (e.colorMode === "lifespan") {
          const ratio = p.maxLife && p.lifespan ? p.lifespan / p.maxLife : 1;
          c32 = parseColorToUint32(`hsl(${Math.floor(ratio * 120)}, 100%, 60%)`);
        }

        buf[py * w + px] = c32;
      }
    }

    ctx.putImageData(e.imgData, 0, 0);
    if (e.lastMouseActive) {
      renderMouseIndicator(e, ctx);
    }
    return;
  }

  // Standard vector path rendering for smaller particle counts with motion glow & trails
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
      const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy);
      const hue = Math.max(0, Math.min(300, 280 - Math.floor(speed * 15)));
      renderColor = `hsl(${hue}, 100%, 60%)`;
    } else if (e.colorMode === "lifespan") {
      const ratio = p.maxLife && p.lifespan ? p.lifespan / p.maxLife : 1;
      renderColor = `hsl(${Math.floor(ratio * 120)}, 100%, 60%)`;
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

  if (e.lastMouseActive) {
    renderMouseIndicator(e, ctx);
  }
}

function renderMouseIndicator(e: ParticleCtx, ctx: CanvasRenderingContext2D) {
  const radiusCap = Math.min(e.mouseRadius, Math.min(e.width, e.height) / 2);
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
  drawSprings(e, ctx);
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
    render(e, ctx);
    return canvas.toDataURL("image/png");
  } catch {
    return "";
  }
}
