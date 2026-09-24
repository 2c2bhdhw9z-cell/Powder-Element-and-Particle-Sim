import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * Recorded results of `Math.sin`, `Math.cos` and `Math.pow`, for the native port to
 * check itself against.
 *
 * ## Why this exists
 *
 * The native engine does not call the platform's maths library for these three. It
 * carries its own implementations, and this fixture is what proves they are right.
 *
 * The reason it carries its own is not really about matching this file. It is that
 * "the platform's maths library" is not one thing: glibc on the Linux test host,
 * Darwin's on an iPhone, and V8's own bundled copy here all give *different* answers
 * for the same argument — always by one unit in the last place, the smallest
 * representable difference. Measured over four thousand arguments drawn the way the
 * particle presets draw them, glibc disagreed with V8 on 3.3% of sines.
 *
 * One unit in the last place sounds harmless. It is not, because the presets are
 * orbits: a body's position sets the force on it, which sets its next position. A
 * last-bit difference doubles every few steps, so two runs that begin identical end up
 * visibly different. That would mean:
 *
 *   - physics verified on the test machine would not be the physics that ships, since
 *     the phone would be running a third implementation again; and
 *   - a saved or shared scene would replay differently on a different device.
 *
 * So the engine owns the arithmetic, and these are the numbers it is held to. A useful
 * side effect is that the native app's physics is now pinned permanently — Chromium is
 * currently considering moving V8 onto a different maths library, which would change
 * the values below, and cannot change the native app's.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-math
 * ```
 *
 * Do not regenerate casually. Unlike the powder and particle fixtures, which describe
 * this project's own behaviour, this one describes a fixed mathematical fact. If it
 * changes, the host JavaScript engine changed, and the native implementation should be
 * left exactly as it is.
 *
 * ## What the native side asserts
 *
 * Sine and cosine: exact equality, and they pass. V8 uses the same published algorithm
 * the native engine now carries.
 *
 * Powers: agreement to within one unit in the last place, not equality. V8 does not use
 * that algorithm for `Math.pow` — transcribing the algorithm into JavaScript and running
 * it here against `Math.pow` showed the same 4% disagreement, so the gap is V8 being
 * more accurate rather than the native port being wrong. It also cannot affect the
 * simulation: `Math.pow` is called in exactly one place, the explosion falloff, and its
 * result is rounded to a whole number before being stored.
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-math-golden.json"
);

/** The exact 64 bits of a double, as hex. Decimal text would lose the last digit. */
function bits(x: number): string {
  const buffer = new ArrayBuffer(8);
  new Float64Array(buffer)[0] = x;
  return new BigUint64Array(buffer)[0].toString(16).padStart(16, "0");
}

/**
 * The next and previous representable doubles either side of `x`.
 *
 * Stepping by `Number.EPSILON` would not do: that is the gap between 1 and its
 * neighbour, and the gap changes with magnitude, so near a quarter turn of 60 radians
 * it would skip over dozens of representable values — exactly the ones where argument
 * reduction is hardest and an error would hide.
 */
function neighbours(x: number): [number, number] {
  if (!Number.isFinite(x) || x === 0) return [Number.MIN_VALUE, -Number.MIN_VALUE];
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  const raw = view.getBigUint64(0);
  // Away from zero is up in magnitude; the sign bit means the order is reversed for
  // negatives, which is why this works off magnitude and reapplies the sign.
  const up = x > 0 ? raw + 1n : raw - 1n;
  const down = x > 0 ? raw - 1n : raw + 1n;
  view.setBigUint64(0, up);
  const after = view.getFloat64(0);
  view.setBigUint64(0, down);
  return [after, view.getFloat64(0)];
}

/** The generator the simulation itself uses, so the arguments are realistic ones. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Arguments for sine and cosine.
 *
 * Chosen to reach every branch of the argument reduction, not just the common one:
 * below a quarter turn needs no reduction at all, below three quarters is a special
 * case, up to roughly a million reduces arithmetically, and anything larger has to go
 * through the table-driven path. Exact and near-exact multiples of a quarter turn are
 * included deliberately, because they are where reduction loses the most precision and
 * where an error would hide.
 */
function trigArguments(): number[] {
  const random = mulberry32(1234);
  const args: number[] = [];

  // How the presets actually draw angles.
  for (let i = 0; i < 1200; i++) args.push(random() * Math.PI * 2);
  // Negative angles, which several presets produce.
  for (let i = 0; i < 200; i++) args.push(-random() * Math.PI * 2);
  // Angles built from a coordinate, as the helix and the vortex do. A world can be
  // 8192 across, so these reach a few hundred radians.
  for (let i = 0; i < 300; i++) args.push(((random() * 8192) / 120) * Math.PI * 2);
  // Each reduction branch, spread over many orders of magnitude.
  for (let i = 0; i < 200; i++) args.push(random() * 1e3);
  for (let i = 0; i < 200; i++) args.push(random() * 1e6);
  for (let i = 0; i < 200; i++) args.push(random() * 1e9);
  for (let i = 0; i < 100; i++) args.push(random() * 1e18);
  for (let i = 0; i < 100; i++) args.push(random() * 1e100);
  // Quarter turns, and the very next representable value either side of each. These
  // are where argument reduction loses the most precision.
  for (let k = 0; k <= 40; k++) {
    const exact = (k * Math.PI) / 2;
    const [after, before] = neighbours(exact);
    args.push(exact, after, before, -exact);
  }
  // The same treatment for a few large multiples, which take the table-driven path.
  for (const k of [1e3, 1e6, 1e9, 1e15]) {
    const exact = (k * Math.PI) / 2;
    const [after, before] = neighbours(exact);
    args.push(exact, after, before, -exact);
  }
  // Boundaries of the branch tests, and the awkward small values.
  args.push(
    0,
    -0,
    1,
    -1,
    Math.PI / 4,
    Math.PI / 4 + 1e-16,
    0.3,
    0.78125,
    0.281_25,
    2 ** -27,
    2 ** -28,
    2 ** -1000,
    5e-324,
    2 ** 19 * (Math.PI / 2),
    2 ** 20 * (Math.PI / 2),
    2 ** 52,
    2 ** 53,
    123456.789,
    1e8,
    1e300,
    Number.MAX_VALUE,
    Number.MIN_VALUE
  );
  return args;
}

/**
 * Base and exponent pairs for powers.
 *
 * The simulation calls this in exactly one place — the explosion falloff, which raises
 * a value between zero and one to the power 0.8 — so that case is covered densely.
 * The rest is breadth: every documented special case, because those are the ones a
 * hand-written implementation gets wrong.
 */
function powArguments(): [number, number][] {
  const random = mulberry32(9876);
  const args: [number, number][] = [];

  // The explosion falloff, which is the only call site in the engine.
  for (let i = 0; i < 400; i++) args.push([random(), 0.8]);
  args.push([0, 0.8], [1, 0.8]);
  // General pairs.
  for (let i = 0; i < 400; i++) args.push([random() * 10, random() * 4 - 2]);
  for (let i = 0; i < 100; i++) args.push([random() * 1e6, random() * 20 - 10]);
  for (let i = 0; i < 100; i++) args.push([random(), random() * 200 - 100]);
  // Negative bases, with whole, odd, even and fractional exponents.
  for (let i = 0; i < 100; i++) args.push([-random() * 10, Math.floor(random() * 10) - 5]);
  for (let i = 0; i < 50; i++) args.push([-random() * 10, random() * 4 - 2]);
  // Special cases the standard pins down exactly.
  const specials: [number, number][] = [
    [2, 0.5], [10, 3], [0.5, -2], [3, 1 / 3], [2, 2], [2, -1], [2, 1],
    [1.0000001, 1000], [1 - 1e-9, 1e8], [1, Infinity], [-1, Infinity],
    [1, NaN], [NaN, 0], [NaN, 1], [0, 0], [0, -0], [-0, 3], [-0, 2],
    [-0, -3], [0, -1], [0, Infinity], [0, -Infinity], [Infinity, 2],
    [Infinity, -2], [-Infinity, 3], [-Infinity, 2], [-Infinity, -3],
    [2, Infinity], [2, -Infinity], [0.5, Infinity], [0.5, -Infinity],
    [-2, 3], [-2, 2], [-2, 2.5], [-2, 0.5],
    [Number.MAX_VALUE, 2], [Number.MIN_VALUE, 2], [Number.MAX_VALUE, -2],
    [2, 1024], [2, 1023], [2, -1074], [2, -1075], [2, 53], [1e300, 2],
    [1e-300, 2], [2, 26], [2, 27], [2, 49], [2, 50],
  ];
  args.push(...specials);
  return args;
}

describe("golden Math results for the native port", () => {
  const trig = trigArguments().map((x) => `${bits(x)} ${bits(Math.sin(x))} ${bits(Math.cos(x))}`);
  const pow = powArguments().map(
    ([base, exponent]) => `${bits(base)} ${bits(exponent)} ${bits(Math.pow(base, exponent))}`
  );

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Recorded from this JavaScript engine's Math. Do not hand-edit. " +
              "Regenerate with: cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-math. " +
              "Each entry is whitespace-separated IEEE 754 bit patterns in hex: " +
              "trig is 'argument sine cosine', pow is 'base exponent result'.",
            trig,
            pow,
          },
          null,
          2
        ) + "\n"
      );
      expect(trig.length).toBeGreaterThan(2000);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { trig: string[]; pow: string[] };
    expect(trig).toEqual(fixture.trig);
    expect(pow).toEqual(fixture.pow);
  });

  it("covers every branch of the argument reduction", () => {
    // A quarter turn, three quarters, the arithmetic limit, and beyond it. If a later
    // edit narrowed the argument set, the native suite would still pass while having
    // stopped testing the hard paths, so the coverage is asserted rather than assumed.
    const quarterTurn = Math.PI / 4;
    const threeQuarters = (3 * Math.PI) / 4;
    const arithmeticLimit = 2 ** 19 * (Math.PI / 2);
    const magnitudes = trigArguments().map(Math.abs);
    expect(magnitudes.some((x) => x <= quarterTurn)).toBe(true);
    expect(magnitudes.some((x) => x > quarterTurn && x < threeQuarters)).toBe(true);
    expect(magnitudes.some((x) => x >= threeQuarters && x <= arithmeticLimit)).toBe(true);
    expect(magnitudes.some((x) => x > arithmeticLimit && Number.isFinite(x))).toBe(true);
  });
});
