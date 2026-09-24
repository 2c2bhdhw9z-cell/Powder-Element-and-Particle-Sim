import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { ParticleEngine } from "@/sim/particle-engine";
import type { ParticleObject } from "@/sim/types";
import { mulberry32 } from "./helpers";

/**
 * Golden scenarios for the particle field, shared with the native port.
 *
 * Same method as `golden-powder.spec.ts`: run a scene in this engine, record every
 * body's final state and the exact number of random draws consumed, and require the
 * native engine to reproduce it. Hand-written expectations could only prove the port
 * matches what someone assumed; these prove it matches what actually happens.
 *
 * ## Why the draw count is recorded
 *
 * It is as valuable as the positions. Two implementations can produce a similar-looking
 * scene while consuming a different number of random numbers, and that difference means
 * their streams have separated — they will diverge completely on some later scene, for a
 * reason that would then be very hard to find. Comparing the count catches it at the
 * source.
 *
 * ## Why this can be exact, where a physics comparison usually cannot
 *
 * These scenes are orbits and springs, where a difference in the last bit of a position
 * doubles every few steps. Comparing them exactly is only possible because the native
 * engine computes its own sine and cosine rather than calling the platform's library;
 * see `native/Sources/CrucibleCore/Support/FDLibm.swift`. Without that, this file would
 * need a tolerance, and a tolerance cannot tell a porting mistake from a last-bit
 * difference that grew.
 *
 * ## Determinism
 *
 * Two sources of non-determinism are removed rather than tolerated:
 *
 *   - `Math.random` is replaced by the simulation's own seeded generator.
 *   - `performance.now()`, which painter mode reads to pick a hue, is passed in
 *     explicitly as `now`.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle
 * ```
 *
 * Without that variable this file *asserts* against the committed fixture instead, so it
 * also guards the web engine against drifting unnoticed.
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-particle-golden.json"
);

const SEED = 1234;

/** Every preset, named so the native side can invoke the same one. */
type PresetName =
  | "burst"
  | "galaxy"
  | "waterfall"
  | "shockwave"
  | "blackHole"
  | "doubleVortex"
  | "repulsor"
  | "solarFlare"
  | "quantumLattice"
  | "dnaHelix"
  | "cosmicFountain"
  | "synchrotron"
  | "pour"
  | "flock"
  | "nbody"
  | "cloth"
  | "rope"
  | "blob"
  | "batch"
  | "well";

/**
 * Settings applied after the preset has built the scene.
 *
 * After, deliberately: most presets set gravity and some set the vortex, so applying
 * these first would have them silently overwritten and the scenario would not be testing
 * what it claims to.
 */
interface Overrides {
  gravityX?: number;
  gravityY?: number;
  damping?: number;
  elasticity?: number;
  electrostaticFactor?: number;
  vortexForce?: number;
  maxSpeed?: number;
  boundaryMode?: "bounce" | "wrap" | "void";
  mouseMode?:
    | "attract"
    | "repel"
    | "vortex"
    | "emitter"
    | "painter"
    | "gravity_well"
    | "freeze"
    | "hawk"
    | "hyper_drive";
  mouseRadius?: number;
  mouseForceMultiplier?: number;
  particleSize?: number;
  maxParticles?: number;
  showTrails?: boolean;
  decaySpeed?: number;
  collisionsEnabled?: boolean;
  fluidEnabled?: boolean;
  flockEnabled?: boolean;
  nbodyEnabled?: boolean;
}

/**
 * A scripted cursor.
 *
 * Held rather than instantaneous, and moving, because that is how the tool is actually
 * used and because a stationary cursor would leave most of the force code unreached.
 */
interface MouseScript {
  x: number;
  y: number;
  /** Added to the position each step, so the cursor sweeps across the scene. */
  dx?: number;
  dy?: number;
  /** Inclusive step range during which the button is held. */
  from?: number;
  to?: number;
}

interface Scenario {
  name: string;
  why: string;
  width: number;
  height: number;
  preset: PresetName;
  /** Arguments to the preset, in declaration order. */
  args?: number[];
  overrides?: Overrides;
  mouse?: MouseScript;
  steps: number;
  /** Frame timestamp for step zero; each step advances by `nowStep`. */
  nowStart?: number;
  nowStep?: number;
  /**
   * Set when the scene is *supposed* to end up empty.
   *
   * Stated per scenario rather than by relaxing the check for everyone, so that a
   * scenario emptying itself by accident is still a failure.
   */
  expectEmpty?: boolean;
}

const SCENARIOS: Scenario[] = [
  {
    name: "burst-settles-under-gravity",
    why:
      "The simplest scene: a hundred bodies thrown from one point, then gravity, air " +
      "friction and the bouncing walls. No attractors and no springs, so a failure here " +
      "is in the integrator itself and nowhere else.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [100],
    steps: 120,
  },
  {
    name: "burst-charges-repel",
    why:
      "The same burst with the electrostatic force turned up hard. Under 300 bodies the " +
      "engine switches to comparing every pair, so this exercises that whole path, " +
      "including the rule that a pinned body is pushed by charge but never moved.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [80],
    overrides: { electrostaticFactor: 900, gravityY: 0 },
    steps: 100,
  },
  {
    name: "galaxy-orbits-hold",
    why:
      "A black hole with 300 bodies in Keplerian orbit. The most sensitive scenario in " +
      "the set: orbital motion amplifies any arithmetic difference, so if sine and " +
      "cosine were even one bit apart between the engines this is where it would show.",
    width: 500,
    height: 400,
    preset: "galaxy",
    args: [300],
    steps: 200,
  },
  {
    name: "galaxy-event-horizon-reemission",
    why:
      "A tight world, so bodies fall into the hole and are re-emitted — either into a " +
      "fresh orbit or, one time in seven, as a jet. That branch draws from the random " +
      "stream, so it pins down both the re-emission maths and the draw accounting.",
    width: 260,
    height: 220,
    preset: "galaxy",
    args: [200],
    steps: 240,
  },
  {
    name: "waterfall-recycles-at-the-floor",
    why:
      "Bodies that reach the floor are teleported back to the top with fresh random " +
      "velocity. Three draws per recycled body per frame, so the counts only agree if " +
      "the recycle condition triggers on exactly the same bodies on the same frames.",
    width: 320,
    height: 400,
    preset: "waterfall",
    args: [250],
    steps: 160,
  },
  {
    name: "shockwave-expands-and-bounces",
    why:
      "A ring driven outward into the walls simultaneously. Every body hits a boundary " +
      "on nearly the same frame, which is the worst case for the bounce code.",
    width: 400,
    height: 400,
    preset: "shockwave",
    args: [300],
    steps: 90,
  },
  {
    name: "blackhole-with-wrapping-edges",
    why:
      "Wrapping boundaries combined with an attractor. Wrapping is a true modulo rather " +
      "than a single correction, which matters exactly here: near a black hole bodies " +
      "can move more than a world-width in one frame.",
    width: 300,
    height: 300,
    preset: "blackHole",
    args: [250],
    overrides: { boundaryMode: "wrap" },
    steps: 180,
  },
  {
    name: "double-vortex-two-attractors",
    why:
      "Two black holes, with bodies assigned alternately and given opposite spin. " +
      "Confirms attractors are accumulated rather than the nearest one winning.",
    width: 480,
    height: 320,
    preset: "doubleVortex",
    args: [300],
    steps: 150,
  },
  {
    name: "repulsor-pushes-outward",
    why: "The repulsor branch, which is the only one that subtracts its force.",
    width: 400,
    height: 400,
    preset: "repulsor",
    steps: 120,
  },
  {
    name: "solar-flare-lifespans-recycle",
    why:
      "Every body has a lifespan and an origin, so they expire and are reborn " +
      "continuously. Each rebirth draws twice, and the origin sits mid-world so it takes " +
      "the ordinary rebirth path rather than the fountain one.",
    width: 400,
    height: 400,
    preset: "solarFlare",
    args: [350],
    steps: 260,
  },
  {
    name: "cosmic-fountain-rebirth-at-the-floor",
    why:
      "The other rebirth path: an origin within 50 of the floor is treated as a fountain " +
      "and gets a different, upward velocity drawn from three more numbers. Both paths " +
      "have to be covered or half the rebirth code is untested.",
    width: 360,
    height: 420,
    preset: "cosmicFountain",
    args: [250],
    steps: 240,
  },
  {
    name: "quantum-lattice-holds-its-shape",
    why:
      "The only preset with a restoring pull toward each body's origin. Also the " +
      "regression guard for that pull being gated on an explicit flag: it used to be " +
      "inferred from having an origin, ignoring gravity and being charged, which also " +
      "described seven orbital presets and crushed them inward.",
    width: 400,
    height: 300,
    preset: "quantumLattice",
    args: [12, 16],
    steps: 120,
  },
  {
    name: "dna-helix-wraps-and-undulates",
    why:
      "The helix wave and its horizontal wrap. Guards the strand being an explicit " +
      "property rather than inferred from the body's colour — which broke permanently " +
      "the moment any tool repainted it.",
    width: 480,
    height: 300,
    preset: "dnaHelix",
    args: [140],
    steps: 200,
  },
  {
    name: "dna-helix-repainted-stays-in-the-helix",
    why:
      "The same helix with the painter held over it, which recolours every body under " +
      "the cursor. Before the strand became a property this silently dropped repainted " +
      "bodies out of the wave for good, so this scenario is the regression itself.",
    width: 480,
    height: 300,
    preset: "dnaHelix",
    args: [120],
    overrides: { mouseMode: "painter", mouseRadius: 400 },
    mouse: { x: 100, y: 150, dx: 2, dy: 0 },
    steps: 140,
    nowStart: 1234.5,
    nowStep: 16.666666666666668,
  },
  {
    name: "synchrotron-between-two-wells",
    why: "Two offset attractors with a dense ring, which produces frequent close passes.",
    width: 500,
    height: 300,
    preset: "synchrotron",
    args: [300],
    steps: 170,
  },
  {
    name: "pour-fluid-mode",
    why: "Turns on the fluid flag, which no other scenario in this set exercises.",
    width: 300,
    height: 400,
    preset: "pour",
    args: [400],
    steps: 140,
  },
  {
    name: "flock-boids-cohere",
    why:
      "The flocking pass: cohesion, alignment and separation over up to 360 bodies. " +
      "Separation is divided by distance, so closer neighbours push harder — it used to " +
      "accumulate the raw offset, which made avoidance weaker the closer they got.",
    width: 400,
    height: 400,
    preset: "flock",
    args: [220],
    steps: 150,
  },
  {
    name: "nbody-mutual-gravity",
    why: "Mutual attraction between every pair, with no central body to dominate it.",
    width: 400,
    height: 400,
    preset: "nbody",
    args: [240],
    steps: 160,
  },
  {
    name: "cloth-hangs-from-pinned-corners",
    why:
      "A spring lattice with pinned top nodes. Springs index into the body list, so this " +
      "is where an off-by-one in that indexing shows up as a sheared sheet.",
    width: 400,
    height: 400,
    preset: "cloth",
    args: [16, 12],
    steps: 180,
  },
  {
    name: "cloth-on-a-canvas-too-narrow",
    why:
      "A cloth wider than the world, so the computed gap collapses. Guards the rule that " +
      "a rest length of zero does not disable every spring — which it used to, leaving " +
      "the sheet as loose beads.",
    width: 80,
    height: 300,
    preset: "cloth",
    args: [16, 10],
    steps: 120,
  },
  {
    name: "rope-swings-from-a-pin",
    why: "A chain of springs from a single pinned end. The clearest test of spring order.",
    width: 300,
    height: 400,
    preset: "rope",
    args: [32],
    steps: 200,
  },
  {
    name: "blob-holds-volume",
    why:
      "A ring of springs plus long cross-braces, so each body has several springs pulling " +
      "in conflicting directions.",
    width: 300,
    height: 300,
    preset: "blob",
    args: [24],
    steps: 180,
  },
  {
    name: "mouse-attract-sweeps-through",
    why: "The attract force, with the cursor crossing the scene so the falloff is swept.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "attract", mouseRadius: 150 },
    mouse: { x: 40, y: 150, dx: 3, dy: 0 },
    steps: 110,
  },
  {
    name: "mouse-repel-and-release",
    why:
      "Repulsion held for part of the run and then released, so the frames after release " +
      "prove the force stops being applied rather than lingering.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "repel", mouseRadius: 200 },
    mouse: { x: 200, y: 150, from: 0, to: 50 },
    steps: 110,
  },
  {
    name: "mouse-vortex-swirls",
    why: "The vortex force, which is tangential with a small radial component.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "vortex", mouseRadius: 250 },
    mouse: { x: 200, y: 150 },
    steps: 120,
  },
  {
    name: "mouse-gravity-well-swirls-inward",
    why: "The strongest of the cursor forces, and the only other one with a swirl term.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "gravity_well", mouseRadius: 300 },
    mouse: { x: 200, y: 150 },
    steps: 120,
  },
  {
    name: "mouse-freeze-damps",
    why: "Freeze multiplies velocity by 0.7 and applies no force, so it must only slow.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "freeze", mouseRadius: 400 },
    mouse: { x: 200, y: 150 },
    steps: 90,
  },
  {
    name: "mouse-hyper-drive-recolours",
    why:
      "Hyper-drive applies a large fixed push and repaints permanently. The push ignores " +
      "the falloff, which makes it the one mode that can exceed the speed limit and so " +
      "the best test of the clamp.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "hyper_drive", mouseRadius: 500 },
    mouse: { x: 200, y: 150 },
    steps: 80,
  },
  {
    name: "mouse-hawk-pushes-hard",
    why:
      "Hawk repels the bodies but attracts the swarm at more than double force — the one " +
      "mode that means opposite things to the two halves of the field.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [120],
    overrides: { mouseMode: "hawk", mouseRadius: 300 },
    mouse: { x: 200, y: 150 },
    steps: 90,
  },
  {
    name: "mouse-emitter-spawns-continuously",
    why:
      "Emitter adds six bodies per frame at the cursor, each drawing four times. The " +
      "count grows every frame, so this is also the test that the cap evicts the oldest " +
      "through the path that keeps springs valid.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [20],
    overrides: { mouseMode: "emitter", maxParticles: 1000 },
    mouse: { x: 200, y: 100, dx: 1, dy: 1 },
    steps: 140,
  },
  {
    name: "void-boundary-removes-escapees",
    why:
      "Void boundaries delete anything that leaves, shrinking the list mid-tick. Removal " +
      "renumbers every later body, so this is where a stale index would surface.",
    width: 200,
    height: 200,
    preset: "shockwave",
    args: [200],
    overrides: { boundaryMode: "void" },
    steps: 60,
  },
  {
    name: "decay-speed-counts-down",
    why:
      "A global decay rate gives a lifespan to bodies that had none. Stopped partway " +
      "through, so the recorded lifespans show the countdown itself rather than only its " +
      "end state.",
    width: 300,
    height: 300,
    preset: "burst",
    args: [150],
    overrides: { decaySpeed: 4 },
    steps: 18,
  },
  {
    name: "decay-speed-empties-the-field",
    why:
      "The same scene run past the deadline. Without an origin these expire and are " +
      "removed rather than reborn, which is the other half of the lifespan code, and the " +
      "removal happens mid-tick while the force loop is still iterating.",
    width: 300,
    height: 300,
    preset: "burst",
    args: [150],
    overrides: { decaySpeed: 4 },
    steps: 40,
    expectEmpty: true,
  },
  {
    name: "speed-limit-clamps-everything",
    why:
      "A deliberately tiny speed limit. Guards the clamp applying to every body: it used " +
      "to sit inside the branch for orbital bodies, leaving ordinary ones completely " +
      "uncapped despite the interface offering one global limit.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [150],
    overrides: { maxSpeed: 1.5 },
    steps: 100,
  },
  {
    name: "trails-off-above-the-threshold",
    why:
      "Trails are only recorded up to a thousand bodies, and a stale trail is discarded " +
      "the moment recording stops. Trails do not affect physics, so this is checked via " +
      "the recorded trail lengths rather than the positions.",
    width: 400,
    height: 300,
    preset: "burst",
    args: [200],
    overrides: { showTrails: false },
    steps: 60,
  },
  {
    name: "swarm-alone",
    why:
      "A large batch goes to the swarm, which is a separate parallel-friendly store with " +
      "its own integrator and spatial-hash collisions. No object bodies at all, so the " +
      "swarm's tick is isolated.",
    width: 300,
    height: 300,
    preset: "batch",
    args: [20000],
    steps: 60,
  },
  {
    name: "swarm-with-cursor-and-wrapping",
    why:
      "The swarm under an attracting cursor with wrapping edges. The swarm only " +
      "understands pull and push, so every cursor mode has to map onto one or be ignored " +
      "— painter and freeze used to blow it outward instead.",
    width: 300,
    height: 300,
    preset: "batch",
    args: [15000],
    overrides: { boundaryMode: "wrap", mouseMode: "attract", mouseRadius: 200 },
    mouse: { x: 150, y: 150, dx: 1, dy: 1 },
    steps: 80,
  },
  {
    name: "swarm-and-bodies-together",
    why:
      "Both halves of the field at once, sharing one random stream and one set of limits. " +
      "The whole-field cap is why the swarm's budget subtracts the bodies already present.",
    width: 400,
    height: 300,
    preset: "galaxy",
    args: [60],
    steps: 80,
  },
  {
    name: "well-placed-into-a-scene",
    why: "A draggable well added on top of an existing scene, rather than by a preset.",
    width: 400,
    height: 300,
    preset: "well",
    args: [200, 150],
    steps: 100,
  },
];

/**
 * Field order within a recorded body line. Both sides read this same list.
 *
 * Bodies are stored as one space-separated line each rather than as objects. A scene of
 * three hundred bodies written as pretty-printed JSON objects runs to six thousand
 * lines and the whole fixture to several megabytes, most of it repeated field names. One
 * line per body keeps a failing diff pointed at the body that changed, which is the only
 * thing the verbose form was buying.
 *
 * An absent value is written as `-`. Absence is itself behaviour here: whether a body has
 * a lifespan at all decides which branch of the tick it takes, so it cannot be flattened
 * to zero.
 */
const BODY_FIELDS = [
  "x",
  "y",
  "vx",
  "vy",
  "radius",
  "mass",
  "charge",
  "colorUint32",
  "type",
  "fixed",
  "ignoreGravity",
  "latticeBound",
  "lifespan",
  "maxLife",
  "originX",
  "originY",
  "helixStrand",
  "trailLength",
] as const;

interface Result {
  name: string;
  why: string;
  width: number;
  height: number;
  preset: PresetName;
  args: number[];
  overrides: Overrides;
  mouse: MouseScript | null;
  steps: number;
  seed: number;
  nowStart: number;
  nowStep: number;
  /** Settings as they stood when stepping began, after the preset and the overrides. */
  settings: Record<string, number | string | boolean>;
  /** Field order is `BODY_FIELDS`; see there for the format and why. */
  bodyFields: readonly string[];
  bodies: string[];
  /** One spring per line: `a b rest k`. */
  springs: string[];
  /** How many bodies live in the swarm. */
  swarmCount: number;
  /**
   * An evenly spaced sample of the swarm, one line each: `index x y vx vy`.
   *
   * Sampled rather than dumped whole: a twenty-thousand-body swarm would add megabytes
   * to this file for no extra confidence, and an even stride still catches a systematic
   * error anywhere in the buffer.
   */
  swarmSample: string[];
  bodyCount: number;
  /** How many times the engine drew from the random stream. */
  randomDraws: number;
}

/**
 * Rounds for storage without hiding a real difference.
 *
 * Twelve decimal places. Full precision would write seventeen significant digits for
 * every number and make the file unreadable, while twelve is far finer than any
 * divergence a porting mistake produces. The native side rounds identically.
 *
 * A negative zero is normalised to zero, because the two are physically the same here
 * and `String(-0)` drops the sign anyway — better to be deliberate than to have the
 * two sides disagree about a value neither of them means.
 */
function round(value: number): number {
  if (!Number.isFinite(value)) return value;
  const rounded = Math.round(value * 1e12) / 1e12;
  return rounded === 0 ? 0 : rounded;
}

/** One body as a single line, in `BODY_FIELDS` order. */
function recordBody(p: ParticleObject): string {
  const maybe = (value: number | undefined) => (value === undefined ? "-" : String(round(value)));
  return [
    round(p.x),
    round(p.y),
    round(p.vx),
    round(p.vy),
    round(p.radius),
    round(p.mass),
    round(p.charge),
    (p.colorUint32 ?? 0) >>> 0,
    p.type,
    p.fixed ? 1 : 0,
    p.ignoreGravity ? 1 : 0,
    p.latticeBound ? 1 : 0,
    p.lifespan === undefined ? "-" : p.lifespan,
    p.maxLife === undefined ? "-" : p.maxLife,
    maybe(p.originX),
    maybe(p.originY),
    p.helixStrand === undefined ? "-" : p.helixStrand,
    p.trail.length,
  ].join(" ");
}

/** Builds the scene a scenario names. */
function build(engine: ParticleEngine, scenario: Scenario) {
  const a = scenario.args ?? [];
  switch (scenario.preset) {
    case "burst":
      engine.spawnBurst(a[0]);
      break;
    case "galaxy":
      engine.spawnGalaxy(a[0]);
      break;
    case "waterfall":
      engine.spawnWaterfall(a[0]);
      break;
    case "shockwave":
      engine.spawnShockwave(a[0]);
      break;
    case "blackHole":
      engine.spawnBlackHole(a[0]);
      break;
    case "doubleVortex":
      engine.spawnDoubleVortex(a[0]);
      break;
    case "repulsor":
      engine.spawnRepulsor();
      break;
    case "solarFlare":
      engine.spawnSolarFlare(a[0]);
      break;
    case "quantumLattice":
      engine.spawnQuantumLattice(a[0], a[1]);
      break;
    case "dnaHelix":
      engine.spawnDnaHelix(a[0]);
      break;
    case "cosmicFountain":
      engine.spawnCosmicFountain(a[0]);
      break;
    case "synchrotron":
      engine.spawnSynchrotron(a[0]);
      break;
    case "pour":
      engine.spawnPour(a[0]);
      break;
    case "flock":
      engine.spawnFlock(a[0]);
      break;
    case "nbody":
      engine.spawnNbody(a[0]);
      break;
    case "cloth":
      engine.spawnCloth(a[0], a[1]);
      break;
    case "rope":
      engine.spawnRope(a[0]);
      break;
    case "blob":
      engine.spawnBlob(a[0]);
      break;
    case "batch":
      engine.spawnBatch(a[0]);
      break;
    case "well":
      engine.placeWell(a[0], a[1]);
      break;
  }
}

function run(scenario: Scenario): Result {
  // Seed the global generator and count every draw. See the note above on why the
  // count matters as much as the positions.
  let randomDraws = 0;
  const source = mulberry32(SEED);
  const previous = Math.random;
  Math.random = () => {
    randomDraws++;
    return source();
  };

  try {
    const engine = new ParticleEngine(scenario.width, scenario.height);
    build(engine, scenario);

    // After the preset, so a preset cannot silently overwrite the setting the
    // scenario exists to test.
    const overrides = scenario.overrides ?? {};
    Object.assign(engine, overrides);
    // Applied through its setter, which also trims the swarm to fit.
    if (overrides.maxParticles !== undefined) engine.setMaxParticles(overrides.maxParticles);

    const settings: Record<string, number | string | boolean> = {
      gravityX: engine.gravityX,
      gravityY: engine.gravityY,
      damping: engine.damping,
      elasticity: engine.elasticity,
      electrostaticFactor: engine.electrostaticFactor,
      vortexForce: engine.vortexForce,
      maxSpeed: engine.maxSpeed,
      boundaryMode: engine.boundaryMode,
      mouseMode: engine.mouseMode,
      mouseRadius: engine.mouseRadius,
      mouseForceMultiplier: engine.mouseForceMultiplier,
      particleSize: engine.particleSize,
      maxParticles: engine.maxParticles,
      showTrails: engine.showTrails,
      decaySpeed: engine.decaySpeed,
      collisionsEnabled: engine.collisionsEnabled,
      fluidEnabled: engine.fluidEnabled,
      flockEnabled: engine.flockEnabled,
      nbodyEnabled: engine.nbodyEnabled,
    };

    const mouse = scenario.mouse ?? null;
    const nowStart = scenario.nowStart ?? 0;
    const nowStep = scenario.nowStep ?? 0;

    for (let i = 0; i < scenario.steps; i++) {
      const now = nowStart + i * nowStep;
      if (!mouse) {
        engine.step(undefined, undefined, false, now);
        continue;
      }
      const from = mouse.from ?? 0;
      const to = mouse.to ?? scenario.steps - 1;
      const active = i >= from && i <= to;
      engine.step(mouse.x + (mouse.dx ?? 0) * i, mouse.y + (mouse.dy ?? 0) * i, active, now);
    }

    // An even stride through the swarm, capped so the file stays a sane size.
    const swarmSample: string[] = [];
    const n = engine.swarm.n;
    if (n > 0) {
      const take = Math.min(n, 64);
      const stride = Math.max(1, Math.floor(n / take));
      for (let i = 0; i < n && swarmSample.length < take; i += stride) {
        swarmSample.push(
          [
            i,
            round(engine.swarm.xy[i * 2]),
            round(engine.swarm.xy[i * 2 + 1]),
            round(engine.swarm.v[i * 2]),
            round(engine.swarm.v[i * 2 + 1]),
          ].join(" ")
        );
      }
    }

    return {
      name: scenario.name,
      why: scenario.why,
      width: scenario.width,
      height: scenario.height,
      preset: scenario.preset,
      args: scenario.args ?? [],
      overrides,
      mouse,
      steps: scenario.steps,
      seed: SEED,
      nowStart,
      nowStep,
      settings,
      bodyFields: BODY_FIELDS,
      bodies: engine.particles.map(recordBody),
      springs: engine.springs.map((s) => `${s.a} ${s.b} ${round(s.rest)} ${round(s.k)}`),
      swarmCount: n,
      swarmSample,
      bodyCount: engine.bodyCount(),
      randomDraws,
    };
  } finally {
    Math.random = previous;
  }
}

describe("golden particle scenarios", () => {
  const results = SCENARIOS.map(run);

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. " +
              "Regenerate with: cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-particle",
            scenarios: results,
          },
          null,
          2
        ) + "\n"
      );
      expect(results.length).toBe(SCENARIOS.length);
    });
    return;
  }

  it("still matches the committed fixture", () => {
    const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { scenarios: Result[] };
    expect(fixture.scenarios.length).toBe(results.length);
    for (let i = 0; i < results.length; i++) {
      const actual = results[i];
      const expected = fixture.scenarios[i];
      expect(actual.name).toBe(expected.name);
      expect(actual.bodies).toEqual(expected.bodies);
      expect(actual.springs).toEqual(expected.springs);
      expect(actual.swarmCount).toBe(expected.swarmCount);
      expect(actual.swarmSample).toEqual(expected.swarmSample);
      expect(actual.randomDraws).toBe(expected.randomDraws);
    }
  });

  it("every scenario actually simulated something", () => {
    for (let i = 0; i < results.length; i++) {
      const result = results[i];
      if (SCENARIOS[i].expectEmpty) {
        expect(result.bodyCount, `${result.name} was supposed to empty out`).toBe(0);
        continue;
      }
      expect(result.bodyCount, `${result.name} ended up empty`).toBeGreaterThan(0);
    }
    // The set as a whole must lean on the random stream heavily, or comparing draw
    // counts would prove nothing. Individual scenarios may legitimately draw nothing:
    // the helix hands every body an explicit position, velocity, size and colour, so
    // there is nothing left to randomise.
    const totalDraws = results.reduce((sum, r) => sum + r.randomDraws, 0);
    expect(totalDraws).toBeGreaterThan(150_000);
    // And most of them must draw, so the count is not being carried by one scenario.
    expect(results.filter((r) => r.randomDraws > 0).length).toBeGreaterThan(results.length - 4);
  });

  it("covers every preset, boundary rule and cursor mode", () => {
    // Coverage is asserted rather than assumed: a later edit could narrow the set and
    // the native suite would still pass while having stopped testing whole subsystems.
    const presets = new Set(SCENARIOS.map((s) => s.preset));
    expect(presets.size).toBe(20);

    const boundaries = new Set(results.map((r) => r.settings.boundaryMode));
    expect(boundaries).toEqual(new Set(["bounce", "wrap", "void"]));

    const cursorModes = new Set(
      SCENARIOS.filter((s) => s.mouse).map((s) => s.overrides?.mouseMode ?? "attract")
    );
    for (const mode of [
      "attract",
      "repel",
      "vortex",
      "emitter",
      "painter",
      "gravity_well",
      "freeze",
      "hawk",
      "hyper_drive",
    ]) {
      expect(cursorModes.has(mode as never), `no scenario holds the ${mode} cursor`).toBe(true);
    }

    // Springs, the swarm, flocking, mutual gravity and fluid each have to appear.
    expect(results.some((r) => r.springs.length > 0)).toBe(true);
    expect(results.some((r) => r.swarmCount > 0)).toBe(true);
    expect(results.some((r) => r.settings.flockEnabled === true)).toBe(true);
    expect(results.some((r) => r.settings.nbodyEnabled === true)).toBe(true);
    expect(results.some((r) => r.settings.fluidEnabled === true)).toBe(true);
  });
});
