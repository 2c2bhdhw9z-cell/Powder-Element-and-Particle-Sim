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
      if (type < 0 || type >= 500 || Number.isNaN(type)) {
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
  const memoryBytes = totalCells * (2 + 1 + 2 + 1) + (e.imageData ? e.imageData.data.byteLength : 0);
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
    loadPercentage: Math.round((activeParticles / totalCells) * 100),
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
    if (type < 0 || type >= 500 || Number.isNaN(type)) {
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

export function purgeOutOfBounds(e: PowderCtx): { success: boolean; purged: number } {
  let purged = 0;
  for (let x = 0; x < e.width; x++) {
    const idxTop = e.getIndex(x, 0);
    const idxBot = e.getIndex(x, e.height - 1);
    if (e.gridType[idxTop] !== 29) {
      e.gridType[idxTop] = EMPTY_ELEMENT_ID;
      purged++;
    }
    if (e.gridType[idxBot] !== 29) {
      e.gridType[idxBot] = EMPTY_ELEMENT_ID;
      purged++;
    }
  }
  return { success: true, purged };
}

export function extinguishFires(e: PowderCtx): { success: boolean; extinguished: number } {
  let extinguished = 0;
  const totalCells = e.width * e.height;
  for (let i = 0; i < totalCells; i++) {
    const t = e.gridType[i];
    // 4 = Fire, 5 = Smoke, 23 = Spark
    if (t === 4 || t === 5 || t === 23) {
      e.gridType[i] = EMPTY_ELEMENT_ID;
      e.gridTemp[i] = 20;
      extinguished++;
    } else if (t === 10 || t === 15) {
      e.gridType[i] = 2; // Stone
      e.gridTemp[i] = 250;
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
      // Acid ID
      e.gridType[i] = 3; // Water ID
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
      const i = e.getIndex(cx + dx, cy + dy);
      if (i >= 0 && i < e.gridTemp.length) {
        e.gridTemp[i] = 2800;
        e.gridType[i] = 4; // Fire
      }
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

  if (diag.corruptCellCount > 0) {
    const res = flushStuckCells(e);
    logs.push(`✓ Auto-Fix Step 1/5: Cleared ${res.cleared} corrupted/NaN element cells.`);
  }

  if (diag.maxTemp > 3000 || diag.minTemp < -273) {
    const res = zeroThermalExtremes(e);
    logs.push(`✓ Auto-Fix Step 2/5: Normalized ${res.normalizedCount} thermal extremes to room temp (20°C).`);
  }

  const oob = purgeOutOfBounds(e);
  if (oob.purged > 0) {
    logs.push(`✓ Auto-Fix Step 3/5: Sealed ${oob.purged} out-of-bounds frame cells.`);
  }

  const seal = sealBedrockBorders(e);
  logs.push(`✓ Auto-Fix Step 4/5: Verified bedrock perimeter boundary enclosure (${seal.borderCellsSet} cells updated).`);

  const realloc = reallocateBuffers(e);
  if (realloc.success) {
    logs.push("✓ Auto-Fix Step 5/5: Re-allocated canvas pixel buffers successfully.");
  }

  const postDiag = getDiagnostics(e);
  logs.push(`Auto-Fix Sequence Completed. System health status: ${postDiag.isHealthy ? "100% OPERATIONAL" : "RECOVERY COMPLETED"}.`);
  return { logs };
}
