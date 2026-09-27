/**
 * The four set-piece events: a meteor, a blast, a surge of water, and a deep freeze.
 *
 * ## Why these are here and not in the view
 *
 * They were written inline in `powder-view.tsx`, mixed in with sound calls and screen-shake
 * state. That put a set of world-mutating rules — radii, temperatures, which element replaces
 * which — somewhere no test can reach them, and it is the only reason they were never checked
 * against the native port the way everything else has been.
 *
 * Moving them here changes nothing about what they do. It makes them comparable.
 *
 * ## Sound and shake are described, not performed
 *
 * An event wants to shake the screen and make a noise, and neither belongs to the simulation.
 * So each function *reports* what should accompany the world change and leaves the caller to do
 * it — the same split the engine already uses for explosions via its `onBurst` callback.
 *
 * ## The delayed second half
 *
 * A meteor lands and then detonates a moment later; a blast goes off and is followed by two
 * flanking ones. That delay is what makes them read as events rather than as instant state
 * changes, so the timing is part of the definition and is returned rather than hidden in a
 * `setTimeout` inside a component.
 */

import type { PowderEngine } from "./powder-engine";
import { triggerExplosion } from "./powder/explosion";

export type PowderEventId = "meteor" | "blast" | "surge" | "freeze";

export type PowderEventSound = "meteor" | "explosion";

/** One explosion, as an event schedules it. */
export type PowderEventBlast = {
  x: number;
  y: number;
  radius: number;
  force: number;
  heat: number;
};

/** The second half of an event, to be run after `delayMs`. */
export type PowderEventFollowUp = {
  delayMs: number;
  blasts: PowderEventBlast[];
  shake: number;
  sound: PowderEventSound | null;
  soundIntensity: number;
};

/** What happened immediately, and what is still to come. */
export type PowderEventStart = {
  shake: number;
  sound: PowderEventSound | null;
  soundIntensity: number;
  followUp: PowderEventFollowUp | null;
};

const LAVA = 6;
const FIRE = 4;
const WATER = 2;
const STONE = 7;
const ACID = 8;
const OIL = 9;
const ICE = 13;
const SALT_WATER = 27;
const BEDROCK = 29;
const EMPTY = 0;

/**
 * Runs the immediate half of an event.
 *
 * @returns what should accompany it, including the delayed half if it has one.
 */
export function startPowderEvent(e: PowderEngine, id: PowderEventId): PowderEventStart {
  switch (id) {
    case "meteor":
      return meteor(e);
    case "blast":
      return blast(e);
    case "surge":
      return surge(e);
    case "freeze":
      return freeze(e);
  }
}

/** Runs the delayed half of an event. */
export function finishPowderEvent(e: PowderEngine, followUp: PowderEventFollowUp) {
  for (const b of followUp.blasts) {
    triggerExplosion(e, b.x, b.y, b.radius, b.force, b.heat);
  }
}

/**
 * A ball of lava and fire dropped from above, which detonates when it lands.
 *
 * The explosion is placed at a fixed fraction of the world's height rather than wherever the
 * material actually got to, because the material may not get anywhere — it can land on a
 * ceiling someone built. Deciding the impact point up front means the event always reads the
 * same.
 */
function meteor(e: PowderEngine): PowderEventStart {
  const cx = Math.floor(e.width / 2);
  const radius = 10;
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      // A disc rather than a square, compared without a square root.
      if (dx * dx + dy * dy > radius * radius) continue;
      const x = cx + dx;
      const y = 14 + dy;
      // Checked before the draw below, so that a meteor near the edge of a narrow world
      // consumes exactly as many random numbers as there are cells it can actually fill.
      if (!e.isValid(x, y)) continue;
      e.setElementAt(x, y, Math.random() < 0.8 ? LAVA : FIRE, 2800);
      e.gridVy[e.getIndex(x, y)] = 18;
    }
  }
  return {
    shake: 16,
    sound: "meteor",
    soundIntensity: 1,
    followUp: {
      delayMs: 180,
      blasts: [{ x: cx, y: Math.floor(e.height * 0.65), radius: 28, force: 18, heat: 3000 }],
      shake: 22,
      sound: "explosion",
      soundIntensity: 2,
    },
  };
}

/** One large explosion at the centre, then two flanking it. */
function blast(e: PowderEngine): PowderEventStart {
  const cx = Math.floor(e.width / 2);
  const cy = Math.floor(e.height / 2);
  triggerExplosion(e, cx, cy, 36, 22, 3500);
  return {
    shake: 24,
    sound: "explosion",
    soundIntensity: 3,
    followUp: {
      delayMs: 120,
      blasts: [
        { x: cx - 22, y: cy - 14, radius: 22, force: 16, heat: 2800 },
        { x: cx + 22, y: cy + 14, radius: 22, force: 16, heat: 2800 },
      ],
      shake: 16,
      sound: null,
      soundIntensity: 1,
    },
  };
}

/** A wall of water down the left side, already moving right. */
function surge(e: PowderEngine): PowderEventStart {
  const startY = Math.floor(e.height * 0.28);
  const endX = Math.min(28, e.width - 4);
  for (let y = startY; y < e.height - 2; y++) {
    for (let x = 2; x < endX; x++) {
      e.setElementAt(x, y, WATER, 12);
      e.gridVx[e.getIndex(x, y)] = 14;
    }
  }
  return { shake: 0, sound: null, soundIntensity: 1, followUp: null };
}

/**
 * Chills everything at once: liquids become ice and lava sets to stone.
 *
 * Writes the grid directly rather than going through `setElementAt`, which is deliberate and
 * load-bearing — it leaves each cell's lifetime and momentum alone, so a freeze stops a world
 * without also resetting everything that was moving through it.
 */
function freeze(e: PowderEngine): PowderEventStart {
  for (let i = 0; i < e.gridType.length; i++) {
    const t = e.gridType[i];
    // Air has no temperature worth setting, and bedrock is the world's container.
    if (t === EMPTY || t === BEDROCK) continue;
    e.gridTemp[i] = -200;
    if (t === WATER || t === ACID || t === OIL || t === SALT_WATER) e.gridType[i] = ICE;
    if (t === LAVA) e.gridType[i] = STONE;
  }
  return { shake: 0, sound: null, soundIntensity: 1, followUp: null };
}
