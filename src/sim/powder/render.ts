import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

export function parseColorToRgbComponents(colorStr: string): { r: number; g: number; b: number } {
  if (colorStr.startsWith("#")) {
    let hex = colorStr.slice(1);
    if (hex.length === 3) hex = hex.split("").map((c) => c + c).join("");
    const r = parseInt(hex.substring(0, 2), 16) || 0;
    const g = parseInt(hex.substring(2, 4), 16) || 0;
    const b = parseInt(hex.substring(4, 6), 16) || 0;
    return { r, g, b };
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
      return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) };
    }
  }
  return { r: 255, g: 255, b: 255 };
}

/** Render the grid onto a 2D ImageData context with the given overlay mode. */
export function renderToCanvas(e: PowderCtx, ctx: CanvasRenderingContext2D, overlayMode: "normal" | "temp" | "temp_overlay" | "density" = "normal") {
  ctx.imageSmoothingEnabled = false;
  if (!e.imageData || e.imageData.width !== e.width || e.imageData.height !== e.height) {
    e.imageData = ctx.createImageData(e.width, e.height);
  }

  const data32 = new Uint32Array(e.imageData.data.buffer);
  const w = e.width;
  const h = e.height;

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      const type = e.gridType[i];
      const temp = e.gridTemp[i];

      // 1. Pure Thermal Vision Heatmap
      if (overlayMode === "temp") {
        // Temperature color mapping: -100°C -> deep blue, 0°C -> teal, 20°C -> green, 100°C -> yellow, 500°C -> orange, 1500°C -> red, 3000°C -> white
        let r = 0, g = 0, b = 0;
        if (temp < 0) {
          const norm = Math.min(1, Math.abs(temp) / 100);
          b = Math.floor(150 + norm * 105);
          g = Math.floor(norm * 100);
        } else if (temp <= 40) {
          const norm = (temp) / 40;
          g = Math.floor(100 + norm * 100);
          b = Math.floor((1 - norm) * 150);
        } else if (temp <= 200) {
          const norm = (temp - 40) / 160;
          r = Math.floor(norm * 255);
          g = Math.floor(200 - norm * 50);
        } else if (temp <= 800) {
          const norm = (temp - 200) / 600;
          r = 255;
          g = Math.floor(150 - norm * 100);
          b = Math.floor(norm * 30);
        } else {
          const norm = Math.min(1, (temp - 800) / 2200);
          r = 255;
          g = Math.floor(50 + norm * 205);
          b = Math.floor(30 + norm * 225);
        }

        data32[i] = (255 << 24) | (b << 16) | (g << 8) | r;
        continue;
      }

      // 2. Element Density Map
      if (overlayMode === "density") {
        if (type === EMPTY_ELEMENT_ID) {
          data32[i] = 0xff0c0a0a;
        } else {
          const def = e.registry.getElement(type);
          const density = def.density || 1;
          const norm = Math.min(1, Math.max(0, density / 20));
          const r = Math.floor(norm * 255);
          const g = Math.floor((1 - norm) * 200);
          const b = 180;
          data32[i] = (255 << 24) | (b << 16) | (g << 8) | r;
        }
        continue;
      }

      if (type === EMPTY_ELEMENT_ID) {
        if (overlayMode === "temp_overlay" && Math.abs(temp - 20) > 10) {
          // Background heat glow for hot air / cold air
          let hr = 10, hg = 10, hb = 12;
          if (temp > 50) {
            const hnorm = Math.min(1, (temp - 50) / 800);
            hr = Math.floor(10 + hnorm * 180);
            hg = Math.floor(10 + hnorm * 40);
          } else if (temp < 0) {
            const cnorm = Math.min(1, Math.abs(temp) / 100);
            hb = Math.floor(12 + cnorm * 180);
            hg = Math.floor(10 + cnorm * 80);
          }
          data32[i] = (255 << 24) | (hb << 16) | (hg << 8) | hr;
        } else {
          data32[i] = 0xff0c0a0a; // ABGR dark background #0a0a0c
        }
        continue;
      }

      const def = e.registry.getElement(type);
      const { r, g, b } = parseColorToRgbComponents(def.color);

      // Color jitter / texture variation
      let varR = r;
      let varG = g;
      let varB = b;

      if (def.colorVariation && def.colorVariation > 0) {
        let jitter = 0;
        if (e.textureMode === "diagonal_matrix") {
          jitter = (((x * 3 + y * 7) % 19) - 9) * (def.colorVariation / 100);
        } else if (e.textureMode === "natural_grain") {
          // Fast bitwise integer hash for static natural sand grain speckling (no trig, no flicker)
          const hash = ((x * 1597334677) ^ (y * 3812015801)) >>> 0;
          const noise = ((hash % 100) - 50) / 50.0;
          jitter = noise * (def.colorVariation / 100);
        } else if (e.textureMode === "organic_flow") {
          const wave = Math.sin(x * 0.08 + y * 0.08 + e.frameCount * 0.05);
          jitter = wave * (def.colorVariation / 100);
        } else if (e.textureMode === "flat") {
          jitter = 0;
        }

        varR = Math.min(255, Math.max(0, r + Math.floor(r * jitter)));
        varG = Math.min(255, Math.max(0, g + Math.floor(g * jitter)));
        varB = Math.min(255, Math.max(0, b + Math.floor(b * jitter)));
      }

      // Gases are mist, not sparkles — blend into the lab background
      if (def.state === "gas" || def.state === "plasma") {
        const bgR = 10, bgG = 10, bgB = 12;
        const alpha = type === 14 ? 0.42 : type === 5 ? 0.5 : 0.62;
        varR = Math.round(varR * alpha + bgR * (1 - alpha));
        varG = Math.round(varG * alpha + bgG * (1 - alpha));
        varB = Math.round(varB * alpha + bgB * (1 - alpha));
      }

      // Apply thermal overlay tinting if enabled
      if (overlayMode === "temp_overlay") {
        if (temp > 100) {
          const heatRatio = Math.min(0.7, (temp - 100) / 1000);
          varR = Math.min(255, Math.floor(varR * (1 - heatRatio) + 255 * heatRatio));
          varG = Math.min(255, Math.floor(varG * (1 - heatRatio) + 120 * heatRatio));
          varB = Math.floor(varB * (1 - heatRatio));
        } else if (temp < -10) {
          const coldRatio = Math.min(0.6, Math.abs(temp + 10) / 150);
          varB = Math.min(255, Math.floor(varB * (1 - coldRatio) + 255 * coldRatio));
          varG = Math.min(255, Math.floor(varG * (1 - coldRatio) + 200 * coldRatio));
        }
      }

      if (type === 48) {
        const d = (e.gridLife[i] || 0) % 4;
        if (d === 0) {
          varR = 180;
          varG = 200;
          varB = 220;
        } else if (d === 1) {
          varR = 120;
          varG = 150;
          varB = 200;
        } else if (d === 2) {
          varR = 200;
          varG = 140;
          varB = 120;
        } else {
          varR = 220;
          varG = 220;
          varB = 180;
        }
      }

      data32[i] = (255 << 24) | (varB << 16) | (varG << 8) | varR;
    }
  }

  ctx.putImageData(e.imageData, 0, 0);
}

/** Scaled PNG data URL of the current grid ("" in non-DOM environments). */
export function captureThumbnail(e: PowderCtx, maxW: number = 320): string {
  try {
    if (typeof document === "undefined") return "";
    const canvas = document.createElement("canvas");
    canvas.width = e.width;
    canvas.height = e.height;
    const ctx = canvas.getContext("2d");
    if (!ctx) return "";
    renderToCanvas(e, ctx, "normal");
    if (e.width > maxW) {
      const scale = maxW / e.width;
      const out = document.createElement("canvas");
      out.width = maxW;
      out.height = Math.round(e.height * scale);
      const octx = out.getContext("2d");
      if (!octx) return canvas.toDataURL("image/png");
      octx.imageSmoothingEnabled = false;
      octx.drawImage(canvas, 0, 0, out.width, out.height);
      return out.toDataURL("image/png");
    }
    return canvas.toDataURL("image/png");
  } catch {
    return "";
  }
}
