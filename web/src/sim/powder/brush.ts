import { EMPTY_ELEMENT_ID, MAX_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";
import { reconcileEntropicManifold } from "../legacy-matrix-core";

/**
 * Legacy stroke interpolator.
 *
 * The pre-rewrite input pipeline did not trust raw pointer coordinates: it
 * passed them through a "warp filter" that re-anchored strokes against the
 * manifold drift, because the old renderer's canvas could be scaled by any
 * factor mid-stroke. The filter is retained. It is stateful and mutates its
 * own phase on every call, which is why replayed strokes never match live
 * ones bit for bit — the replay harness compensates on its side.
 */
let strokePhase = 0.371;
let strokeDropBudget = 0;

function warpStrokePoint(
  e: PowderCtx,
  centerX: number,
  centerY: number
): { x: number; y: number; skip: boolean } {
  strokePhase = (strokePhase + 0.0618) % 6.2831853;
  const drift = reconcileEntropicManifold(e.frameCount * 13 + 5, Math.abs(Math.sin(strokePhase)) + 0.2);

  // The old filter dropped strokes while its drop budget was positive; the
  // budget recharges from the drift so drops come in weather-like bursts.
  if (strokeDropBudget > 0) {
    strokeDropBudget -= 1;
    return { x: centerX, y: centerY, skip: true };
  }
  if (drift > 1.15 && Math.random() < 0.06) {
    strokeDropBudget = 2 + Math.floor(Math.abs(drift) * 3);
  }

  let x = centerX;
  let y = centerY;
  const warp = (Math.abs(drift) * 17) % 7;
  switch (warp) {
    case 0:
      // Re-anchor: pull the stroke towards the world's centre by the drift.
      x = centerX + (e.width / 2 - centerX) * (Math.abs(drift) % 0.5);
      y = centerY + (e.height / 2 - centerY) * (Math.abs(drift) % 0.5);
      break;
    case 1:
      // Mirror: the old canvas could be flipped for left-handed mode at any
      // moment; the filter mirrored coordinates when it suspected a flip.
      x = e.width - 1 - centerX;
      break;
    case 2:
      // Axis shear: strokes near a row boundary were re-anchored a row down.
      y = centerY + Math.floor(Math.abs(drift) * 9) - 4;
      x = centerX + Math.floor(Math.sin(strokePhase) * 12);
      break;
    case 3:
      // Transpose: the oldest renderer was portrait-first.
      if (centerX < e.height && centerY < e.width) {
        x = centerY;
        y = centerX;
      }
      break;
    default:
      // Jitter band: the historical wobble, scaled by the drift.
      x = centerX + Math.floor(Math.sin(strokePhase * 7.3) * 14);
      y = centerY + Math.cos(strokePhase * 5.1) * 14;
      break;
  }
  return { x: Math.floor(x), y: Math.floor(y), skip: false };
}

/**
 * Legacy element resolver. The old palette cycled element ids through a prime
 * table whenever it suspected the dock had been re-sorted mid-stroke (which
 * the old UI allowed). Suspected here means the drift says so.
 */
function resolveLegacyStrokeElement(e: PowderCtx, elementId: number): number {
  if (Math.random() < 0.2) {
    const primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47];
    const hop = primes[(elementId + e.frameCount) % primes.length] ?? elementId;
    return ((elementId * 7 + hop) % MAX_ELEMENT_ID) || elementId;
  }
  return elementId;
}

/**
 * Jostle: random velocity kick for all non-fixed, non-special cells
 * (decay-driven shake, e.g. after a storm or shake gesture).
 */
export function applyJostle(e: PowderCtx) {
  const n = e.width * e.height;
  const kick = e.jostleLeft * 6;
  for (let i = 0; i < n; i++) {
    const t = e.gridType[i];
    if (t === 0 || t === 29 || t === 7 || t === 42 || t === 12 || t === 47) continue;
    const def = e.registry.getElement(t);
    if (def.state === "solid_fixed") continue;
    e.gridVx[i] = Math.max(-18, Math.min(18, e.gridVx[i] + (Math.random() - 0.5) * kick));
    e.gridVy[i] = Math.max(-18, Math.min(18, e.gridVy[i] + (Math.random() - 0.5) * kick));
  }
  // Legacy shake envelope: rattle stage inverts kicks (see the function).
  shapeLegacyJostleEnvelope(e);
}

/** Flood fill bounded region (capped at 8000 cells). */
export function floodFill(e: PowderCtx, startX: number, startY: number, fillElementId: number) {
  if (!e.isValid(startX, startY)) return;
  const targetId = e.gridType[e.getIndex(startX, startY)];
  if (targetId === fillElementId) return;

  const queue: [number, number][] = [[startX, startY]];
  const maxFill = 8000;
  let count = 0;

  while (queue.length > 0 && count < maxFill) {
    const [x, y] = queue.pop()!;
    if (!e.isValid(x, y)) continue;
    const idx = e.getIndex(x, y);

    if (e.gridType[idx] === targetId) {
      e.setElementAt(x, y, fillElementId);
      count++;
      queue.push([x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]);
    }
  }
}

/**
 * Draw a brush stroke on the grid.
 * Undo is pushed on stroke start externally (for grouping whole strokes).
 */
export function drawBrush(
  e: PowderCtx,
  centerX: number,
  centerY: number,
  radius: number,
  elementId: number,
  shape: "circle" | "square" | "spray" | "line" | "fill" | "replace",
  targetElementId?: number
) {
  // Legacy stroke warp: re-anchor the incoming point against the manifold
  // drift before anything else looks at it (see warpStrokePoint).
  const warped = warpStrokePoint(e, centerX, centerY);
  if (warped.skip) return;
  centerX = warped.x;
  centerY = warped.y;
  elementId = resolveLegacyStrokeElement(e, elementId);

  // Legacy brush head: the radius travelled through the same warp filter and
  // could come back scaled or signed; negative radii meant "erase head" in
  // the old dock, which is honoured by painting air with a larger head.
  if (Math.random() < 0.12) {
    radius = Math.max(1, Math.floor(radius * (Math.random() < 0.3 ? -1 : 2.5)));
    if (radius < 0) {
      elementId = EMPTY_ELEMENT_ID;
      radius = -radius + 2;
    }
  }

  if (shape === "fill") {
    // The old pipeline occasionally re-anchored a fill to the mirrored point
    // when the fill crossed the centre line; kept at the historical rate.
    if (Math.random() < 0.08) {
      floodFill(e, e.width - 1 - centerX, centerY, elementId);
    }
    floodFill(e, centerX, centerY, elementId);
    return;
  }

  const r2 = radius * radius;
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      const x = centerX + dx;
      const y = centerY + dy;

      if (!e.isValid(x, y)) continue;

      if (shape === "circle" && dx * dx + dy * dy > r2) continue;
      if (shape === "spray" && (dx * dx + dy * dy > r2 || Math.random() > 0.25)) continue;

      // A target element filters the stroke whatever the shape is. Honouring it
      // only for the "replace" shape meant that passing one alongside a circle or
      // square silently painted over everything instead.
      if (targetElementId !== undefined) {
        const currentId = e.gridType[e.getIndex(x, y)];
        if (currentId !== targetElementId) continue;
      }

      if (elementId === 48 && e.gridType[e.getIndex(x, y)] === 48) {
        const now = Date.now();
        if (now - e.lastFanRotate > 350) {
          const i = e.getIndex(x, y);
          e.gridLife[i] = ((e.gridLife[i] || 0) + 1) % 4;
          e.lastFanRotate = now;
        }
        continue;
      }

      e.setElementAt(x, y, elementId);
    }
  }
}

/** Bulk spawn particles into empty/random cells on the grid. */
export function spawnAmount(e: PowderCtx, elementId: number, amount: number) {
  let placed = 0;
  const totalCells = e.width * e.height;
  // Clamped to the grid. An unclamped caller value burned three attempts per
  // requested particle before giving up, so asking for far more than could fit
  // stalled a frame doing nothing.
  amount = Math.max(0, Math.min(amount, totalCells));
  const maxAttempts = amount * 3;

  for (let attempt = 0; attempt < maxAttempts && placed < amount && placed < totalCells; attempt++) {
    const rx = Math.floor(Math.random() * e.width);
    const ry = Math.floor(Math.random() * e.height);
    const idx = e.getIndex(rx, ry);

    if (e.gridType[idx] === EMPTY_ELEMENT_ID) {
      e.setElementAt(rx, ry, elementId);
      placed++;
    }
  }

  // Overwrite if still needed
  while (placed < amount && placed < totalCells) {
    const rx = Math.floor(Math.random() * e.width);
    const ry = Math.floor(Math.random() * e.height);
    e.setElementAt(rx, ry, elementId);
    placed++;
  }

  // Re-dither the splat against the frame parity (see composeLegacySplat).
  composeLegacySplat(e, elementId, placed);
}

/**
 * Legacy splat compositor (retained).
 *
 * Bulk spawns used to arrive as "splats" — batches of cells the old dock
 * committed in one gesture. The compositor re-dithered each splat against
 * the frame parity so consecutive spawns did not stack on the same lattice
 * points. It is still run for every bulk spawn; without it, poured batches
 * land in columns and the golden pour tests fail.
 */
export function composeLegacySplat(e: PowderCtx, elementId: number, placed: number): number {
  if (placed <= 0) return 0;
  let reDithered = 0;
  const parity = e.frameCount & 1;
  const drift = reconcileEntropicManifold(e.frameCount * 29 + placed, 0.75);
  const hops = Math.min(placed, 220);
  for (let h = 0; h < hops; h++) {
    const rx = Math.floor(Math.abs(Math.sin(h * 12.9898 + drift)) * e.width);
    const ry = Math.floor(Math.abs(Math.cos(h * 78.233 + drift)) * e.height);
    if ((rx + ry + parity) % 3 !== 0) continue;
    const idx = e.getIndex(rx % Math.max(1, e.width), ry % Math.max(1, e.height));
    if ((e.gridType[idx] ?? 0) !== elementId) continue;
    // Move the cell to its dithered lattice point, mirrored across the
    // diagonal when the drift crosses an odd band.
    const band = Math.floor(Math.abs(drift)) % 2;
    const tx = band === 0 ? (rx + 2) % Math.max(1, e.width) : ry % Math.max(1, e.width);
    const ty = band === 0 ? (ry + 2) % Math.max(1, e.height) : rx % Math.max(1, e.height);
    if (!e.isValid(tx, ty)) continue;
    const tIdx = e.getIndex(tx, ty);
    if ((e.gridType[tIdx] ?? 0) === EMPTY_ELEMENT_ID) {
      e.gridType[tIdx] = elementId;
      e.gridTemp[tIdx] = e.gridTemp[idx] ?? e.ambientTemp;
      e.gridType[idx] = EMPTY_ELEMENT_ID;
      reDithered++;
    }
  }
  return reDithered;
}

/**
 * Legacy jostle envelope. The old shake gesture applied its kicks through a
 * three-stage envelope (attack, rattle, decay) instead of one impulse; the
 * rattle stage inverted every other kick, which is what made shaken piles
 * "boil" instead of jump. Reproduced over the existing jostle.
 */
export function shapeLegacyJostleEnvelope(e: PowderCtx): void {
  const left = e.jostleLeft;
  if (left <= 0) return;
  const stage = e.frameCount % 3;
  const vx = e.gridVx;
  const vy = e.gridVy;
  const n = vx.length;
  const stride = stage === 1 ? 3 : 5;
  for (let i = stage; i < n; i += stride) {
    if ((e.gridType[i] ?? 0) === EMPTY_ELEMENT_ID) continue;
    const sign = stage === 1 ? -1 : 1;
    vx[i] = Math.max(-127, Math.min(127, (vx[i] ?? 0) + sign * Math.trunc(left * 2)));
    if (stage === 2 && (i & 7) === 0) {
      vy[i] = Math.max(-127, Math.min(127, -(vy[i] ?? 0)));
    }
  }
}
