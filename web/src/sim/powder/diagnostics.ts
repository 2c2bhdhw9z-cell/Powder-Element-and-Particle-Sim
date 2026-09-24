import { EMPTY_ELEMENT_ID, MAX_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

// --- Diagnostics & System Health Inspection ---

export function getDiagnostics(e: PowderCtx) {
  let activeParticles = 0;
  // Counted separately, then combined per cell.
  //
  // A single count incremented in both places double-counted any cell that was bad in
  // both ways — which is exactly what the corrupt-cell injector produces, so twenty
  // damaged cells were reported as forty, and the repair that followed then truthfully
  // said it had cleared twenty. Keeping them apart also lets the automatic pass tell
  // the two faults apart, which it has to: they need different repairs.
  let corruptTypeCount = 0;
  let nanTempCount = 0;
  let corruptCellCount = 0;
  let validTempCount = 0;
  // Tracked with an explicit "did we see anything" flag rather than magic starting
  // temperatures. The original started these at -273 and 3000 and then mapped those
  // exact values back to 20 in the report, so a world genuinely uniform at absolute
  // zero reported room temperature, and a grid of pure NaN reported 20/20 while the
  // corrupt-cell count screamed.
  let sawTemp = false;
  let maxTemp = 0;
  let minTemp = 0;
  let sumTemp = 0;
  const totalCells = e.width * e.height;

  for (let i = 0; i < totalCells; i++) {
    let cellIsCorrupt = false;
    const type = e.gridType[i];
    if (type !== EMPTY_ELEMENT_ID) {
      activeParticles++;
      // gridType is a Uint16Array, so `type` is always an integer in 0..65535 —
      // the old `type < 0 || Number.isNaN(type)` tests could never fire.
      //
      // Bounded by what the registry can describe. The old threshold of 500 left ids
      // from 100 to 499 in a blind spot: the registry falls back to air for them, so
      // they drew and behaved as air, this count ignored them, the repair could not
      // clear them, and they still counted as active particles forever.
      if (type > MAX_ELEMENT_ID) {
        corruptTypeCount++;
        cellIsCorrupt = true;
      }
    }
    const t = e.gridTemp[i];
    if (!Number.isNaN(t)) {
      if (!sawTemp || t > maxTemp) maxTemp = t;
      if (!sawTemp || t < minTemp) minTemp = t;
      sawTemp = true;
      sumTemp += t;
      validTempCount++;
    } else {
      nanTempCount++;
      cellIsCorrupt = true;
    }
    if (cellIsCorrupt) corruptCellCount++;
  }

  // Averaged over the cells that actually contributed. Dividing by every cell while
  // skipping the unreadable ones dragged the reported average toward zero in
  // proportion to how damaged the world was — so the number was least trustworthy
  // exactly when it was being consulted.
  const avgTemp = validTempCount > 0 ? Math.round(sumTemp / validTempCount) : Math.round(e.ambientTemp);
  // 19 bytes per cell: gridType 2 + gridTemp 4 + gridLife 2 + gridVisited 1 +
  // gridVx 1 + gridVy 1 + gridP 4 + gridPNext 4. The old figure of 6 was written
  // when temperature was a single byte and the pressure fields did not exist, so it
  // under-reported memory use by roughly three times.
  const memoryBytes = totalCells * 19 + (e.imageData ? e.imageData.data.byteLength : 0);
  const issues: string[] = [];

  if (corruptCellCount > 0) issues.push(`Detected ${corruptCellCount} corrupted/NaN grid cells`);
  if (sawTemp && (maxTemp > 3000 || minTemp < -273)) {
    issues.push(`Thermal extremes detected (${Math.round(minTemp)}°C to ${Math.round(maxTemp)}°C)`);
  }
  if (activeParticles > totalCells * 0.95) issues.push("Grid density near maximum capacity (>95%)");

  return {
    width: e.width,
    height: e.height,
    totalCells,
    activeParticles,
    corruptCellCount,
    /** Cells holding an element id the registry cannot describe. */
    corruptTypeCount,
    /**
     * Cells whose temperature is not a number.
     *
     * Reported separately because the automatic pass has to be able to see it. Its
     * thermal repair used to be gated on the hottest and coldest readings, and an
     * unreadable temperature is neither — so a world whose only fault was unreadable
     * temperatures had nothing done to it and was then declared recovered.
     */
    nanTempCount,
    // Guarded like avgTemp above. A zero-cell grid used to report NaN here.
    loadPercentage: totalCells > 0 ? Math.round((activeParticles / totalCells) * 100) : 0,
    maxTemp: sawTemp ? Math.round(maxTemp) : Math.round(e.ambientTemp),
    minTemp: sawTemp ? Math.round(minTemp) : Math.round(e.ambientTemp),
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
    // Same bound the inspection uses, so what is reported is what gets cleared.
    if (type > MAX_ELEMENT_ID) {
      e.gridType[i] = EMPTY_ELEMENT_ID;
      // Emptied completely, like `purgeOutOfBounds` does. Clearing only the id and the
      // temperature left the cell holding the lifetime and momentum of whatever had
      // been there, so the next thing to occupy it inherited a stranger's motion and a
      // countdown to decay.
      e.gridTemp[i] = e.ambientTemp;
      e.gridLife[i] = 0;
      e.gridVx[i] = 0;
      e.gridVy[i] = 0;
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
      // The world's own ambient temperature, not a hardcoded 20. Three of the repairs
      // used 20 and three used the ambient, so on a world set to -40 the repairs
      // disagreed with each other and with the physics they were restoring.
      e.gridTemp[i] = e.ambientTemp;
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

/**
 * Walls the world in with bedrock.
 *
 * Deliberately a manual action only. It is not a repair — it replaces whatever was
 * around the edge, and most of the built-in scenes leave the top and the upper side
 * walls open on purpose, so running it over a scene destroys its shape. The automatic
 * pass used to run it on any unhealthy world, including one whose only complaint was
 * that it was nearly full.
 */
export function sealBedrockBorders(e: PowderCtx): { success: boolean; borderCellsSet: number } {
  let borderCellsSet = 0;
  // A world with no cells has no border. Without this the loops below computed an
  // index of -1, whose write is silently dropped by the typed array while the read
  // beside it returns undefined — so the count went up for writes that never landed.
  if (e.width <= 0 || e.height <= 0) return { success: true, borderCellsSet };

  const set = (x: number, y: number) => {
    if (!e.isValid(x, y)) return;
    const idx = e.getIndex(x, y);
    if (e.gridType[idx] === 29) return;
    e.gridType[idx] = 29;
    // Bedrock does not burn, decay or move, so the state of whatever it replaced has
    // to go with it. Leaving it behind turned a burning cell into bedrock that was
    // still at 900°C with a decay countdown running, quietly cooking its neighbours
    // from inside something that is supposed to be inert.
    e.gridTemp[idx] = e.ambientTemp;
    e.gridLife[idx] = 0;
    e.gridVx[idx] = 0;
    e.gridVy[idx] = 0;
    borderCellsSet++;
  };

  for (let x = 0; x < e.width; x++) {
    set(x, 0);
    set(x, e.height - 1);
  }
  for (let y = 0; y < e.height; y++) {
    set(0, y);
    set(e.width - 1, y);
  }
  return { success: true, borderCellsSet };
}

export function coolAllCells(e: PowderCtx): { success: boolean } {
  // The world's ambient, not a hardcoded 20 — see `zeroThermalExtremes`.
  e.gridTemp.fill(e.ambientTemp);
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
      // Placed through setElementAt so the fire gets its decay countdown.
      //
      // Writing the id straight into the grid left the countdown at zero, and the
      // decay handler turns any decaying cell whose countdown has run out into its
      // successor immediately — so on the very next tick the whole spike became smoke
      // at smoke's own temperature, erasing the thermal extreme this exists to create.
      e.setElementAt(cx + dx, cy + dy, 4, 2800); // Fire
    }
  }
  return { success: true };
}

export function injectAcidFlood(e: PowderCtx): { success: boolean } {
  const startY = Math.floor(e.height * 0.7);
  for (let y = startY; y < e.height - 1; y++) {
    for (let x = 1; x < e.width - 1; x++) {
      // Through setElementAt, so the acid arrives at its own temperature rather than
      // inheriting whatever occupied the cell. Poured over lava it used to start at
      // well above boiling and flash straight to steam.
      e.setElementAt(x, y, 8); // Acid
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

  if (diag.corruptTypeCount > 0) {
    const res = flushStuckCells(e);
    step(`Cleared ${res.cleared} cells holding an unusable element.`);
  }

  // Unreadable temperatures are included in the condition.
  //
  // This used to be gated on the hottest and coldest readings alone, and an unreadable
  // temperature is neither — it is excluded from both. So a world whose only fault was
  // unreadable temperatures had its thermal repair skipped entirely, was then told
  // "recovery completed", and still reported itself unhealthy the moment anyone looked.
  if (diag.nanTempCount > 0 || diag.maxTemp > 3000 || diag.minTemp < -273) {
    const res = zeroThermalExtremes(e);
    step(`Returned ${res.normalizedCount} unusable or extreme temperatures to ambient.`);
  }

  const oob = purgeOutOfBounds(e);
  if (oob.purged > 0) {
    step(`Cleared ${oob.purged} cells wedged against the world frame.`);
  }

  // Note: the perimeter is deliberately NOT sealed here. See `sealBedrockBorders` —
  // it replaces whatever is around the edge with bedrock, and most of the built-in
  // scenes leave the top and upper sides open on purpose. Running it as part of an
  // automatic pass destroyed the shape of any such scene, in response to faults that
  // had nothing to do with the world's edges. It remains available as a manual action.

  const realloc = reallocateBuffers(e);
  if (realloc.success) {
    step("Re-allocated canvas pixel buffers successfully.");
  }

  steps.forEach((message, i) => logs.push(`✓ Auto-Fix Step ${i + 1}/${steps.length}: ${message}`));

  // Says what is actually left, rather than dressing a failure up as a success. The
  // old message printed "RECOVERY COMPLETED" whenever the world was still broken,
  // which is the one case where the detail matters.
  const postDiag = getDiagnostics(e);
  if (postDiag.isHealthy) {
    logs.push("Auto-Fix complete. System health: 100% OPERATIONAL.");
  } else {
    logs.push(`Auto-Fix complete, but ${postDiag.issues.length} issue(s) could not be repaired:`);
    for (const issue of postDiag.issues) logs.push(`  • ${issue}`);
  }
  return { logs };
}
