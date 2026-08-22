import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { ElementDefinition } from "../types";
import type { PowderCtx } from "./context";

/** Can the cell at (fromIdx) move or swap into (toX, toY)? */
export function tryMoveOrSwap(
  e: PowderCtx,
  fromIdx: number,
  fromX: number,
  fromY: number,
  toX: number,
  toY: number,
  selfDensity: number
): boolean {
  if (!e.isValid(toX, toY)) return false;
  const toIdx = e.getIndex(toX, toY);
  if (e.gridVisited[toIdx]) return false;

  const targetType = e.gridType[toIdx];

  // Move to empty space
  if (targetType === EMPTY_ELEMENT_ID) {
    e.swapCells(fromIdx, toIdx);
    return true;
  }

  // Buoyancy density sorting (Sinking / Floating)
  const targetDef = e.registry.getElement(targetType);
  if (targetDef.state !== "solid_fixed" && targetDef.state !== "special") {
    const gDir = Math.sign(e.gravityY) || 1;
    const moveDirY = Math.sign(toY - fromY);

    const isSinkingWithGravity = moveDirY === gDir && selfDensity > targetDef.density;
    const isFloatingAgainstGravity = moveDirY === -gDir && selfDensity < targetDef.density;

    if ((isSinkingWithGravity || isFloatingAgainstGravity) && Math.random() < (selfDensity < 0 ? 0.95 : 0.78)) {
      e.swapCells(fromIdx, toIdx);
      return true;
    }
  }

  return false;
}

/** Move into a guaranteed-empty neighbor (horizontal fluid leveling). */
export function tryMoveEmpty(e: PowderCtx, fromIdx: number, toX: number, toY: number): boolean {
  if (!e.isValid(toX, toY)) return false;
  const toIdx = e.getIndex(toX, toY);
  if (e.gridVisited[toIdx]) return false;
  if (e.gridType[toIdx] !== EMPTY_ELEMENT_ID) return false;
  e.swapCells(fromIdx, toIdx);
  return true;
}

/**
 * Physical movement for movable solids, liquids, gases, plasma and energy.
 * Returns when the cell moved this tick.
 */
export function updateMovement(e: PowderCtx, x: number, y: number, idx: number, def: ElementDefinition) {
  const gravityFactor = def.gravityFactor !== undefined ? def.gravityFactor : 1;
  if (gravityFactor === 0 && def.state === "solid_fixed") return;

  // 0. High-Velocity Inertial Momentum (Explosion Shockwaves & Kinetic Force)
  const vx = e.gridVx[idx];
  const vy = e.gridVy[idx];

  if (vx !== 0 || vy !== 0) {
    const speed = Math.hypot(vx, vy);

    if (speed > 0.3) {
      const normX = vx / speed;
      const normY = vy / speed;

      let posX = x;
      let posY = y;
      let currentIdx = idx;
      let moved = false;

      const maxSteps = Math.min(Math.round(speed), 8);
      for (let s = 0; s < maxSteps; s++) {
        const nextX = Math.round(posX + normX);
        const nextY = Math.round(posY + normY);

        if (nextX === Math.round(posX) && nextY === Math.round(posY)) {
          posX += normX;
          posY += normY;
          continue;
        }

        if (!e.isValid(nextX, nextY)) {
          e.gridVx[currentIdx] = Math.trunc(-e.gridVx[currentIdx] * 0.4);
          e.gridVy[currentIdx] = Math.trunc(-e.gridVy[currentIdx] * 0.4);
          break;
        }

        const targetIdx = e.getIndex(nextX, nextY);
        const targetType = e.gridType[targetIdx];

        if (targetType === EMPTY_ELEMENT_ID) {
          e.swapCells(currentIdx, targetIdx);
          posX = nextX;
          posY = nextY;
          currentIdx = targetIdx;
          moved = true;
        } else if (targetType === 29) {
          // Bedrock bounce/stop
          e.gridVx[currentIdx] = Math.trunc(-e.gridVx[currentIdx] * 0.3);
          e.gridVy[currentIdx] = Math.trunc(-e.gridVy[currentIdx] * 0.3);
          break;
        } else {
          // Collision with other particles: transfer momentum outwards
          const targetDef = e.registry.getElement(targetType);
          if (targetDef.state !== "solid_fixed") {
            e.gridVx[targetIdx] = Math.trunc(e.gridVx[targetIdx] + vx * 0.6);
            e.gridVy[targetIdx] = Math.trunc(e.gridVy[targetIdx] + vy * 0.6);
          }
          e.gridVx[currentIdx] = Math.trunc(e.gridVx[currentIdx] * 0.3);
          e.gridVy[currentIdx] = Math.trunc(e.gridVy[currentIdx] * 0.3);
          break;
        }
      }

      e.gridVx[currentIdx] = Math.trunc(e.gridVx[currentIdx] * 0.85);
      e.gridVy[currentIdx] = Math.trunc(e.gridVy[currentIdx] * 0.85);

      if (moved) return;
    } else {
      e.gridVx[idx] = 0;
      e.gridVy[idx] = 0;
    }
  }

  const dirY = Math.sign(e.gravityY * gravityFactor) || (def.state === "gas" || def.state === "plasma" ? -1 : 1);

  // Movable Solids (Sand, Gunpowder, Thermite, Anti-Gravity)
  if (def.state === "solid_movable") {
    const belowY = y + dirY;
    if (tryMoveOrSwap(e, idx, x, y, x, belowY, def.density)) return;

    // Slide diagonally
    const leftFirst = Math.random() < 0.5;
    const dx1 = leftFirst ? -1 : 1;
    const dx2 = leftFirst ? 1 : -1;

    if (tryMoveOrSwap(e, idx, x, y, x + dx1, belowY, def.density)) return;
    if (tryMoveOrSwap(e, idx, x, y, x + dx2, belowY, def.density)) return;
  }

  // Liquids (Water, Lava, Magma, Acid, Oil, Nitro, Slime, Honey, Tar)
  if (def.state === "liquid") {
    const belowY = y + dirY;

    // 1. Direct fall down
    if (tryMoveOrSwap(e, idx, x, y, x, belowY, def.density)) return;

    // 2. Diagonal down slide — only if the destination is empty or clearly lighter
    const leftFirst = Math.random() < 0.5;
    const dx1 = leftFirst ? -1 : 1;
    const dx2 = leftFirst ? 1 : -1;

    if (tryMoveOrSwap(e, idx, x, y, x + dx1, belowY, def.density)) return;
    if (tryMoveOrSwap(e, idx, x, y, x + dx2, belowY, def.density)) return;

    // 3. Horizontal fluid leveling. Keep water packed — no 6-cell teleports.
    const viscosity = def.viscosity || 1;
    if (viscosity > 3 && Math.random() < 0.35) return;

    // Cohesion: well-supported liquid (3+ same neighbors) almost never spreads
    let same = 0;
    const n4 = [e.getIndex(x - 1, y), e.getIndex(x + 1, y), e.getIndex(x, y - 1), e.getIndex(x, y + 1)];
    for (const n of n4) {
      if (n >= 0 && n < e.gridType.length && e.gridType[n] === def.id) same++;
    }
    if (same >= 3 && Math.random() < 0.82) return;

    const spread = viscosity <= 1 ? (Math.random() < 0.35 ? 2 : 1) : 1;
    const pHere = e.pressureEnabled ? e.gridP[idx] : 0;
    const extra = pHere > 3 ? 1 : 0;
    for (let s = 1; s <= spread + extra; s++) {
      if (tryMoveEmpty(e, idx, x + dx1 * s, y)) return;
      if (tryMoveEmpty(e, idx, x + dx2 * s, y)) return;
    }
  }

  // Gases & Plasma (Smoke, Steam, Oxygen, Helium, Fire)
  if (def.state === "gas" || def.state === "plasma") {
    if (e.pressureEnabled) {
      let bestX = x;
      let bestY = y;
      let bestP = e.gridP[idx];
      const nbs = [
        [x, y + dirY],
        [x - 1, y],
        [x + 1, y],
        [x, y - dirY],
      ];
      for (const [nx, ny] of nbs) {
        if (!e.isValid(nx, ny)) continue;
        const ni = e.getIndex(nx, ny);
        if (e.gridVisited[ni]) continue;
        const t = e.gridType[ni];
        if (t !== EMPTY_ELEMENT_ID && e.registry.getElement(t).density >= def.density) continue;
        if (e.gridP[ni] < bestP) {
          bestP = e.gridP[ni];
          bestX = nx;
          bestY = ny;
        }
      }
      if (bestX !== x || bestY !== y) {
        if (tryMoveOrSwap(e, idx, x, y, bestX, bestY, def.density)) return;
      }
    }
    const moveY = y + dirY;
    if (tryMoveOrSwap(e, idx, x, y, x, moveY, def.density)) return;

    const leftFirst = Math.random() < 0.5;
    const dx1 = leftFirst ? -1 : 1;
    const dx2 = leftFirst ? 1 : -1;

    if (tryMoveOrSwap(e, idx, x, y, x + dx1, moveY, def.density)) return;
    if (tryMoveOrSwap(e, idx, x, y, x + dx2, moveY, def.density)) return;
    if (tryMoveOrSwap(e, idx, x, y, x + dx1, y, def.density)) return;
    if (tryMoveOrSwap(e, idx, x, y, x + dx2, y, def.density)) return;
  }

  // Energy / Laser Beam Propagation
  if (def.state === "energy" || def.id === 36 || def.name.includes("Laser")) {
    const stepDir = e.gravityY !== 0 ? Math.sign(e.gravityY) : 1;
    for (let dist = 1; dist <= 3; dist++) {
      const ny = y + dist * stepDir;
      if (e.isValid(x, ny)) {
        const nIdx = e.getIndex(x, ny);
        const targetType = e.gridType[nIdx];
        if (targetType === EMPTY_ELEMENT_ID) {
          e.swapCells(idx, nIdx);
          return;
        } else if (targetType !== 29 && targetType !== 36) {
          // Bedrock intact
          e.gridTemp[nIdx] += 400;
          if (targetType === 2 || targetType === 13) {
            e.setElementAt(x, ny, 14); // Water/Ice -> Steam
          } else if (targetType === 1 || targetType === 7) {
            e.setElementAt(x, ny, 6); // Sand/Stone -> Lava
          } else {
            e.setElementAt(x, ny, 4, 150); // Ignite fire
          }
          return;
        }
      }
    }
  }
}
