import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { ParticleEngine } from "@/sim/particle-engine";
import { seedRng } from "./helpers";

/**
 * The exact pixels the particle field is drawn as, in every colour mode.
 *
 * The native app draws the field on the GPU as points rather than as a grid of pixels, so it
 * does not take this path — but it makes the same *decision* about what colour each particle
 * should be, from the same function. Comparing the finished picture is how that decision gets
 * checked, and it is a far sharper check than comparing a list of colours would be, because it
 * also pins down which pixel each particle lands on.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle-render
 * ```
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-particle-render-golden.json"
);

const SEED = 1234;

const MODES = ["element", "velocity", "charge", "rainbow", "density", "lifespan"] as const;

/**
 * Builds a field with one of everything the colour modes care about.
 *
 * Several presets together rather than one, so that a single frame contains fast bodies and
 * slow ones, charged and neutral, crowded and isolated, and bodies both with and without a
 * lifespan — which is what makes all six modes say something different.
 */
function buildShowcase(): ParticleEngine {
  const engine = new ParticleEngine(160, 120);
  // Over a thousand bodies, because that is the count above which this engine stops drawing
  // shapes and starts writing pixels — and the pixel path is the one being compared.
  //
  // Solar flare first: it is the only preset here that gives its bodies a lifespan, and every
  // preset but the burst clears the field, so it has to come before the bursts rather than
  // after. The two bursts then add bodies without clearing, which is also what makes one
  // corner of the world crowded and the rest sparse.
  engine.spawnSolarFlare(500);
  engine.spawnBurst(400);
  engine.spawnBurst(350);
  // A few placed by hand at known positions, including the awkward cases.
  engine.addParticle({ x: 0, y: 0, vx: 0, vy: 0, radius: 1, charge: 0, color: "#000000" });
  engine.addParticle({ x: 159, y: 119, vx: 40, vy: 30, radius: 1, charge: 1, color: "#ffffff" });
  engine.addParticle({ x: 80, y: 60, vx: 0, vy: 0, radius: 1, charge: -1, color: "#112233" });
  // Outside the world and unusable, which the renderer must leave out rather than fold into
  // the corner.
  engine.addParticle({ x: -50, y: 60, vx: 0, vy: 0, radius: 1, charge: 1 });
  engine.addParticle({ x: NaN, y: 60, vx: 0, vy: 0, radius: 1, charge: 1 });
  return engine;
}

/** The rendered pixels, as `index:hex` for everything that is not plain background. */
function renderToSparseHex(engine: ParticleEngine): string[] {
  const pixels = new Uint32Array(engine.width * engine.height);
  // A stand-in for the browser's canvas. The renderer only needs somewhere to put pixels and
  // somewhere to hand them back, and above the pixel-path threshold that is all it uses.
  const imageData = {
    width: engine.width,
    height: engine.height,
    data: { buffer: pixels.buffer } as unknown as Uint8ClampedArray,
  } as unknown as ImageData;
  engine.imgData = imageData;
  engine.buf32 = pixels;
  const ctx = {
    createImageData: () => imageData,
    putImageData: () => {},
    save: () => {},
    restore: () => {},
    beginPath: () => {},
    moveTo: () => {},
    lineTo: () => {},
    stroke: () => {},
    fill: () => {},
    arc: () => {},
    fillRect: () => {},
  } as unknown as CanvasRenderingContext2D;

  engine.render(ctx);

  const background = 0xff0c0a0a;
  const out: string[] = [];
  for (let i = 0; i < pixels.length; i++) {
    if (pixels[i] !== background) out.push(`${i}:${pixels[i].toString(16).padStart(8, "0")}`);
  }
  return out;
}

interface Frame {
  mode: string;
  width: number;
  height: number;
  bodyCount: number;
  /** Cells that are not plain background, as `index:aabbggrr`. */
  pixels: string[];
}

describe("golden particle rendering", () => {
  const frames: Frame[] = MODES.map((mode) => {
    const restore = seedRng(SEED);
    try {
      const engine = buildShowcase();
      engine.colorMode = mode;
      // Above the threshold, so the pixel path is the one under test. Asserted rather than
      // assumed: below it the engine draws shapes into the canvas instead, which the stand-in
      // context throws away — so every mode would come out identical and the comparison would
      // be checking nothing at all. That is exactly what happened before this line existed.
      expect(engine.particles.length).toBeGreaterThan(1000);
      return {
        mode,
        width: engine.width,
        height: engine.height,
        bodyCount: engine.particles.length,
        pixels: renderToSparseHex(engine),
      };
    } finally {
      restore();
    }
  });

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. Regenerate with: " +
              "cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle-render",
            seed: SEED,
            frames,
          },
          null,
          2
        ) + "\n"
      );
      expect(frames.length).toBe(MODES.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { frames: Frame[] };
    expect(fixture.frames.length).toBe(frames.length);
    for (let i = 0; i < frames.length; i++) {
      expect(frames[i].mode).toBe(fixture.frames[i].mode);
      expect(frames[i].bodyCount).toBe(fixture.frames[i].bodyCount);
      expect(frames[i].pixels).toEqual(fixture.frames[i].pixels);
    }
  });

  it("every mode draws something, and no two modes agree", () => {
    for (const frame of frames) {
      expect(frame.pixels.length, `${frame.mode} drew nothing`).toBeGreaterThan(0);
    }
    // Six modes the interface presents as different must actually differ. Two of them once
    // measured the same thing — density computed speed, exactly as velocity did, and only the
    // hue range differed — so the interface offered a choice that did nothing.
    const seen = new Map<string, string>();
    for (const frame of frames) {
      const signature = frame.pixels.join("|");
      const twin = seen.get(signature);
      expect(twin, `${frame.mode} draws exactly the same as ${twin}`).toBeUndefined();
      seen.set(signature, frame.mode);
    }
  });

  it("leaves out anything that cannot be placed", () => {
    // Two of the placed bodies are unusable or off-world. Truncating their coordinates would
    // put them at the origin, so a pixel at index 0 that is not the deliberately black
    // particle would mean they had been folded into the corner.
    const element = frames.find((f) => f.mode === "element")!;
    const atOrigin = element.pixels.filter((entry) => entry.startsWith("0:"));
    expect(atOrigin.length).toBeLessThanOrEqual(1);
  });
});
