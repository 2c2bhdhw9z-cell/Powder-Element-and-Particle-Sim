import { EMPTY_ELEMENT_ID } from "../element-registry";
import { triggerExplosion } from "./explosion";
import type { PowderCtx } from "./context";

/**
 * Heat conduction diffusion between conductive neighbors — simple 4-neighbor
 * averaging with conductivity weighting, sampled sparsely for performance.
 *
 * Two corrections over the original:
 *
 * 1. The sampled lattice now shifts every pass. It used to start at (1, 1) and
 *    stride by 2 forever, so only odd/odd cells ever acted as a diffusion centre —
 *    and since all four neighbours of an odd/odd cell are at even coordinates, those
 *    neighbours were never sampled themselves. Heat flowed one way out of a fixed
 *    lattice and pooled where it could not be redistributed, leaving a permanent
 *    checkerboard in the temperature field. Cycling the offset covers all four
 *    sub-lattices.
 * 2. Heat is now conserved. The centre cell gained `delta` while each of its four
 *    neighbours gave up only `delta * 0.15` — six tenths of it — so every pass
 *    quietly destroyed heat around hot cells and invented it around cold ones,
 *    despite the comment claiming to conserve.
 */
export function diffuseHeat(e: PowderCtx) {
  // diffuseHeat runs on every second tick, so halving the frame count gives a
  // pass counter; four passes visit all four sub-lattices.
  const phase = Math.floor(e.frameCount / 2) % 4;
  const offX = phase % 2;
  const offY = (phase >> 1) % 2;
  for (let y = 1 + offY; y < e.height - 1; y += 2) {
    for (let x = 1 + offX; x < e.width - 1; x += 2) {
      const idx = e.getIndex(x, y);
      const type = e.gridType[idx];
      if (type === EMPTY_ELEMENT_ID) continue;
      const def = e.registry.getElement(type);
      const cond = def.heatConductivity ?? 0;
      if (cond <= 0.05) continue;
      const t = e.gridTemp[idx];
      // average with 4 neighbors
      let sum = t;
      let cnt = 1;
      const neigh = [e.getIndex(x + 1, y), e.getIndex(x - 1, y), e.getIndex(x, y + 1), e.getIndex(x, y - 1)];
      for (const nIdx of neigh) {
        if (nIdx >= 0 && nIdx < e.gridTemp.length) {
          sum += e.gridTemp[nIdx];
          cnt++;
        }
      }
      const avg = sum / cnt;
      const delta = (avg - t) * cond * 0.15;
      e.gridTemp[idx] = t + delta;
      // Take back from the neighbours exactly what this cell gained, so heat moves
      // rather than being created or destroyed.
      const contributors = cnt - 1;
      if (contributors > 0) {
        const share = delta / contributors;
        for (const nIdx of neigh) {
          if (nIdx >= 0 && nIdx < e.gridTemp.length) {
            e.gridTemp[nIdx] -= share;
          }
        }
      }
    }
  }
}

/** Heat pipes (copper / wire): fast conduction along conductors, leak to other matter. */
export function pipeHeat(e: PowderCtx) {
  const w = e.width;
  const h = e.height;
  const type = e.gridType;
  const temp = e.gridTemp;
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = y * w + x;
      const t = type[i];
      if (t !== 47 && t !== 17) continue;
      const self = temp[i];
      const nbs = [i - 1, i + 1, i - w, i + w];
      let pipeSum = self;
      let pipeN = 1;
      let dump = 0;
      let dumpN = 0;
      for (const ni of nbs) {
        const nt = type[ni];
        if (nt === 47 || nt === 17) {
          pipeSum += temp[ni];
          pipeN++;
        } else if (nt !== EMPTY_ELEMENT_ID && nt !== 29) {
          dump += temp[ni];
          dumpN++;
        }
      }
      const pipeAvg = pipeSum / pipeN;
      const mix = t === 47 ? 0.55 : 0.22;
      temp[i] = self + (pipeAvg - self) * mix;
      if (dumpN > 0) {
        const leak = (temp[i] - dump / dumpN) * (t === 47 ? 0.18 : 0.08);
        temp[i] -= leak;
        const share = leak / dumpN;
        for (const ni of nbs) {
          const nt = type[ni];
          if (nt !== 47 && nt !== 17 && nt !== EMPTY_ELEMENT_ID && nt !== 29) {
            temp[ni] += share;
          }
        }
      }
    }
  }
}

/** Horizontal wind drift for gases and light powders. */
export function applyWindDrift(e: PowderCtx) {
  const w = e.windX;
  if (w === 0) return;
  const dir = w > 0 ? 1 : -1;
  const strength = Math.abs(w);
  // scan and nudge light elements sideways if empty
  for (let y = 0; y < e.height; y++) {
    // iterate opposite to wind to avoid double move
    const startX = dir > 0 ? e.width - 2 : 1;
    const endX = dir > 0 ? -1 : e.width;
    const stepX = dir > 0 ? -1 : 1;
    for (let x = startX; x !== endX; x += stepX) {
      const idx = e.getIndex(x, y);
      const type = e.gridType[idx];
      if (type === EMPTY_ELEMENT_ID) continue;
      const def = e.registry.getElement(type);
      const isLight = def.state === "gas" || def.state === "plasma" || def.density < 12;
      if (!isLight) continue;
      if (Math.random() > 0.4 * strength) continue;
      const nx = x + dir;
      if (!e.isValid(nx, y)) continue;
      const nIdx = e.getIndex(nx, y);
      if (e.gridType[nIdx] === EMPTY_ELEMENT_ID) {
        e.swapCells(idx, nIdx);
        e.gridVisited[nIdx] = 1;
      }
    }
  }
}

/**
 * Pressure field: per-cell build-up from density/gases, 4-neighbor smoothing,
 * and over-pressurized sealed pockets (steam/gas/smoke) detonating.
 */
export function updatePressure(e: PowderCtx) {
  const w = e.width;
  const h = e.height;
  const p = e.gridP;
  const next = e.gridPNext;
  const type = e.gridType;
  const n = w * h;

  for (let i = 0; i < n; i++) {
    const t = type[i];
    if (t === EMPTY_ELEMENT_ID) {
      p[i] *= 0.82;
      continue;
    }
    if (t === 20) {
      p[i] = Math.min(p[i], -4);
      continue;
    }
    const def = e.registry.getElement(t);
    let add = def.density * 0.012;
    if (def.state === "gas" || def.state === "plasma") add += 0.35;
    if (t === 4 || t === 14 || t === 32) add += 1.2;
    if (t === 6) add += 0.6;
    p[i] = Math.max(-8, Math.min(24, p[i] * 0.92 + add));
  }

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x;
      let sum = p[i] * 2;
      let c = 2;
      if (x > 0) {
        sum += p[i - 1];
        c++;
      }
      if (x < w - 1) {
        sum += p[i + 1];
        c++;
      }
      if (y > 0) {
        sum += p[i - w];
        c++;
      }
      if (y < h - 1) {
        sum += p[i + w];
        c++;
      }
      next[i] = sum / c;
    }
  }
  e.gridP = next;
  e.gridPNext = p;

  if (e.frameCount % 4 === 0) {
    for (let i = 0; i < n; i++) {
      if (e.gridP[i] < 12) continue;
      const t = type[i];
      if (t !== 14 && t !== 31 && t !== 43 && t !== 5) continue;
      const x = i % w;
      const y = (i / w) | 0;
      let walls = 0;
      // Checked as coordinates, not raw offsets. At x = 0, i - 1 is the last cell of
      // the row above: not adjacent, yet it was counted toward "sealed", so pockets
      // against the left and right walls detonated on the wrong evidence.
      const nbs: [number, number][] = [
        [x - 1, y],
        [x + 1, y],
        [x, y - 1],
        [x, y + 1],
      ];
      for (const [nx, ny] of nbs) {
        if (!e.isValid(nx, ny)) {
          // The edge of the world contains pressure just as stone does.
          walls++;
          continue;
        }
        const nt = type[e.getIndex(nx, ny)];
        if (nt === 7 || nt === 17 || nt === 42 || nt === 29 || nt === 12 || nt === 47) walls++;
      }
      if (walls >= 3) {
        triggerExplosion(e, x, y, 8, 14, 900);
        break;
      }
    }
  }
}
