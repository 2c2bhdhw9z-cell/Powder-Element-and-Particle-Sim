import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { ElementDefinition } from "../types";
import { quenchLava } from "./phase-change";
import { steerSpark } from "./electricity";
import type { PowderCtx } from "./context";

/**
 * Chemical reactions & special element behavior for one cell.
 * Returns true when the cell was consumed or transformed (movement skipped).
 */
export function updateReactions(
  e: PowderCtx,
  x: number,
  y: number,
  idx: number,
  def: ElementDefinition,
  portalsA: [number, number][],
  portalsB: [number, number][]
): boolean {
  const type = def.id;

  // 1. Fire / Plasma / Lava / Thermite / Laser thermal effects
  if (type === 4 || type === 6 || type === 26 || type === 32 || type === 36 || def.state === "energy" || def.name.includes("Laser")) {
    if (type !== 6) {
      e.gridTemp[idx] = Math.min(3000, e.gridTemp[idx] + (type === 36 ? 80 : 20));
    }

    const neighbors = [
      [x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y],
      [x - 1, y - 1], [x + 1, y - 1], [x - 1, y + 1], [x + 1, y + 1]
    ];

    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType === EMPTY_ELEMENT_ID) continue;

      const nDef = e.registry.getElement(nType);

      if (nType === 2 || nType === 27) {
        if (type === 6) {
          quenchLava(e, idx, nIdx);
          if (e.gridType[idx] !== 6) return true;
          continue;
        } else if (type === 36 || def.state === "energy") {
          e.setElementAt(nx, ny, 14, Math.max(120, e.gridTemp[nIdx]));
        } else if (type === 4) {
          e.setElementAt(x, y, 14, 120);
          return true;
        }
      }

      // Residual steam still pulls heat out of lava
      if (type === 6 && nType === 14) {
        e.gridTemp[idx] -= 55;
        e.gridTemp[nIdx] = Math.max(e.gridTemp[nIdx], 110);
        if (e.gridTemp[idx] < 700) {
          e.setElementAt(x, y, 46, Math.max(180, e.gridTemp[idx]));
          return true;
        }
      }

      // Heat bleeds through an obsidian crust into surrounding water
      if (type === 6 && nType === 46) {
        const flow = (e.gridTemp[idx] - e.gridTemp[nIdx]) * 0.12;
        e.gridTemp[idx] -= flow;
        e.gridTemp[nIdx] += flow;
        if (e.gridTemp[idx] < 700) {
          e.setElementAt(x, y, 46, Math.max(180, e.gridTemp[idx]));
          return true;
        }
      }

      if (nType === 13) {
        if (type === 36 || type === 26) {
          e.setElementAt(nx, ny, 14, 140);
        } else {
          e.setElementAt(nx, ny, 2, 8);
        }
      }

      if ((type === 6 || type === 36) && (nType === 1 || nType === 7)) {
        if (nType === 1 && Math.random() < 0.08) e.setElementAt(nx, ny, 12);
        if (nType === 7 && e.gridTemp[idx] > 1100 && Math.random() < 0.02) {
          e.setElementAt(nx, ny, 6, 1200);
        }
      }

      if (nDef.flammability && Math.random() * 100 < nDef.flammability) {
        if (nType === 10 || nType === 28 || nType === 35 || nType === 31 || nType === 9 || nType === 43) {
          const rad = nType === 28 ? 26 : (nType === 43 ? 22 : (nType === 35 ? 24 : (nType === 31 ? 20 : 16)));
          e.triggerExplosion(nx, ny, rad, 22, 3000);
        } else {
          e.setElementAt(nx, ny, 4, 400);
        }
      }
    }
  }

  // Hot volcanic glass still boils water on contact, draining leftover lava heat
  if (type === 46 && e.gridTemp[idx] > 320) {
    const crustN = [[x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y]];
    for (const [nx, ny] of crustN) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType === 2 || nType === 27) {
        e.setElementAt(nx, ny, 14, 130, 80);
        e.gridVy[nIdx] = -2;
        e.gridTemp[idx] -= 90;
      }
    }
  }

  // 1.5 Electricity — seeks wet, rides metal, then burns
  if (type === 16) {
    if (steerSpark(e, x, y, idx)) return true;
  }

  // 2. Acid Corrosion
  if (type === 8) {
    const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];

      if (nType !== EMPTY_ELEMENT_ID && nType !== 8 && nType !== 12 && nType !== 29) {
        // Glass & Bedrock immune
        const nDef = e.registry.getElement(nType);
        if (!nDef.acidResistance || Math.random() * 100 > nDef.acidResistance) {
          e.setElementAt(nx, ny, 5); // Target turns to smoke
          e.setElementAt(x, y, EMPTY_ELEMENT_ID); // Acid consumed
          return true;
        }
      }
    }
  }

  // 3. Virus Bio Spreading
  if (type === 18) {
    const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType !== EMPTY_ELEMENT_ID && nType !== 18 && nType !== 29 && nType !== 12) {
        if (Math.random() < 0.15) {
          e.setElementAt(nx, ny, 18);
        }
      }
    }
  }

  // 3b. Ants crawl along solids and nibble wood/dirt
  if (type === 19) {
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    const d = dirs[Math.floor(Math.random() * 4)];
    const nx = x + d[0];
    const ny = y + d[1];
    if (e.isValid(nx, ny)) {
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType === EMPTY_ELEMENT_ID) {
        e.swapCells(idx, nIdx);
        return true;
      }
      if ((nType === 3 || nType === 39 || nType === 11) && Math.random() < 0.08) {
        e.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
      }
    }
  }

  // 3c. Wax melts into viscous honey near fire/lava
  if (type === 25) {
    const neighbors = [[x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nType = e.gridType[e.getIndex(nx, ny)];
      if (nType === 4 || nType === 6 || nType === 26) {
        e.setElementAt(x, y, 34, 80);
        return true;
      }
    }
  }

  // 3d. Dirt + water → mud
  if (type === 39) {
    const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      if (e.gridType[e.getIndex(nx, ny)] === 2 && Math.random() < 0.12) {
        e.setElementAt(x, y, 45);
        e.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
        return true;
      }
    }
  }

  // 3e. Ice freezes adjacent water
  if (type === 13) {
    const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      if (e.gridType[nIdx] === 2 && e.gridTemp[nIdx] < 8 && Math.random() < 0.04) {
        e.setElementAt(nx, ny, 13, -10);
      }
    }
  }

  // 4. Plant Growth
  if (type === 11) {
    const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      if (e.gridType[nIdx] === 2) {
        // Water: consume and grow plant onto that cell
        e.setElementAt(nx, ny, 11);
        break;
      }
    }
  }

  // 5. Void Singularity
  if (type === 20) {
    const neighbors = [
      [x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y],
      [x - 1, y - 1], [x + 1, y - 1], [x - 1, y + 1], [x + 1, y + 1]
    ];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      if (e.gridType[nIdx] !== EMPTY_ELEMENT_ID && e.gridType[nIdx] !== 20) {
        e.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
        e.gridP[nIdx] = -8;
      }
    }
  }

  // 5b. Fan — paint over it to rotate (life % 4)
  if (type === 48) {
    const d = (e.gridLife[idx] || 0) % 4;
    const ox = d === 0 ? 1 : d === 1 ? 0 : d === 2 ? -1 : 0;
    const oy = d === 0 ? 0 : d === 1 ? 1 : d === 2 ? 0 : -1;
    for (let k = 1; k <= 4; k++) {
      const nx = x + ox * k;
      const ny = y + oy * k;
      if (!e.isValid(nx, ny)) break;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType === 29 || nType === 48) break;
      const nDef = e.registry.getElement(nType);
      if (nType === EMPTY_ELEMENT_ID) {
        e.gridP[nIdx] += 1.4;
        continue;
      }
      if (nDef.state === "gas" || nDef.state === "plasma" || nDef.density < 16) {
        e.gridVx[nIdx] = Math.max(-20, Math.min(20, e.gridVx[nIdx] + ox * 5));
        e.gridVy[nIdx] = Math.max(-20, Math.min(20, e.gridVy[nIdx] + oy * 5));
        e.gridP[nIdx] += 2;
        const ax = nx + ox;
        const ay = ny + oy;
        if (e.isValid(ax, ay) && e.gridType[e.getIndex(ax, ay)] === EMPTY_ELEMENT_ID && Math.random() < 0.45) {
          e.swapCells(nIdx, e.getIndex(ax, ay));
        }
      }
    }
  }

  // 5c. Erosion — flowing water carves sand/dirt
  if (type === 2 && Math.random() < 0.06) {
    const g = Math.sign(e.gravityY) || 1;
    const spots = [
      [x, y + g],
      [x - 1, y + g],
      [x + 1, y + g],
      [x - 1, y],
      [x + 1, y],
    ];
    for (const [nx, ny] of spots) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const nType = e.gridType[nIdx];
      if (nType === 1 || nType === 39) {
        const dumpX = x + (Math.random() < 0.5 ? -1 : 1);
        const dumpY = y + g;
        if (e.isValid(dumpX, dumpY) && e.gridType[e.getIndex(dumpX, dumpY)] === EMPTY_ELEMENT_ID) {
          e.swapCells(nIdx, e.getIndex(dumpX, dumpY));
        } else if (nType === 39 && Math.random() < 0.35) {
          e.setElementAt(nx, ny, 45);
        }
        break;
      }
    }
  }

  // 6. Clone / Duplicator
  if (type === 21) {
    const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
    let sourceId = EMPTY_ELEMENT_ID;
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nType = e.gridType[e.getIndex(nx, ny)];
      if (nType !== EMPTY_ELEMENT_ID && nType !== 21) {
        sourceId = nType;
        break;
      }
    }
    if (sourceId !== EMPTY_ELEMENT_ID) {
      for (const [nx, ny] of neighbors) {
        if (e.isValid(nx, ny) && e.gridType[e.getIndex(nx, ny)] === EMPTY_ELEMENT_ID) {
          e.setElementAt(nx, ny, sourceId);
          break;
        }
      }
    }
  }

  // 7. Portal Teleportation
  if (type === 22 && portalsB.length > 0) {
    const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
    for (const [nx, ny] of neighbors) {
      if (!e.isValid(nx, ny)) continue;
      const nIdx = e.getIndex(nx, ny);
      const pType = e.gridType[nIdx];
      if (pType !== EMPTY_ELEMENT_ID && pType !== 22 && pType !== 23) {
        // Choose destination portal
        const targetPortal = portalsB[Math.floor(Math.random() * portalsB.length)];
        const targetNeighbors = [
          [targetPortal[0], targetPortal[1] - 1],
          [targetPortal[0] + 1, targetPortal[1]],
          [targetPortal[0] - 1, targetPortal[1]],
          [targetPortal[0], targetPortal[1] + 1]
        ];
        for (const [tx, ty] of targetNeighbors) {
          if (e.isValid(tx, ty) && e.gridType[e.getIndex(tx, ty)] === EMPTY_ELEMENT_ID) {
            e.setElementAt(tx, ty, pType);
            e.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
            break;
          }
        }
      }
    }
  }

  // 8. Custom Interaction Rules
  if (def.interactions && def.interactions.length > 0) {
    const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
    for (const rule of def.interactions) {
      if (Math.random() > rule.chance) continue;

      for (const [nx, ny] of neighbors) {
        if (!e.isValid(nx, ny)) continue;
        const nIdx = e.getIndex(nx, ny);
        if (e.gridType[nIdx] === rule.targetElementId) {
          if (rule.resultSelfId !== undefined) {
            e.setElementAt(x, y, rule.resultSelfId);
          }
          if (rule.resultTargetId !== undefined) {
            e.setElementAt(nx, ny, rule.resultTargetId);
          }
          if (rule.explosionRadius && rule.explosionRadius > 0) {
            e.triggerExplosion(x, y, rule.explosionRadius);
          }
          return true;
        }
      }
    }
  }

  return false;
}
