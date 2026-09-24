import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { PowderEngine } from "@/sim/powder-engine";
import type { ElementDefinition } from "@/sim/types";
import { mulberry32 } from "./helpers";

/**
 * Golden scenarios shared with the native port.
 *
 * The native engine (../../../native) is verified tick-for-tick against the
 * output of *this* engine, which is the behavioral specification. Hand-written
 * expectations could only prove the port matches what someone assumed; these
 * prove it matches what actually happens.
 *
 * Every scenario is restricted to sand and bedrock. That is deliberate: neither
 * element appears in any branch of `reactions.ts`, has any declarative
 * interaction, or matches any case in `updatePhase`, and at ambient temperature
 * heat diffusion has nothing to do. So the only subsystem with any effect is
 * movement, and — just as importantly — the only code drawing from the random
 * stream is movement. A scenario involving water would consume draws in
 * `reactions.ts` (the water-spread rule) and the two engines' random streams
 * would drift apart for reasons unrelated to the port's correctness.
 *
 * ## Regenerating
 *
 * ```bash
 * cd web
 * CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder
 * ```
 *
 * Without that variable this file *asserts* against the committed fixture
 * instead, so it also guards against the web engine's own behavior drifting
 * unnoticed. If a deliberate physics change makes it fail, regenerate and the
 * native suite will then show the same diff.
 */

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../native/Tests/CrucibleCoreTests/Fixtures/web-powder-golden.json"
);

const SEED = 1234;

const SAND = 1;
const WATER = 2;
const WOOD = 3;
const FIRE = 4;
const SMOKE = 5;
const LAVA = 6;
const LASER = 36;
const STONE = 7;
const ACID = 8;
const OIL = 9;
const GUNPOWDER = 10;
const PLANT = 11;
const GLASS = 12;
const ICE = 13;
const STEAM = 14;
const C4 = 15;
const SPARK = 16;
const METAL = 17;
const VIRUS = 18;
const VOID = 20;
const CLONE = 21;
const PORTAL_A = 22;
const PORTAL_B = 23;
const BEDROCK = 29;
const HONEY = 34;
const SALT = 37;
const DIRT = 39;
const SEED_ELEMENT = 40;
const MERCURY = 44;
const COPPER = 47;
const FAN = 48;

interface Scenario {
  name: string;
  why: string;
  width: number;
  height: number;
  gravityX?: number;
  gravityY?: number;
  windX?: number;
  ambientTemp?: number;
  pressureEnabled?: boolean;
  heatConductionEnabled?: boolean;
  jostle?: number;
  /** Custom elements registered before the world is built, for declarative rules. */
  customElements?: ElementDefinition[];
  steps: number;
  build: (e: PowderEngine) => void;
}

/** One painted cell, recorded so the native side can reproduce the setup exactly. */
interface PaintedCell {
  x: number;
  y: number;
  id: number;
  temp?: number;
  life?: number;
}

const SCENARIOS: Scenario[] = [
  {
    name: "single-grain-falls",
    why: "One grain, no contention. Pins down fall speed and the resting row.",
    width: 32,
    height: 32,
    steps: 40,
    build: (e) => e.setElementAt(16, 2, SAND),
  },
  {
    name: "column-collapses",
    why:
      "A vertical column. Exercises the bottom-up scan: processed top-down the whole " +
      "column would collapse in a single tick instead of falling at a sane speed.",
    width: 32,
    height: 32,
    steps: 60,
    build: (e) => {
      for (let y = 2; y <= 9; y++) e.setElementAt(16, y, SAND);
    },
  },
  {
    name: "pile-forms-on-floor",
    why:
      "A block of sand onto a bedrock floor. The shape of the resulting pile is decided " +
      "entirely by the diagonal-slide rules and the per-row scan direction flip.",
    width: 48,
    height: 32,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 20; x <= 27; x++) for (let y = 2; y <= 9; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "slides-off-a-shelf",
    why: "Sand landing on a narrow bedrock shelf must shed off both shoulders.",
    width: 40,
    height: 36,
    steps: 100,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 16; x <= 23; x++) e.setElementAt(x, 20, BEDROCK);
      for (let x = 18; x <= 21; x++) for (let y = 4; y <= 11; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "inverted-gravity-sand-rises",
    why: "Gravity up flips the vertical scan to top-down. Sand must pile on the ceiling.",
    width: 32,
    height: 32,
    gravityY: -1,
    steps: 80,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, 0, BEDROCK);
      for (let x = 12; x <= 19; x++) for (let y = 24; y <= 27; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "zero-gravity-sand-still-settles",
    why:
      "With gravity at zero the direction comes from the fallback branch, which sends " +
      "granular solids downward anyway. Guards that fallback.",
    width: 32,
    height: 32,
    gravityY: 0,
    steps: 80,
    build: (e) => {
      for (let x = 14; x <= 17; x++) for (let y = 10; y <= 13; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "no-sideways-drift",
    why:
      "A single grain on a flat floor, run long. The per-row alternating scan direction " +
      "exists to stop exactly this grain from walking sideways forever.",
    width: 64,
    height: 24,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(32, 4, SAND);
    },
  },
  {
    name: "tall-stack-settles",
    why:
      "Enough sand to fill several rows, so cells repeatedly contend for the same space " +
      "and the visited mask is load-bearing.",
    width: 24,
    height: 40,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 19; x++) for (let y = 2; y <= 13; y++) e.setElementAt(x, y, SAND);
    },
  },

  // ---- Chemistry ----------------------------------------------------------
  // From here on every subsystem is in play: heat diffusion, heat pipes,
  // pressure, phase changes and reactions. All of them draw from the random
  // stream, so these scenarios test the whole tick, not just movement.

  {
    name: "water-pools-in-a-basin",
    why:
      "Water levelling out. Exercises viscosity, cohesion and the erosion reaction, " +
      "which draws from the random stream on every water cell every tick.",
    width: 32,
    height: 32,
    steps: 120,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 24, BEDROCK);
      for (let y = 18; y <= 24; y++) {
        e.setElementAt(8, y, BEDROCK);
        e.setElementAt(23, y, BEDROCK);
      }
      for (let x = 12; x <= 19; x++) for (let y = 6; y <= 13; y++) e.setElementAt(x, y, WATER);
    },
  },
  {
    name: "water-erodes-a-sandbank",
    why: "The erosion reaction specifically: flowing water must carve sand and carry it downstream.",
    width: 36,
    height: 32,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 10; x <= 25; x++) for (let y = 22; y <= 30; y++) e.setElementAt(x, y, SAND);
      for (let x = 14; x <= 21; x++) for (let y = 4; y <= 11; y++) e.setElementAt(x, y, WATER);
    },
  },
  {
    name: "lava-cools-into-obsidian",
    why: "Lava losing heat until it crosses the 700C vitrification threshold, with no water involved.",
    width: 32,
    height: 32,
    steps: 200,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 24, BEDROCK);
      for (let x = 12; x <= 19; x++) for (let y = 21; y <= 23; y++) e.setElementAt(x, y, LAVA, 900);
    },
  },
  {
    name: "thin-water-cap-vitrifies-lava",
    why:
      "The hardest fidelity target in the whole port. A shallow water cap over a small lava " +
      "pocket: the water flashes off almost immediately, so the lava must keep shedding heat " +
      "to its steam and obsidian neighbours to cross the threshold. With weaker cooling " +
      "coefficients it stalls near 1100C and oscillates forever. Guards the web fix for bug 2.",
    width: 40,
    height: 40,
    steps: 400,
    build: (e) => {
      const floorY = 30;
      const x0 = 17;
      const x1 = 23;
      for (let x = x0; x <= x1; x++) e.setElementAt(x, floorY, BEDROCK);
      for (let y = floorY - 4; y <= floorY; y++) {
        e.setElementAt(x0, y, BEDROCK);
        e.setElementAt(x1, y, BEDROCK);
      }
      for (let x = x0 + 1; x <= x1 - 1; x++)
        for (let y = floorY - 2; y <= floorY - 1; y++) e.setElementAt(x, y, LAVA, 1300);
      for (let x = x0 + 1; x <= x1 - 1; x++) e.setElementAt(x, floorY - 3, WATER);
    },
  },
  {
    name: "obsidian-crust-never-remelts",
    why:
      "The same geometry run far longer. Once the fight resolves nothing may re-melt: the " +
      "residual steam and condensation loop must settle rather than re-quenching forever.",
    width: 40,
    height: 40,
    steps: 700,
    build: (e) => {
      const floorY = 30;
      const x0 = 17;
      const x1 = 23;
      for (let x = x0; x <= x1; x++) e.setElementAt(x, floorY, BEDROCK);
      for (let y = floorY - 4; y <= floorY; y++) {
        e.setElementAt(x0, y, BEDROCK);
        e.setElementAt(x1, y, BEDROCK);
      }
      for (let x = x0 + 1; x <= x1 - 1; x++)
        for (let y = floorY - 2; y <= floorY - 1; y++) e.setElementAt(x, y, LAVA, 1300);
      for (let x = x0 + 1; x <= x1 - 1; x++) e.setElementAt(x, floorY - 3, WATER);
    },
  },
  {
    name: "fire-spreads-through-wood",
    why: "Ignition by flammability, fire decaying to smoke, and smoke expiring. The core fire loop.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 8; x <= 23; x++) for (let y = 20; y <= 28; y++) e.setElementAt(x, y, WOOD);
      e.setElementAt(15, 19, FIRE, 600, 40);
    },
  },
  {
    name: "ice-melts-and-freezes-water",
    why: "Two directions at once: ice melting above zero, and ice spreading through cold water.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 6; x <= 13; x++) for (let y = 20; y <= 27; y++) e.setElementAt(x, y, ICE, -20);
      for (let x = 18; x <= 25; x++) for (let y = 20; y <= 27; y++) e.setElementAt(x, y, WATER, 2);
      e.setElementAt(10, 18, FIRE, 600, 60);
    },
  },
  {
    name: "acid-dissolves-a-wall",
    why:
      "Acid corrosion, including the resistance roll. Glass is immune, stone resists partly, " +
      "wood not at all, so all three paths through the check are exercised.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 11; x++) e.setElementAt(x, 20, STONE);
      for (let x = 12; x <= 19; x++) e.setElementAt(x, 20, WOOD);
      for (let x = 20; x <= 27; x++) e.setElementAt(x, 20, GLASS);
      for (let x = 4; x <= 27; x++) for (let y = 10; y <= 13; y++) e.setElementAt(x, y, ACID);
    },
  },
  {
    name: "spark-seeks-water-along-wire",
    why:
      "Electricity: the scoring scan, conductor load flood fill, the hop, and water being " +
      "flashed to steam. Also covers the branch that returns without consuming the spark.",
    width: 40,
    height: 32,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 30; x++) e.setElementAt(x, 20, METAL);
      for (let x = 24; x <= 30; x++) e.setElementAt(x, 21, COPPER);
      for (let x = 32; x <= 37; x++) for (let y = 24; y <= 29; y++) e.setElementAt(x, y, WATER);
      e.setElementAt(5, 19, SPARK, 1000, 12);
    },
  },
  {
    name: "c4-detonates",
    why:
      "The explosion path end to end: three blast zones, ballistic embers and the smoke plume. " +
      "By far the heaviest consumer of random numbers, and the draw order is intricate.",
    width: 48,
    height: 48,
    steps: 90,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 18; x <= 29; x++) for (let y = 30; y <= 35; y++) e.setElementAt(x, y, C4);
      for (let x = 10; x <= 37; x++) for (let y = 38; y <= 44; y++) e.setElementAt(x, y, SAND);
      for (let x = 12; x <= 20; x++) e.setElementAt(x, 29, WOOD);
      e.setElementAt(24, 29, FIRE, 900, 30);
    },
  },
  {
    name: "gunpowder-chain-reaction",
    why: "Explosions triggering further explosions, which is where a draw-order error compounds fastest.",
    width: 48,
    height: 40,
    steps: 80,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 6; x <= 41; x++) for (let y = 30; y <= 33; y++) e.setElementAt(x, y, GUNPOWDER);
      e.setElementAt(8, 29, FIRE, 900, 40);
    },
  },
  {
    name: "plants-drink-and-grow",
    why: "Plant growth consuming water, plus seeds germinating on dirt through a declarative rule.",
    width: 32,
    height: 32,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 27; x++) for (let y = 26; y <= 30; y++) e.setElementAt(x, y, DIRT);
      for (let x = 10; x <= 13; x++) e.setElementAt(x, 25, PLANT);
      for (let x = 18; x <= 21; x++) e.setElementAt(x, 24, SEED_ELEMENT);
      for (let x = 6; x <= 25; x++) for (let y = 14; y <= 17; y++) e.setElementAt(x, y, WATER);
    },
  },
  {
    name: "salt-dissolves-into-salt-water",
    why: "The declarative interaction path: salt meeting water becomes nothing and makes the water salty.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 26, BEDROCK);
      for (let y = 18; y <= 26; y++) {
        e.setElementAt(8, y, BEDROCK);
        e.setElementAt(23, y, BEDROCK);
      }
      for (let x = 10; x <= 21; x++) for (let y = 22; y <= 25; y++) e.setElementAt(x, y, WATER);
      for (let x = 12; x <= 19; x++) for (let y = 6; y <= 11; y++) e.setElementAt(x, y, SALT);
    },
  },
  {
    name: "portals-teleport",
    why: "Portal pairing, the random choice of exit, and the search for a free cell beside it.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 6; x <= 11; x++) e.setElementAt(x, 20, BEDROCK);
      e.setElementAt(8, 19, PORTAL_A);
      e.setElementAt(24, 10, PORTAL_B);
      e.setElementAt(26, 10, PORTAL_B);
      for (let x = 7; x <= 9; x++) for (let y = 4; y <= 9; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "fan-drives-smoke",
    why: "Fan rotation from the lifetime slot, the pressure it adds, and the momentum it imparts.",
    width: 40,
    height: 32,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(6, 20, FAN);
      for (let x = 10; x <= 15; x++) for (let y = 18; y <= 22; y++) e.setElementAt(x, y, SMOKE, 150, 400);
    },
  },
  {
    name: "virus-infects-everything",
    why: "Virus spreading through solids, which converts a large region and stresses the reaction loop.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 27; x++) for (let y = 20; y <= 28; y++) e.setElementAt(x, y, WOOD);
      e.setElementAt(15, 19, VIRUS);
    },
  },
  {
    name: "clone-and-void",
    why: "A duplicator feeding a singularity: one creates matter every tick and the other erases it.",
    width: 32,
    height: 32,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(10, 20, CLONE);
      e.setElementAt(10, 19, SAND);
      e.setElementAt(22, 26, VOID);
      for (let x = 20; x <= 24; x++) for (let y = 6; y <= 11; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "copper-pipes-heat",
    why: "The heat-pipe pass: copper moving temperature without moving mass, and leaking it into contact.",
    width: 40,
    height: 32,
    steps: 200,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 6; x <= 33; x++) e.setElementAt(x, 20, COPPER);
      for (let x = 6; x <= 9; x++) e.setElementAt(x, 21, LAVA, 1400);
      for (let x = 30; x <= 33; x++) e.setElementAt(x, 21, ICE, -20);
      for (let x = 16; x <= 23; x++) e.setElementAt(x, 21, WATER);
    },
  },
  {
    name: "sealed-steam-pocket-detonates",
    why:
      "Pressure build-up in a sealed container until it lets go. The only path that reaches the " +
      "pressure detonation check, which fires at most once per four ticks.",
    width: 32,
    height: 32,
    steps: 200,
    build: (e) => {
      for (let x = 10; x <= 21; x++) {
        e.setElementAt(x, 14, STONE);
        e.setElementAt(x, 25, STONE);
      }
      for (let y = 14; y <= 25; y++) {
        e.setElementAt(10, y, STONE);
        e.setElementAt(21, y, STONE);
      }
      for (let x = 11; x <= 20; x++) for (let y = 15; y <= 24; y++) e.setElementAt(x, y, STEAM, 400, 5000);
    },
  },
  {
    name: "wind-blows-gases-sideways",
    why: "The wind pass, which is the only place outside movement that relocates cells.",
    width: 40,
    height: 32,
    windX: 3,
    steps: 150,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 9; x++) for (let y = 10; y <= 20; y++) e.setElementAt(x, y, SMOKE, 150, 900);
      for (let x = 4; x <= 9; x++) for (let y = 22; y <= 27; y++) e.setElementAt(x, y, SAND);
    },
  },
  {
    name: "shaken-world-settles",
    why: "The shake gesture: a velocity kick to every loose cell, decaying over the following ticks.",
    width: 32,
    height: 32,
    jostle: 4,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 6; x <= 25; x++) for (let y = 24; y <= 30; y++) e.setElementAt(x, y, SAND);
      for (let x = 10; x <= 21; x++) for (let y = 20; y <= 23; y++) e.setElementAt(x, y, WATER);
    },
  },
  {
    name: "honey-and-oil-and-mercury-stratify",
    why:
      "Three liquids of different density and viscosity in one container. Buoyancy sorting plus " +
      "the viscosity and cohesion gates, all of which draw conditionally.",
    width: 32,
    height: 36,
    steps: 300,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 30, BEDROCK);
      for (let y = 12; y <= 30; y++) {
        e.setElementAt(8, y, BEDROCK);
        e.setElementAt(23, y, BEDROCK);
      }
      for (let x = 9; x <= 22; x++) {
        for (let y = 14; y <= 17; y++) e.setElementAt(x, y, MERCURY);
        for (let y = 18; y <= 21; y++) e.setElementAt(x, y, OIL);
        for (let y = 22; y <= 25; y++) e.setElementAt(x, y, HONEY);
        for (let y = 26; y <= 29; y++) e.setElementAt(x, y, WATER);
      }
    },
  },
  // ---- Regression guards for the bugs fixed after the first port -----------

  {
    name: "laser-stops-at-bedrock",
    why:
      "A beam must not reappear on the far side of a bedrock wall. The loop used to " +
      "continue past bedrock to the next distance instead of stopping.",
    width: 32,
    height: 32,
    steps: 60,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 16, BEDROCK);
      for (let x = 8; x <= 23; x++) for (let y = 20; y <= 24; y++) e.setElementAt(x, y, WOOD);
      for (let x = 12; x <= 19; x++) e.setElementAt(x, 8, LASER, 1500, 400);
    },
  },
  {
    name: "liquid-cannot-cross-a-thin-wall",
    why:
      "Two sealed tanks separated by a one-cell wall. Water used to reach two cells " +
      "sideways without checking the first, so it hopped straight through and drained.",
    width: 40,
    height: 32,
    steps: 300,
    build: (e) => {
      for (let x = 6; x <= 33; x++) e.setElementAt(x, 26, BEDROCK);
      for (let y = 12; y <= 26; y++) {
        e.setElementAt(6, y, BEDROCK);
        e.setElementAt(20, y, BEDROCK);
        e.setElementAt(33, y, BEDROCK);
      }
      for (let x = 7; x <= 19; x++) for (let y = 20; y <= 25; y++) e.setElementAt(x, y, WATER);
    },
  },
  {
    name: "lightning-ignites-oil",
    why:
      "Oil used to be classed as 'wet', so a spark treated the most flammable liquid " +
      "in the game as water and could never set it alight.",
    width: 32,
    height: 28,
    steps: 90,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 14; x <= 27; x++) for (let y = 22; y <= 26; y++) e.setElementAt(x, y, OIL);
      e.setElementAt(10, 22, SPARK, 1000, 30);
    },
  },
  {
    name: "spark-dies-beside-mercury",
    why:
      "Mercury counts as wet but is never converted, and the spark used to re-stamp its " +
      "own lifetime every tick — an immortal spark that also seeded a new one forever.",
    width: 32,
    height: 28,
    steps: 200,
    build: (e) => {
      for (let x = 8; x <= 23; x++) e.setElementAt(x, 24, BEDROCK);
      for (let y = 18; y <= 24; y++) {
        e.setElementAt(8, y, BEDROCK);
        e.setElementAt(23, y, BEDROCK);
      }
      for (let x = 9; x <= 22; x++) for (let y = 22; y <= 23; y++) e.setElementAt(x, y, MERCURY);
      e.setElementAt(15, 21, SPARK, 1000, 12);
    },
  },
  {
    name: "fan-stops-at-a-wall",
    why:
      "A fan blowing into stone used to match neither branch of its loop, so it carried " +
      "on and pressurised cells on the far side of the wall.",
    width: 40,
    height: 28,
    steps: 120,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      e.setElementAt(6, 18, FAN);
      for (let y = 14; y <= 22; y++) e.setElementAt(9, y, STONE);
      for (let x = 11; x <= 16; x++) for (let y = 16; y <= 20; y++) e.setElementAt(x, y, SMOKE, 150, 600);
    },
  },
  {
    name: "explosion-plume-follows-inverted-gravity",
    why: "The smoke plume used to be hardcoded upward, so under inverted gravity it fired into the ground.",
    width: 40,
    height: 40,
    gravityY: -1,
    steps: 60,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, 0, BEDROCK);
      for (let x = 14; x <= 25; x++) for (let y = 6; y <= 10; y++) e.setElementAt(x, y, C4);
      e.setElementAt(20, 11, FIRE, 900, 30);
    },
  },
  {
    name: "custom-rule-spawns-and-heats",
    why:
      "spawnElementId and tempChange are declared on an interaction rule but the original " +
      "never read either, so custom elements could not produce a third element or release " +
      "heat. Also guards that a rule doing nothing no longer freezes the particle.",
    width: 32,
    height: 32,
    steps: 120,
    customElements: [
      {
        id: 50,
        name: "Reactant",
        category: "Custom",
        state: "solid_movable",
        color: "#ff00ff",
        density: 20,
        interactions: [
          {
            targetElementId: WATER,
            chance: 0.5,
            resultSelfId: STEAM,
            spawnElementId: FIRE,
            tempChange: 40,
          },
        ],
      },
      {
        id: 51,
        name: "Inert Rule",
        category: "Custom",
        state: "solid_movable",
        color: "#00ffff",
        density: 20,
        // A rule with no effects at all: must not stop the grain from falling.
        interactions: [{ targetElementId: STONE, chance: 1 }],
      },
    ],
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let x = 4; x <= 15; x++) e.setElementAt(x, 24, WATER);
      for (let x = 6; x <= 13; x++) e.setElementAt(x, 10, 50);
      for (let x = 20; x <= 27; x++) e.setElementAt(x, 28, STONE);
      for (let x = 20; x <= 27; x++) e.setElementAt(x, 10, 51);
    },
  },
  {
    name: "everything-at-once",
    why:
      "A deliberately chaotic world run long, mixing every subsystem. If any single reaction " +
      "draws at the wrong moment, the two engines diverge here even when every focused " +
      "scenario above still agrees.",
    width: 56,
    height: 44,
    steps: 300,
    build: (e) => {
      for (let x = 0; x < e.width; x++) e.setElementAt(x, e.height - 1, BEDROCK);
      for (let y = 0; y < e.height; y++) {
        e.setElementAt(0, y, BEDROCK);
        e.setElementAt(e.width - 1, y, BEDROCK);
      }
      for (let x = 2; x <= 12; x++) for (let y = 36; y <= 42; y++) e.setElementAt(x, y, SAND);
      for (let x = 14; x <= 24; x++) for (let y = 34; y <= 42; y++) e.setElementAt(x, y, WATER);
      for (let x = 26; x <= 32; x++) for (let y = 38; y <= 42; y++) e.setElementAt(x, y, LAVA, 1200);
      for (let x = 34; x <= 42; x++) for (let y = 36; y <= 42; y++) e.setElementAt(x, y, WOOD);
      for (let x = 44; x <= 52; x++) for (let y = 38; y <= 42; y++) e.setElementAt(x, y, OIL);
      for (let x = 6; x <= 20; x++) e.setElementAt(x, 24, METAL);
      e.setElementAt(21, 24, COPPER);
      for (let x = 30; x <= 38; x++) e.setElementAt(x, 22, STONE);
      for (let x = 40; x <= 46; x++) e.setElementAt(x, 22, GLASS);
      for (let x = 8; x <= 14; x++) for (let y = 10; y <= 14; y++) e.setElementAt(x, y, ICE, -20);
      for (let x = 20; x <= 26; x++) for (let y = 8; y <= 12; y++) e.setElementAt(x, y, ACID);
      for (let x = 34; x <= 38; x++) for (let y = 8; y <= 12; y++) e.setElementAt(x, y, GUNPOWDER);
      e.setElementAt(48, 20, FAN);
      e.setElementAt(3, 6, SPARK, 1000, 14);
      e.setElementAt(28, 30, VIRUS);
      e.setElementAt(50, 30, CLONE);
      e.setElementAt(50, 29, SAND);
      for (let x = 42; x <= 46; x++) for (let y = 30; y <= 32; y++) e.setElementAt(x, y, SALT);
      e.setElementAt(16, 30, PORTAL_A);
      e.setElementAt(44, 26, PORTAL_B);
    },
  },
];

interface Result {
  name: string;
  why: string;
  width: number;
  height: number;
  gravityX: number;
  gravityY: number;
  steps: number;
  seed: number;
  windX: number;
  ambientTemp: number;
  pressureEnabled: boolean;
  heatConductionEnabled: boolean;
  jostle: number;
  customElements: ElementDefinition[];
  /** Cells that were painted before stepping. */
  setup: PaintedCell[];
  /**
   * Temperatures after stepping, one comma-separated row per grid row, rounded to
   * two decimals.
   *
   * Included because temperature drives the chemistry: a port could place every
   * element correctly while running hot or cold, and would then diverge later at
   * one of the hard thresholds. Rounded because the grid stores single-precision
   * floats whose full decimal expansion is noise.
   */
  temperatureRows: string[];
  /**
   * Element ids after stepping, one comma-separated string per grid row.
   *
   * Stored row-wise rather than as one flat array so a failing diff points at
   * the row that changed, and so the file stays a manageable size.
   */
  typeRows: string[];
  /**
   * Momentum after stepping, as [index, velocityX, velocityY] for the cells
   * where either is non-zero. Sparse because in these scenarios almost nothing
   * carries momentum, and a full grid of zeroes would dwarf the useful data.
   */
  velocityNonZero: [number, number, number][];
  activeCount: number;
  hashLite: number;
  /** How many times the engine drew from the random stream. */
  randomDraws: number;
  /**
   * The compact multiplayer payload for this world, exactly as it goes on the wire.
   *
   * Recorded so the native port can be held to producing and consuming the identical
   * bytes. That is what lets a player on a phone and a player in a browser share a
   * world: if the two encoders disagree by a single byte, the host's divergence check
   * fires forever and the two worlds never converge.
   */
  liteBase64: string;
}

function toRows(values: Uint16Array, width: number, height: number): string[] {
  const rows: string[] = [];
  for (let y = 0; y < height; y++) {
    rows.push(Array.from(values.subarray(y * width, (y + 1) * width)).join(","));
  }
  return rows;
}

function toTemperatureRows(values: Float32Array, width: number, height: number): string[] {
  const rows: string[] = [];
  for (let y = 0; y < height; y++) {
    const row: string[] = [];
    for (let x = 0; x < width; x++) row.push(values[y * width + x].toFixed(2));
    rows.push(row.join(","));
  }
  return rows;
}

function sparseVelocity(vx: Int8Array, vy: Int8Array): [number, number, number][] {
  const out: [number, number, number][] = [];
  for (let i = 0; i < vx.length; i++) {
    if (vx[i] !== 0 || vy[i] !== 0) out.push([i, vx[i], vy[i]]);
  }
  return out;
}

/** Records the cells a scenario paints, so the native side sets up identically. */
function recordSetup(scenario: Scenario): PaintedCell[] {
  const painted: PaintedCell[] = [];
  const recorder = new PowderEngine(scenario.width, scenario.height);
  for (const custom of scenario.customElements ?? []) recorder.registry.registerElement(custom);
  const original = recorder.setElementAt.bind(recorder);
  recorder.setElementAt = (x: number, y: number, id: number, temp?: number, life?: number) => {
    const cell: PaintedCell = { x, y, id };
    if (temp !== undefined) cell.temp = temp;
    if (life !== undefined) cell.life = life;
    painted.push(cell);
    original(x, y, id, temp, life);
  };
  scenario.build(recorder);
  return painted;
}

function run(scenario: Scenario): Result {
  const setup = recordSetup(scenario);

  // Seed the global generator and count every draw the engine makes. The count
  // is as valuable as the grid: a port that produces the right picture while
  // consuming a different number of random numbers has diverged and will drift
  // apart on some other scenario later.
  let randomDraws = 0;
  const source = mulberry32(SEED);
  const previous = Math.random;
  Math.random = () => {
    randomDraws++;
    return source();
  };

  try {
    const e = new PowderEngine(scenario.width, scenario.height);
    for (const custom of scenario.customElements ?? []) e.registry.registerElement(custom);
    if (scenario.gravityX !== undefined) e.gravityX = scenario.gravityX;
    if (scenario.gravityY !== undefined) e.gravityY = scenario.gravityY;
    if (scenario.windX !== undefined) e.windX = scenario.windX;
    if (scenario.ambientTemp !== undefined) e.ambientTemp = scenario.ambientTemp;
    if (scenario.pressureEnabled !== undefined) e.pressureEnabled = scenario.pressureEnabled;
    if (scenario.heatConductionEnabled !== undefined) e.heatConductionEnabled = scenario.heatConductionEnabled;
    scenario.build(e);
    if (scenario.jostle !== undefined) e.jostle(scenario.jostle);
    for (let i = 0; i < scenario.steps; i++) e.step();

    return {
      name: scenario.name,
      why: scenario.why,
      width: scenario.width,
      height: scenario.height,
      gravityX: e.gravityX,
      gravityY: e.gravityY,
      windX: e.windX,
      ambientTemp: e.ambientTemp,
      pressureEnabled: e.pressureEnabled,
      heatConductionEnabled: e.heatConductionEnabled,
      jostle: scenario.jostle ?? 0,
      customElements: scenario.customElements ?? [],
      steps: scenario.steps,
      seed: SEED,
      setup,
      typeRows: toRows(e.gridType, scenario.width, scenario.height),
      temperatureRows: toTemperatureRows(e.gridTemp, scenario.width, scenario.height),
      velocityNonZero: sparseVelocity(e.gridVx, e.gridVy),
      activeCount: e.getActiveParticleCount(),
      hashLite: e.hashLite(),
      randomDraws,
      liteBase64: (JSON.parse(e.serializeLite()) as { t: string }).t,
    };
  } finally {
    Math.random = previous;
  }
}

describe("golden powder scenarios", () => {
  const results = SCENARIOS.map(run);

  if (process.env.CRUCIBLE_WRITE_GOLDEN === "1") {
    it("writes the fixture consumed by the native test suite", () => {
      writeFileSync(
        FIXTURE,
        JSON.stringify(
          {
            note:
              "Generated from the web engine. Do not hand-edit. " +
              "Regenerate with: cd web && CRUCIBLE_WRITE_GOLDEN=1 npx vitest run golden-powder",
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
      expect(results[i].name).toBe(fixture.scenarios[i].name);
      expect(results[i].typeRows).toEqual(fixture.scenarios[i].typeRows);
      expect(results[i].temperatureRows).toEqual(fixture.scenarios[i].temperatureRows);
      expect(results[i].velocityNonZero).toEqual(fixture.scenarios[i].velocityNonZero);
      expect(results[i].randomDraws).toBe(fixture.scenarios[i].randomDraws);
      expect(results[i].hashLite).toBe(fixture.scenarios[i].hashLite);
      expect(results[i].liteBase64).toBe(fixture.scenarios[i].liteBase64);
    }
  });

  it("every scenario actually simulated something", () => {
    for (const result of results) {
      expect(result.activeCount).toBeGreaterThan(0);
      expect(result.setup.length).toBeGreaterThan(0);
    }
    // Not every scenario needs randomness — a beam meeting a wall is entirely
    // deterministic — but the set as a whole must exercise the random stream
    // heavily, or comparing draw counts would prove nothing.
    const totalDraws = results.reduce((sum, r) => sum + r.randomDraws, 0);
    expect(totalDraws).toBeGreaterThan(500_000);
  });
});
