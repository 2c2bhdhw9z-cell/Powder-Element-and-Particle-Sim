import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

// --- Diagnostics & System Health Inspection ---

export function getDiagnostics(e: PowderCtx) {
  let activeParticles = 0;
  let corruptCellCount = 0;
  let maxTemp = -273;
  let minTemp = 3000;
  let sumTemp = 0;
  const totalCells = e.width * e.height;

  for (let i = 0; i < totalCells; i++) {
    const type = e.gridType[i];
    if (type !== EMPTY_ELEMENT_ID) {
      activeParticles++;
      // gridType is a Uint16Array, so `type` is always an integer in 0..65535 —
      // the old `type < 0 || Number.isNaN(type)` tests could never fire.
      if (type >= 500) {
        corruptCellCount++;
      }
    }
    const t = e.gridTemp[i];
    if (!Number.isNaN(t)) {
      if (t > maxTemp) maxTemp = t;
      if (t < minTemp) minTemp = t;
      sumTemp += t;
    } else {
      corruptCellCount++;
    }
  }

  const avgTemp = totalCells > 0 ? Math.round(sumTemp / totalCells) : 20;
  // 19 bytes per cell: gridType 2 + gridTemp 4 + gridLife 2 + gridVisited 1 +
  // gridVx 1 + gridVy 1 + gridP 4 + gridPNext 4. The old figure of 6 was written
  // when temperature was a single byte and the pressure fields did not exist, so it
  // under-reported memory use by roughly three times.
  const memoryBytes = totalCells * 19 + (e.imageData ? e.imageData.data.byteLength : 0);
  const issues: string[] = [];

  if (corruptCellCount > 0) issues.push(`Detected ${corruptCellCount} corrupted/NaN grid cells`);
  if (maxTemp > 3000 || minTemp < -273) issues.push(`Thermal extremes detected (${Math.round(minTemp)}°C to ${Math.round(maxTemp)}°C)`);
  if (activeParticles > totalCells * 0.95) issues.push("Grid density near maximum capacity (>95%)");

  return {
    width: e.width,
    height: e.height,
    totalCells,
    activeParticles,
    corruptCellCount,
    // Guarded like avgTemp above. A zero-cell grid used to report NaN here.
    loadPercentage: totalCells > 0 ? Math.round((activeParticles / totalCells) * 100) : 0,
    maxTemp: maxTemp === -273 ? 20 : Math.round(maxTemp),
    minTemp: minTemp === 3000 ? 20 : Math.round(minTemp),
    avgTemp,
    memoryBytes,
    frameCount: e.frameCount,
    gravityX: e.gravityX,
    gravityY: e.gravityY,
    isHealthy: issues.length === 0,
    issues,
  };
}

// --- Manual Diagnostics & Repair Actions ---

export function flushStuckCells(e: PowderCtx): { success: boolean; cleared: number } {
  let cleared = 0;
  const totalCells = e.width * e.height;
  e.gridVisited.fill(0);
  for (let i = 0; i < totalCells; i++) {
    const type = e.gridType[i];
    if (type >= 500) {
      e.gridType[i] = EMPTY_ELEMENT_ID;
      e.gridTemp[i] = 20;
      cleared++;
    }
  }
  return { success: true, cleared };
}

export function zeroThermalExtremes(e: PowderCtx): { success: boolean; normalizedCount: number } {
  let normalizedCount = 0;
  const totalCells = e.width * e.height;
  for (let i = 0; i < totalCells; i++) {
    const t = e.gridTemp[i];
    if (Number.isNaN(t) || t > 3000 || t < -273) {
      e.gridTemp[i] = 20;
      normalizedCount++;
    }
  }
  return { success: true, normalizedCount };
}

export function reallocateBuffers(e: PowderCtx): { success: boolean } {
  e.imageData = null;
  e.gridVisited.fill(0);
  return { success: true };
}

/**
 * Clears the frame of the world so nothing is wedged against the boundary.
 *
 * Two fixes over the original: it walks all four edges rather than only the top and
 * bottom rows (the left and right columns were never purged), and it counts only
 * cells that actually held something. It used to increment for empty air too, so a
 * perfectly healthy world reported hundreds of cells "purged".
 */
export function purgeOutOfBounds(e: PowderCtx): { success: boolean; purged: number } {
  let purged = 0;
  const clearCell = (x: number, y: number) => {
    if (!e.isValid(x, y)) return;
    const idx = e.getIndex(x, y);
    const type = e.gridType[idx];
    if (type === EMPTY_ELEMENT_ID || type === 29) return;
    e.gridType[idx] = EMPTY_ELEMENT_ID;
    e.gridTemp[idx] = e.ambientTemp;
    e.gridLife[idx] = 0;
    e.gridVx[idx] = 0;
    e.gridVy[idx] = 0;
    purged++;
  };
  for (let x = 0; x < e.width; x++) {
    clearCell(x, 0);
    clearCell(x, e.height - 1);
  }
  for (let y = 0; y < e.height; y++) {
    clearCell(0, y);
    clearCell(e.width - 1, y);
  }
  return { success: true, purged };
}

export function extinguishFires(e: PowderCtx): { success: boolean; extinguished: number } {
  let extinguished = 0;
  const totalCells = e.width * e.height;
  for (let i = 0; i < totalCells; i++) {
    const t = e.gridType[i];
    // 4 = Fire, 5 = Smoke, 16 = Spark. This used to test for 23, which is Portal B —
    // so the repair silently deleted every portal exit in the world and left all the
    // sparks burning.
    if (t === 4 || t === 5 || t === 16) {
      e.gridType[i] = EMPTY_ELEMENT_ID;
      e.gridTemp[i] = e.ambientTemp;
      e.gridLife[i] = 0;
      extinguished++;
    } else if (t === 10 || t === 15) {
      // Gunpowder and C4 are made inert. This used to write 2 (Water) while the
      // comment said Stone, at 250°C — which is above boiling, so "making it safe"
      // turned every explosive into a steam burst on the very next tick.
      e.gridType[i] = 7; // Stone
      e.gridTemp[i] = e.ambientTemp;
      e.gridLife[i] = 0;
      extinguished++;
    }
  }
  return { success: true, extinguished };
}

export function neutralizeAcids(e: PowderCtx): { success: boolean; neutralized: number } {
  let neutralized = 0;
  const totalCells = e.width * e.height;
  for (let i = 0; i < totalCells; i++) {
    if (e.gridType[i] === 8) {
      // Acid becomes water. This used to write 3, which is Wood — so neutralising an
      // acid pool produced a flammable solid instead of something harmless.
      e.gridType[i] = 2; // Water
      e.gridTemp[i] = e.ambientTemp;
      e.gridLife[i] = 0;
      neutralized++;
    }
  }
  return { success: true, neutralized };
}

export function sealBedrockBorders(e: PowderCtx): { success: boolean; borderCellsSet: number } {
  let borderCellsSet = 0;
  for (let x = 0; x < e.width; x++) {
    const iTop = e.getIndex(x, 0);
    const iBot = e.getIndex(x, e.height - 1);
    if (e.gridType[iTop] !== 29) {
      e.gridType[iTop] = 29;
      borderCellsSet++;
    }
    if (e.gridType[iBot] !== 29) {
      e.gridType[iBot] = 29;
      borderCellsSet++;
    }
  }
  for (let y = 0; y < e.height; y++) {
    const iLeft = e.getIndex(0, y);
    const iRight = e.getIndex(e.width - 1, y);
    if (e.gridType[iLeft] !== 29) {
      e.gridType[iLeft] = 29;
      borderCellsSet++;
    }
    if (e.gridType[iRight] !== 29) {
      e.gridType[iRight] = 29;
      borderCellsSet++;
    }
  }
  return { success: true, borderCellsSet };
}

export function coolAllCells(e: PowderCtx): { success: boolean } {
  e.gridTemp.fill(20);
  return { success: true };
}

// --- Stress Test Injectors (for testing debug diagnostics) ---

export function injectThermalSpike(e: PowderCtx): { success: boolean } {
  const cx = Math.floor(e.width / 2);
  const cy = Math.floor(e.height / 2);
  for (let dy = -10; dy <= 10; dy++) {
    for (let dx = -10; dx <= 10; dx++) {
      // Validated as coordinates. A range check on the raw index lets a column near
      // the edge wrap onto the next row, which is how the spike used to smear across
      // rows on a narrow grid.
      if (!e.isValid(cx + dx, cy + dy)) continue;
      const i = e.getIndex(cx + dx, cy + dy);
      e.gridTemp[i] = 2800;
      e.gridType[i] = 4; // Fire
    }
  }
  return { success: true };
}

export function injectAcidFlood(e: PowderCtx): { success: boolean } {
  const startY = Math.floor(e.height * 0.7);
  for (let y = startY; y < e.height - 1; y++) {
    for (let x = 1; x < e.width - 1; x++) {
      const i = e.getIndex(x, y);
      e.gridType[i] = 8; // Acid
    }
  }
  return { success: true };
}

export function injectCorruptCells(e: PowderCtx): { success: boolean } {
  const cx = Math.floor(e.width / 2);
  const cy = Math.floor(e.height / 2);
  for (let i = 0; i < 20; i++) {
    // Bounds-checked. The original had no check at all, so on a grid narrower than
    // 39 cells it wrote corruption onto the following row instead.
    if (!e.isValid(cx + i, cy)) break;
    const idx = e.getIndex(cx + i, cy);
    e.gridType[idx] = 9999; // Invalid ID
    e.gridTemp[idx] = NaN; // Corrupt float
  }
  return { success: true };
}

// --- Automated Diagnostics Pass ---

export function runAutoFix(e: PowderCtx): { logs: string[] } {
  const logs: string[] = [];
  logs.push("Initiating Powder Simulator Automated Diagnostics Pass...");

  const diag = getDiagnostics(e);
  if (diag.isHealthy) {
    logs.push("✓ All grid data buffers and temperatures verified normal.");
    logs.push("✓ No critical anomalies detected.");
    return { logs };
  }

  // Steps are numbered as they actually run. They used to be labelled "1/5" through
  // "5/5" while each was conditional, so a real repair pass would print "3/5" and
  // "4/5" and nothing else, as though steps had silently failed.
  const steps: string[] = [];
  const step = (message: string) => steps.push(message);

  if (diag.corruptCellCount > 0) {
    const res = flushStuckCells(e);
    step(`Cleared ${res.cleared} corrupted/NaN element cells.`);
  }

  if (diag.maxTemp > 3000 || diag.minTemp < -273) {
    const res = zeroThermalExtremes(e);
    step(`Normalized ${res.normalizedCount} thermal extremes to room temp (20°C).`);
  }

  const oob = purgeOutOfBounds(e);
  if (oob.purged > 0) {
    step(`Cleared ${oob.purged} cells wedged against the world frame.`);
  }

  // Only done while repairing a damaged world. Sealing the perimeter replaces it
  // with bedrock, which would be destructive to run on a healthy world that
  // deliberately has open edges — hence the early return above.
  const seal = sealBedrockBorders(e);
  step(`Verified bedrock perimeter boundary enclosure (${seal.borderCellsSet} cells updated).`);

  const realloc = reallocateBuffers(e);
  if (realloc.success) {
    step("Re-allocated canvas pixel buffers successfully.");
  }

  steps.forEach((message, i) => logs.push(`✓ Auto-Fix Step ${i + 1}/${steps.length}: ${message}`));

  const postDiag = getDiagnostics(e);
  logs.push(`Auto-Fix Sequence Completed. System health status: ${postDiag.isHealthy ? "100% OPERATIONAL" : "RECOVERY COMPLETED"}.`);
  return { logs };
}
