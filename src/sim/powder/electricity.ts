import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

/** Water-like elements that lightning seeks out. */
export function isWet(type: number): boolean {
  return type === 2 || type === 27 || type === 44 || type === 9;
}

/**
 * Flood-fill size of the conductor network (wire / copper / salt water)
 * connected to (x, y), capped at 80 cells.
 */
export function conductorLoad(e: PowderCtx, x: number, y: number): number {
  const seen = new Set<number>();
  const q = [e.getIndex(x, y)];
  let n = 0;
  while (q.length && n < 80) {
    const i = q.pop()!;
    if (seen.has(i)) continue;
    seen.add(i);
    const t = e.gridType[i];
    if (t !== 17 && t !== 47 && t !== 44) continue;
    n++;
    const cx = i % e.width;
    const cy = (i / e.width) | 0;
    for (const [dx, dy] of [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ] as const) {
      const nx = cx + dx;
      const ny = cy + dy;
      if (!e.isValid(nx, ny)) continue;
      q.push(e.getIndex(nx, ny));
    }
  }
  return n;
}

/** Explosive material within a 5×5 window? */
export function wireHasBoom(e: PowderCtx, x: number, y: number): boolean {
  for (let dy = -2; dy <= 2; dy++) {
    for (let dx = -2; dx <= 2; dx++) {
      if (!e.isValid(x + dx, y + dy)) continue;
      const t = e.gridType[e.getIndex(x + dx, y + dy)];
      if (t === 15 || t === 10 || t === 28 || t === 43) return true;
    }
  }
  return false;
}

/**
 * Lightning that seeks wet, then burns: steer a spark (16) toward the
 * highest-value nearby target (water > flammable > conductor) and resolve
 * the contact.
 *
 * Returns true when the spark was consumed.
 */
export function steerSpark(e: PowderCtx, x: number, y: number, idx: number): boolean {
  let bestX = x;
  let bestY = y;
  let best = -1;
  const R = 5;
  for (let dy = -R; dy <= R; dy++) {
    for (let dx = -R; dx <= R; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (!e.isValid(nx, ny)) continue;
      const nType = e.gridType[e.getIndex(nx, ny)];
      if (nType === EMPTY_ELEMENT_ID || nType === 16 || nType === 29) continue;
      const dist = Math.abs(dx) + Math.abs(dy);
      const nDef = e.registry.getElement(nType);
      let score = 0;
      if (isWet(nType)) score = 90 - dist * 8;
      else if (nDef.isConductor || nType === 17 || nType === 47) score = 55 - dist * 5;
      else if (nDef.flammability && nDef.flammability > 20) score = 70 - dist * 6;
      if (score > best) {
        best = score;
        bestX = nx;
        bestY = ny;
      }
    }
  }

  const neighbors = [
    [x + 1, y],
    [x - 1, y],
    [x, y + 1],
    [x, y - 1],
    [x + 1, y + 1],
    [x + 1, y - 1],
    [x - 1, y + 1],
    [x - 1, y - 1],
  ];

  const stepX = Math.sign(bestX - x);
  const stepY = Math.sign(bestY - y);
  const prefer = [
    [x + stepX, y + stepY],
    [x + stepX, y],
    [x, y + stepY],
    ...neighbors,
  ];

  for (const [nx, ny] of prefer) {
    if (!e.isValid(nx, ny) || (nx === x && ny === y)) continue;
    const nIdx = e.getIndex(nx, ny);
    const nType = e.gridType[nIdx];
    const nDef = e.registry.getElement(nType);

    if (isWet(nType)) {
      e.gridTemp[nIdx] = Math.max(e.gridTemp[nIdx], 140);
      if (nType === 2 || nType === 27) {
        e.setElementAt(nx, ny, 14, 130, 70);
        e.gridVy[nIdx] = -2;
      }
      e.setElementAt(x, y, 16, 1000, Math.max(4, e.gridLife[idx]));
      if (e.isValid(nx + stepX, ny + stepY)) {
        const fIdx = e.getIndex(nx + stepX, ny + stepY);
        if (e.gridType[fIdx] === EMPTY_ELEMENT_ID) {
          e.setElementAt(nx + stepX, ny + stepY, 16, 1000, 8);
          e.gridVisited[fIdx] = 1;
        }
      }
      return false;
    }

    if (nDef.flammability && nDef.flammability > 15 && nType !== 17 && nType !== 47) {
      if (nType === 10 || nType === 15 || nType === 28 || nType === 43) {
        e.triggerExplosion(nx, ny, nType === 15 ? 18 : 14, 18, 2500);
      } else {
        e.setElementAt(nx, ny, 4, 700, 28);
      }
      e.setElementAt(x, y, 4, 500, 8);
      return true;
    }

    if (nDef.isConductor || nType === 17 || nType === 47) {
      const load = conductorLoad(e, nx, ny);
      e.gridTemp[nIdx] = Math.max(e.gridTemp[nIdx], 900 + load * 12);
      if (load > 16 && Math.random() < 0.12) {
        e.setElementAt(nx, ny, 4, 800, 18);
        e.setElementAt(x, y, 4, 500, 8);
        return true;
      }
      if (wireHasBoom(e, nx, ny)) {
        e.triggerExplosion(nx, ny, 12 + Math.min(10, load), 16, 2200);
        return true;
      }
      const hop = [
        [nx + stepX, ny + stepY],
        [nx + 1, ny],
        [nx - 1, ny],
        [nx, ny + 1],
        [nx, ny - 1],
      ];
      for (const [tx, ty] of hop) {
        if (!e.isValid(tx, ty) || (tx === x && ty === y)) continue;
        const tIdx = e.getIndex(tx, ty);
        const tType = e.gridType[tIdx];
        if (tType === EMPTY_ELEMENT_ID) {
          e.setElementAt(tx, ty, 16, 1000, 8);
          e.gridVisited[tIdx] = 1;
          break;
        }
      }
    }

    if (nType === EMPTY_ELEMENT_ID && best > 0) {
      e.swapCells(idx, nIdx);
      e.gridLife[nIdx] = Math.max(e.gridLife[nIdx], 8);
      return true;
    }
  }
  return false;
}
