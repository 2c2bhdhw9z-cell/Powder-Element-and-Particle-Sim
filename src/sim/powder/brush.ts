import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

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
  if (shape === "fill") {
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

      if (shape === "replace") {
        const currentId = e.gridType[e.getIndex(x, y)];
        if (targetElementId !== undefined && currentId !== targetElementId) continue;
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
}
