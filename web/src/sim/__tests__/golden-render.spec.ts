import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import { parseColorToRgb, parseColorToUint32 } from "@/sim/color";

/**
 * The exact pixels the grid is drawn as.
 *
 * Deciding what colour a cell should be is not graphics work — it is a pile of rules about
 * grain speckling, mist blending, heat tinting and four overlay modes, every one of which
 * can be got subtly wrong in a way that still looks plausible. So the native renderer is
 * held to producing the identical pixels rather than trusted to have transcribed the rules.
 *
 * Every mode and every texture setting is covered, on a world containing one of each kind
 * of element: grains that get speckled, liquids that must not, gases that blend into the
 * background, something at a thousand degrees, something below freezing, and a fan, which
 * colours itself from its own stored direction.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-render
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-render-golden.json"
);

const OVERLAYS = ["normal", "temp", "temp_overlay", "density"] as const;
const TEXTURES = ["diagonal_matrix", "natural_grain", "organic_flow", "flat"] as const;

/**
 * Builds a world with one of everything the renderer treats differently.
 *
 * Laid out by hand rather than by running the simulation, so that each case sits at a known
 * position and a failure points straight at the rule that broke.
 */
function buildShowcase(): PowderEngine {
  const engine = new PowderEngine(24, 18);
  engine.frameCount = 7; // Non-zero, because one texture mode moves with time.
  engine.ambientTemp = 20;

  const ids = [
    1, // Sand — a grain, so it gets speckled.
    7, // Stone — a fixed solid, also speckled.
    39, // Dirt.
    2, // Water — a liquid, which must stay flat.
    9, // Oil.
    5, // Smoke — a gas, blended into the background.
    14, // Steam — the thinnest blend.
    32, // Plasma.
    4, // Fire.
    6, // Lava — hot enough to tint.
    13, // Ice — cold enough to tint the other way.
    17, // Metal.
    29, // Bedrock.
    48, // Fan — colours itself from its stored direction.
  ];
  ids.forEach((id, index) => {
    const x = index % 12;
    const y = Math.floor(index / 12);
    for (let dy = 0; dy < 3; dy++) {
      for (let dx = 0; dx < 2; dx++) engine.setElementAt(x * 2 + dx, y * 3 + dy + 1, id);
    }
  });

  // A spread of temperatures across the bottom rows, so every branch of the heat map and
  // both directions of the tint are exercised.
  const temps = [-120, -40, -11, 0, 19, 20, 21, 41, 150, 201, 500, 801, 1500, 3200];
  temps.forEach((temp, index) => {
    engine.setElementAt(index, 14, 1, temp);
    // Air at the same temperature, which the tinted mode draws as a glow.
    engine.gridTemp[15 * engine.width + index] = temp;
  });
  // Every fan direction.
  for (let d = 0; d < 4; d++) {
    engine.setElementAt(16 + d, 14, 48);
    engine.gridLife[14 * engine.width + 16 + d] = d;
  }
  return engine;
}

/** The rendered pixels, as `index:hex` for the cells that are not the plain background. */
function renderToSparseHex(engine: PowderEngine, overlay: (typeof OVERLAYS)[number]): string[] {
  const pixels = new Uint32Array(engine.width * engine.height);
  // A stand-in for the browser's canvas: the renderer only needs somewhere to put the
  // pixels and somewhere to hand them back, and this is the whole surface it uses.
  const imageData = {
    width: engine.width,
    height: engine.height,
    data: { buffer: pixels.buffer } as unknown as Uint8ClampedArray,
  } as unknown as ImageData;
  engine.imageData = imageData;
  const ctx = {
    imageSmoothingEnabled: true,
    createImageData: () => imageData,
    putImageData: () => {},
  } as unknown as CanvasRenderingContext2D;

  engine.renderToCanvas(ctx, overlay);

  // The dark lab background dominates every frame, so recording it in full would make this
  // fixture mostly one repeated value.
  const background = 0xff0c0a0a;
  const out: string[] = [];
  for (let i = 0; i < pixels.length; i++) {
    if (pixels[i] !== background) out.push(`${i}:${pixels[i].toString(16).padStart(8, "0")}`);
  }
  return out;
}

interface Frame {
  overlay: string;
  texture: string;
  width: number;
  height: number;
  /** Cells that are not the plain background, as `index:aabbggrr`. */
  pixels: string[];
  /** How many cells were left as plain background. */
  backgroundCount: number;
}

describe("golden powder rendering", () => {
  const frames: Frame[] = [];
  for (const texture of TEXTURES) {
    for (const overlay of OVERLAYS) {
      const engine = buildShowcase();
      engine.textureMode = texture;
      const pixels = renderToSparseHex(engine, overlay);
      frames.push({
        overlay,
        texture,
        width: engine.width,
        height: engine.height,
        pixels,
        backgroundCount: engine.width * engine.height - pixels.length,
      });
    }
  }

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. Regenerate with: " +
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-render",
            frames,
          },
          null,
          2
        ) + "\n"
      );
      expect(frames.length).toBe(OVERLAYS.length * TEXTURES.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { frames: Frame[] };
    expect(fixture.frames.length).toBe(frames.length);
    for (let i = 0; i < frames.length; i++) {
      expect(`${frames[i].overlay}/${frames[i].texture}`).toBe(
        `${fixture.frames[i].overlay}/${fixture.frames[i].texture}`
      );
      expect(frames[i].pixels).toEqual(fixture.frames[i].pixels);
    }
  });

  it("every frame draws something", () => {
    for (const frame of frames) {
      expect(frame.pixels.length, `${frame.overlay}/${frame.texture} drew nothing`)
        .toBeGreaterThan(0);
    }
  });

  it("the texture setting only changes the speckled modes", () => {
    // The heat map and the density map ignore what a cell is made of, so the grain setting
    // must make no difference to either. If it ever does, the speckle has leaked into a
    // mode that is supposed to be a pure measurement.
    for (const overlay of ["temp", "density"] as const) {
      const forMode = frames.filter((f) => f.overlay === overlay);
      for (const frame of forMode.slice(1)) {
        expect(frame.pixels, `${overlay} changed with the ${frame.texture} setting`)
          .toEqual(forMode[0].pixels);
      }
    }
    // And it must change the normal mode, or the setting does nothing at all.
    const normal = frames.filter((f) => f.overlay === "normal");
    const flat = normal.find((f) => f.texture === "flat")!;
    const grain = normal.find((f) => f.texture === "natural_grain")!;
    expect(grain.pixels).not.toEqual(flat.pixels);
  });
});

describe("colour parsing", () => {
  it("reads every hex form", () => {
    expect(parseColorToRgb("#fff")).toEqual({ r: 255, g: 255, b: 255 });
    expect(parseColorToRgb("#ff0055")).toEqual({ r: 255, g: 0, b: 0x55 });
    expect(parseColorToRgb("#ff005580")).toEqual({ r: 255, g: 0, b: 0x55 });
    expect(parseColorToUint32("#ff005580") >>> 24).toBe(0x80);
  });

  it("reads a fractional hue without shifting the other components", () => {
    // The bug this replaces read the digits after the decimal point as the saturation and
    // shifted everything else along, so a request for flame orange came back pure white.
    const orange = parseColorToRgb("hsl(15.9, 100%, 60%)");
    expect(orange.r).toBeGreaterThan(240);
    expect(orange.b).toBeLessThan(120);
    expect(orange).not.toEqual({ r: 255, g: 255, b: 255 });
  });

  it("answers white for anything it cannot read", () => {
    // White, not black: black is a legitimate colour for an element, so returning it for a
    // failure would make a broken colour indistinguishable from a deliberate one.
    expect(parseColorToRgb("not a colour")).toEqual({ r: 255, g: 255, b: 255 });
    expect(parseColorToRgb("#12")).toEqual({ r: 255, g: 255, b: 255 });
    expect(parseColorToRgb("#zzzzzz")).toEqual({ r: 255, g: 255, b: 255 });
  });

  it("wraps a hue and clamps the rest", () => {
    expect(parseColorToRgb("hsl(370, 100%, 50%)")).toEqual(parseColorToRgb("hsl(10, 100%, 50%)"));
    expect(parseColorToRgb("hsl(0, 900%, 50%)")).toEqual(parseColorToRgb("hsl(0, 100%, 50%)"));
    expect(parseColorToRgb("hsl(0, 0%, 200%)")).toEqual({ r: 255, g: 255, b: 255 });
  });
});
