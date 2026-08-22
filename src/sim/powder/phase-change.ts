import type { PowderCtx } from "./context";

/** Is there a specific element within `radius` cells? */
export function hasTypeNear(e: PowderCtx, x: number, y: number, typeId: number, radius: number): boolean {
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (!e.isValid(nx, ny)) continue;
      if (e.gridType[e.getIndex(nx, ny)] === typeId) return true;
    }
  }
  return false;
}

/** Is there a hot source (fire / lava / glowing obsidian) within `radius` cells? */
export function hasHotNear(e: PowderCtx, x: number, y: number, radius: number): boolean {
  for (let dy = -radius; dy <= radius; dy++) {
    for (let dx = -radius; dx <= radius; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx;
      const ny = y + dy;
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const t = e.gridType[nIdx];
      if (t === 6 || t === 4 || t === 32) return true;
      if ((t === 46 || t === 7) && e.gridTemp[nIdx] > 280) return true;
    }
  }
  return false;
}

/**
 * Phase changes: boil, freeze, melt, condense, solidify.
 * Returns true when the cell changed phase (movement for this tick is skipped).
 */
export function updatePhase(e: PowderCtx, x: number, y: number, idx: number, type: number): boolean {
  const temp = e.gridTemp[idx];
  const nearLava = type === 2 || type === 27 || type === 14
    ? hasHotNear(e, x, y, 1)
    : false;

  // Water / salt water boils into steam
  if ((type === 2 || type === 27) && (temp >= 100 || (nearLava && hasTypeNear(e, x, y, 6, 1)))) {
    e.setElementAt(x, y, 14, Math.max(120, temp), 90);
    e.gridVy[idx] = -2;
    return true;
  }

  // Ice melts
  if (type === 13 && temp > 0) {
    e.setElementAt(x, y, 2, Math.max(1, temp));
    return true;
  }

  // Snow melts
  if (type === 38 && temp > 0) {
    e.setElementAt(x, y, 2, Math.max(1, temp));
    return true;
  }

  // Steam cools and rains back as water — not while lava is still next to it
  if (type === 14) {
    e.gridTemp[idx] += (e.ambientTemp - e.gridTemp[idx]) * 0.012;
    if (!nearLava && e.gridTemp[idx] < 85 && Math.random() < 0.045) {
      e.setElementAt(x, y, 2, Math.max(20, e.gridTemp[idx]));
      e.gridVy[idx] = 1;
      return true;
    }
  }

  // Lava cools into obsidian
  if (type === 6 && temp < 700) {
    e.setElementAt(x, y, 46, Math.max(180, temp));
    return true;
  }

  // Obsidian remelts only under extreme heat
  if (type === 46 && temp > 1450) {
    e.setElementAt(x, y, 6, temp);
    return true;
  }

  // Stone melts back into lava
  if (type === 7 && temp > 1250) {
    e.setElementAt(x, y, 6, temp);
    return true;
  }

  // Sand fuses into glass
  if (type === 1 && temp > 1450) {
    e.setElementAt(x, y, 12, temp);
    return true;
  }

  // Wax already handled near fire; heat can also melt it
  if (type === 25 && temp > 65) {
    e.setElementAt(x, y, 34, temp);
    return true;
  }

  return false;
}

/**
 * Lava + water/salt water: water boils, lava loses heat and eventually vitrifies.
 * Returns true when the lava cell was consumed (turned to obsidian).
 */
export function quenchLava(e: PowderCtx, lavaIdx: number, waterIdx: number) {
  const lavaTemp = e.gridTemp[lavaIdx];

  e.gridType[waterIdx] = 14;
  e.gridTemp[waterIdx] = Math.max(130, 80 + lavaTemp * 0.08);
  e.gridLife[waterIdx] = 100;
  e.gridVx[waterIdx] = (Math.random() < 0.5 ? -1 : 1) * (1 + Math.floor(Math.random() * 2));
  e.gridVy[waterIdx] = -4 - Math.floor(Math.random() * 2);
  e.gridVisited[waterIdx] = 1;

  // Lava is a thermal mass — one droplet should not freeze a whole cell
  const cooled = lavaTemp - (55 + Math.random() * 25);
  e.gridTemp[lavaIdx] = cooled;
  if (cooled < 700) {
    e.gridType[lavaIdx] = 46; // Obsidian
    e.gridTemp[lavaIdx] = Math.max(180, cooled);
    e.gridLife[lavaIdx] = 0;
    e.gridVx[lavaIdx] = 0;
    e.gridVy[lavaIdx] = 0;
  }
  e.gridVisited[lavaIdx] = 1;
}
