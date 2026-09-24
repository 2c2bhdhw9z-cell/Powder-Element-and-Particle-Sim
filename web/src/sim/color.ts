/**
 * Colour parsing, in one place.
 *
 * Both renderers need to turn a colour written as text into numbers, and both grew their
 * own copy of the conversion. The copies then drifted: one was fixed and the other kept a
 * bug that made every fractional hue come out wrong. One implementation, two thin wrappers.
 */

/** A colour as three channels, each `0 ... 255`. */
export interface Rgb {
  r: number;
  g: number;
  b: number;
}

/** White, the documented "I could not read this" answer. */
const UNREADABLE: Rgb = { r: 255, g: 255, b: 255 };

/** Clamps to a whole byte, so no channel can bleed into the next one. */
function toByte(unit: number): number {
  if (!Number.isFinite(unit)) return 0;
  return Math.max(0, Math.min(255, Math.round(unit * 255)));
}

function hueToChannel(p: number, q: number, t: number): number {
  let x = t;
  if (x < 0) x += 1;
  if (x > 1) x -= 1;
  if (x < 1 / 6) return p + (q - p) * 6 * x;
  if (x < 1 / 2) return q;
  if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
  return p;
}

/**
 * Parses `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA` or `hsl(h, s%, l%)`.
 *
 * Anything unreadable comes back white rather than black. Black is a legitimate colour for
 * an element to be, so returning it for a failure makes a broken colour indistinguishable
 * from a deliberate one — and custom elements are loaded from storage without their colour
 * being checked, so this is reachable in ordinary use.
 */
export function parseColorToRgb(colorStr: string): Rgb {
  if (typeof colorStr !== "string") return UNREADABLE;
  const text = colorStr.trim();

  if (text.startsWith("#")) {
    let hex = text.slice(1);
    // Shorthand expands by doubling each digit. Only the three-digit form used to be
    // handled, so a four- or eight-digit colour — which the colour picker and hand-edited
    // save files both produce — was read with its channels shifted.
    if (hex.length === 3 || hex.length === 4) {
      hex = hex
        .split("")
        .map((c) => c + c)
        .join("");
    }
    if (hex.length !== 6 && hex.length !== 8) return UNREADABLE;
    if (!/^[0-9a-fA-F]{6}$/.test(hex.slice(0, 6))) return UNREADABLE;
    return {
      r: parseInt(hex.slice(0, 2), 16),
      g: parseInt(hex.slice(2, 4), 16),
      b: parseInt(hex.slice(4, 6), 16),
    };
  }

  if (text.startsWith("hsl")) {
    // Fraction-aware, and each component clamped into its own range.
    //
    // This used to match `\d+`, which splits a fractional hue in two: "hsl(15.9, 100%,
    // 60%)" produced the four matches 15, 9, 100, 60 — so the hue lost its decimals, the
    // *decimals* were read as the saturation, and the real saturation and lightness shifted
    // one slot along and off the end. A saturation of 9 instead of 1 pushed every channel
    // past its maximum, and rounding that and shifting it left bled into the neighbouring
    // channel's bits. The result was not subtly off: a request for flame orange came back
    // pure white.
    const parts = text.match(/-?\d*\.?\d+/g);
    if (!parts || parts.length < 3) return UNREADABLE;
    const rawH = parseFloat(parts[0]);
    const rawS = parseFloat(parts[1]);
    const rawL = parseFloat(parts[2]);
    if (!Number.isFinite(rawH) || !Number.isFinite(rawS) || !Number.isFinite(rawL)) {
      return UNREADABLE;
    }
    // Hue is an angle, so it wraps; the other two clamp.
    const h = (((rawH % 360) + 360) % 360) / 360;
    const s = Math.max(0, Math.min(1, rawS / 100));
    const l = Math.max(0, Math.min(1, rawL / 100));
    if (s === 0) {
      const flat = toByte(l);
      return { r: flat, g: flat, b: flat };
    }
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p = 2 * l - q;
    return {
      r: toByte(hueToChannel(p, q, h + 1 / 3)),
      g: toByte(hueToChannel(p, q, h)),
      b: toByte(hueToChannel(p, q, h - 1 / 3)),
    };
  }

  return UNREADABLE;
}

/**
 * The same colour packed into one 32-bit word, laid out red, green, blue, alpha in memory.
 *
 * That is what a `Uint32Array` view over `ImageData` expects on a little-endian machine,
 * and it is also the layout Metal's `rgba8Unorm` textures use — so the native renderer can
 * upload the same words without rearranging them.
 */
export function parseColorToUint32(colorStr: string): number {
  const { r, g, b } = parseColorToRgb(colorStr);
  let alpha = 255;
  // An eight-digit hex colour carries its own alpha.
  if (typeof colorStr === "string") {
    const hex = colorStr.trim().replace(/^#/, "");
    if (hex.length === 8) alpha = parseInt(hex.slice(6, 8), 16) & 255;
    else if (hex.length === 4) {
      const nibble = parseInt(hex[3], 16);
      if (Number.isFinite(nibble)) alpha = (nibble << 4) | nibble;
    }
  }
  return ((alpha << 24) | (b << 16) | (g << 8) | r) >>> 0;
}
