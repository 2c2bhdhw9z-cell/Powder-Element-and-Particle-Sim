import { ElementRegistry, EMPTY_ELEMENT_ID } from "./element-registry";
import { ElementDefinition } from "./types";
import { PowderHistory } from "./powder/history";
import { updatePhase } from "./powder/phase-change";
import { updateReactions } from "./powder/reactions";
import { updateMovement } from "./powder/movement";
import { triggerExplosion } from "./powder/explosion";
import { diffuseHeat, pipeHeat, applyWindDrift, updatePressure } from "./powder/thermals";
import { applyJostle, drawBrush, spawnAmount } from "./powder/brush";
import { renderToCanvas, captureThumbnail } from "./powder/render";
import {
  getDiagnostics,
  flushStuckCells,
  zeroThermalExtremes,
  reallocateBuffers,
  purgeOutOfBounds,
  extinguishFires,
  neutralizeAcids,
  sealBedrockBorders,
  coolAllCells,
  injectThermalSpike,
  injectAcidFlood,
  injectCorruptCells,
  runAutoFix,
} from "./powder/diagnostics";
import { debug } from "@/lib/debug";
import type { PowderCtx } from "./powder/context";

/**
 * Cellular-automata powder world.
 *
 * The engine owns grid state and orchestration; each physics subsystem lives
 * in its own module under `src/sim/powder/` and operates on the `PowderCtx`
 * structural interface (this class satisfies it):
 *
 *   phase-change.ts  boil / freeze / melt / condense, lava quench
 *   electricity.ts   lightning: seek wet → ride conductors → burn
 *   reactions.ts     chemical reactions & special element behavior
 *   explosion.ts     shockwave / shatter / embers / smoke plume
 *   movement.ts      gravity, buoyancy, viscosity, momentum
 *   thermals.ts      heat diffusion, heat pipes, wind, pressure field
 *   brush.ts         painting tools, flood fill, bulk spawn, jostle
 *   history.ts       typed-array undo/redo snapshots
 *   render.ts        canvas renderer + overlay modes
 *   diagnostics.ts   health inspection & repair actions
 */
export class PowderEngine implements PowderCtx {
  public width: number;
  public height: number;

  // Typed Arrays for maximum speed & cache locality
  public gridType: Uint16Array;
  public gridTemp: Float32Array;
  public gridLife: Uint16Array;
  public gridVisited: Uint8Array;
  public gridVx: Int8Array;
  public gridVy: Int8Array;
  public gridP: Float32Array;
  public gridPNext: Float32Array;

  public registry: ElementRegistry;

  // Global environment parameters
  public gravityX: number = 0;
  public gravityY: number = 1; // 1 = normal down, -1 = up, 0 = zero-g
  public ambientTemp: number = 20; // 20°C
  public windX: number = 0;
  public pressureEnabled: boolean = true;
  public heatConductionEnabled: boolean = true;
  public frameCount: number = 0;
  public textureMode: "diagonal_matrix" | "natural_grain" | "organic_flow" | "flat" = "natural_grain";
  public onBurst: ((x: number, y: number, r: number) => void) | null = null;
  public keepWorld = false;
  public lastFanRotate = 0;
  public jostleLeft = 0;

  // Render color buffer cache for fast canvas rendering
  public imageData: ImageData | null = null;

  // Undo / Redo History (typed-array snapshots)
  private history: PowderHistory = new PowderHistory(25);

  constructor(width: number = 240, height: number = 160, registry?: ElementRegistry) {
    this.width = width;
    this.height = height;
    this.registry = registry || new ElementRegistry();

    const size = width * height;
    this.gridType = new Uint16Array(size);
    this.gridTemp = new Float32Array(size);
    this.gridLife = new Uint16Array(size);
    this.gridVisited = new Uint8Array(size);
    this.gridVx = new Int8Array(size);
    this.gridVy = new Int8Array(size);
    this.gridP = new Float32Array(size);
    this.gridPNext = new Float32Array(size);

    this.resetGrid();
  }

  public resize(newWidth: number, newHeight: number) {
    if (this.width === newWidth && this.height === newHeight) return;

    const oldWidth = this.width;
    const oldHeight = this.height;
    const oldType = this.gridType;
    const oldTemp = this.gridTemp;
    const oldLife = this.gridLife;
    const oldVx = this.gridVx;
    const oldVy = this.gridVy;
    const oldP = this.gridP;

    this.width = newWidth;
    this.height = newHeight;

    const size = newWidth * newHeight;
    this.gridType = new Uint16Array(size);
    this.gridTemp = new Float32Array(size);
    this.gridLife = new Uint16Array(size);
    this.gridVisited = new Uint8Array(size);
    this.gridVx = new Int8Array(size);
    this.gridVy = new Int8Array(size);
    this.gridP = new Float32Array(size);
    this.gridPNext = new Float32Array(size);

    this.resetGrid();

    // Preserve previous particles within overlapping bounds
    const minW = Math.min(oldWidth, newWidth);
    const minH = Math.min(oldHeight, newHeight);
    for (let y = 0; y < minH; y++) {
      for (let x = 0; x < minW; x++) {
        const oldIdx = y * oldWidth + x;
        const newIdx = y * newWidth + x;
        this.gridType[newIdx] = oldType[oldIdx];
        this.gridTemp[newIdx] = oldTemp[oldIdx];
        this.gridLife[newIdx] = oldLife[oldIdx];
        this.gridVx[newIdx] = oldVx[oldIdx];
        this.gridVy[newIdx] = oldVy[oldIdx];
        this.gridP[newIdx] = oldP[oldIdx];
      }
    }

    this.imageData = null;
  }

  public resetGrid() {
    this.gridType.fill(EMPTY_ELEMENT_ID);
    this.gridTemp.fill(this.ambientTemp);
    this.gridLife.fill(0);
    this.gridVisited.fill(0);
    this.gridVx.fill(0);
    this.gridVy.fill(0);
    this.gridP.fill(0);
    this.gridPNext.fill(0);
  }

  public clear() {
    this.pushUndo();
    this.resetGrid();
  }

  // --- Undo / Redo History ---
  public pushUndo() {
    this.history.push(this);
  }

  public canUndo(): boolean {
    return this.history.canUndo();
  }

  public canRedo(): boolean {
    return this.history.canRedo();
  }

  public undo(): boolean {
    return this.history.undo(this);
  }

  public redo(): boolean {
    return this.history.redo(this);
  }

  public clearHistory() {
    this.history.clear();
  }

  public captureThumbnail(maxW: number = 320): string {
    return captureThumbnail(this, maxW);
  }

  public getWind(): number {
    return this.windX;
  }

  public setWind(v: number) {
    this.windX = Math.max(-5, Math.min(5, v));
  }

  public getIndex(x: number, y: number): number {
    return y * this.width + x;
  }

  public jostle(amount: number) {
    this.jostleLeft = Math.max(this.jostleLeft, amount);
  }

  public isValid(x: number, y: number): boolean {
    return x >= 0 && x < this.width && y >= 0 && y < this.height;
  }

  public getElementAt(x: number, y: number): ElementDefinition {
    if (!this.isValid(x, y)) return this.registry.getElement(29); // Bedrock if out of bounds
    const idx = this.getIndex(x, y);
    return this.registry.getElement(this.gridType[idx]);
  }

  public setElementAt(x: number, y: number, elementId: number, temp?: number, life?: number) {
    if (!this.isValid(x, y)) return;
    const idx = this.getIndex(x, y);
    const def = this.registry.getElement(elementId);

    const prev = this.gridType[idx];
    this.gridType[idx] = elementId;
    this.gridTemp[idx] = temp !== undefined ? temp : def.defaultTemp !== undefined ? def.defaultTemp : this.ambientTemp;
    this.gridLife[idx] =
      life !== undefined
        ? life
        : elementId === 48
          ? prev === 48
            ? this.gridLife[idx]
            : 0
          : def.decayTicks || 0;
    this.gridVx[idx] = 0;
    this.gridVy[idx] = 0;
  }

  public swapCells(idx1: number, idx2: number) {
    const t1 = this.gridType[idx1];
    const temp1 = this.gridTemp[idx1];
    const l1 = this.gridLife[idx1];
    const vx1 = this.gridVx[idx1];
    const vy1 = this.gridVy[idx1];

    this.gridType[idx1] = this.gridType[idx2];
    this.gridTemp[idx1] = this.gridTemp[idx2];
    this.gridLife[idx1] = this.gridLife[idx2];
    this.gridVx[idx1] = this.gridVx[idx2];
    this.gridVy[idx1] = this.gridVy[idx2];
    const p1 = this.gridP[idx1];
    this.gridP[idx1] = this.gridP[idx2];

    this.gridType[idx2] = t1;
    this.gridTemp[idx2] = temp1;
    this.gridLife[idx2] = l1;
    this.gridVx[idx2] = vx1;
    this.gridVy[idx2] = vy1;
    this.gridP[idx2] = p1;

    this.gridVisited[idx1] = 1;
    this.gridVisited[idx2] = 1;
  }

  // Draw Brush on Grid — auto push undo on stroke start externally for grouping
  public drawBrush(
    centerX: number,
    centerY: number,
    radius: number,
    elementId: number,
    shape: "circle" | "square" | "spray" | "line" | "fill" | "replace",
    targetElementId?: number
  ) {
    drawBrush(this, centerX, centerY, radius, elementId, shape, targetElementId);
  }

  // Bulk spawn particles into empty/random cells on grid
  public spawnAmount(elementId: number, amount: number) {
    spawnAmount(this, elementId, amount);
  }

  public getActiveParticleCount(): number {
    let count = 0;
    for (let i = 0; i < this.gridType.length; i++) {
      if (this.gridType[i] !== EMPTY_ELEMENT_ID) count++;
    }
    return count;
  }

  // Main Physics Tick
  public step() {
    this.frameCount++;
    this.gridVisited.fill(0);

    // Lightweight heat diffusion every 2 ticks when enabled
    if (this.heatConductionEnabled && this.frameCount % 2 === 0) {
      diffuseHeat(this);
      pipeHeat(this);
    }

    // Wind drift for light gases/smoke every 3 ticks
    if (this.windX !== 0 && this.frameCount % 3 === 0) {
      applyWindDrift(this);
    }

    if (this.pressureEnabled && this.frameCount % 2 === 0) {
      updatePressure(this);
    }

    if (this.jostleLeft > 0) {
      applyJostle(this);
      this.jostleLeft *= 0.72;
      if (this.jostleLeft < 0.15) this.jostleLeft = 0;
    }

    const portalsA: [number, number][] = [];
    const portalsB: [number, number][] = [];

    // First pass: locate portals
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        const idx = this.getIndex(x, y);
        const type = this.gridType[idx];
        if (type === 22) portalsA.push([x, y]);
        if (type === 23) portalsB.push([x, y]);
      }
    }

    // Determine scan direction based on gravity
    const scanBottomUp = this.gravityY >= 0;

    const startY = scanBottomUp ? this.height - 1 : 0;
    const endY = scanBottomUp ? -1 : this.height;
    const stepY = scanBottomUp ? -1 : 1;

    for (let y = startY; y !== endY; y += stepY) {
      // Alternate horizontal scan direction to remove biases
      const scanLeftRight = (y + this.frameCount) % 2 === 0;
      const startX = scanLeftRight ? 0 : this.width - 1;
      const endX = scanLeftRight ? this.width : -1;
      const stepX = scanLeftRight ? 1 : -1;

      for (let x = startX; x !== endX; x += stepX) {
        const idx = this.getIndex(x, y);
        if (this.gridVisited[idx]) continue;

        const type = this.gridType[idx];
        if (type === EMPTY_ELEMENT_ID) continue;

        const def = this.registry.getElement(type);

        // Decay handler (Fire, Smoke, Sparks, Plasma)
        if (def.decayTicks && def.decayTicks > 0) {
          if (this.gridLife[idx] > 0) {
            this.gridLife[idx]--;
          } else {
            this.setElementAt(x, y, def.decayIntoId || EMPTY_ELEMENT_ID);
            continue;
          }
        }

        if (updatePhase(this, x, y, idx, type)) {
          continue;
        }

        // Custom & Preset Chemical Reaction Evaluator
        if (updateReactions(this, x, y, idx, def, portalsA, portalsB)) {
          continue; // Particle consumed or transformed
        }

        // Particle State Physics Movement
        updateMovement(this, x, y, idx, def);
      }
    }
  }

  // Trigger explosion physics wave with multi-stage shockwave & flying embers
  public triggerExplosion(
    centerX: number,
    centerY: number,
    radius: number,
    shockwaveForce: number = 22,
    maxHeat: number = 3000
  ) {
    triggerExplosion(this, centerX, centerY, radius, shockwaveForce, maxHeat);
  }

  // Render Grid onto Canvas 2D ImageData context
  public renderToCanvas(ctx: CanvasRenderingContext2D, overlayMode: "normal" | "temp" | "temp_overlay" | "density" = "normal") {
    renderToCanvas(this, ctx, overlayMode);
  }

  // Export state to compressed string
  public hashLite(): number {
    const t = this.gridType;
    let h = this.width * 131 + this.height + ((this.gravityX * 10) | 0) * 17;
    const step = Math.max(1, (t.length / 4000) | 0);
    for (let i = 0; i < t.length; i += step) h = (h * 33 + t[i]) | 0;
    return h;
  }

  public serializeLite(): string {
    const t = this.gridType;
    let raw = "";
    const chunk = 32768;
    for (let i = 0; i < t.length; i += chunk) {
      raw += String.fromCharCode(...t.subarray(i, Math.min(t.length, i + chunk)));
    }
    return JSON.stringify({ w: this.width, h: this.height, t: btoa(raw), gx: this.gravityX, gy: this.gravityY });
  }

  public deserializeLite(json: string) {
    try {
      const o = JSON.parse(json) as { w: number; h: number; t: string; gx?: number; gy?: number };
      if (o.w !== this.width || o.h !== this.height) this.resize(o.w, o.h);
      const bin = atob(o.t);
      const n = Math.min(this.gridType.length, bin.length);
      for (let i = 0; i < n; i++) this.gridType[i] = bin.charCodeAt(i);
      if (o.gx !== undefined) this.gravityX = o.gx;
      if (o.gy !== undefined) this.gravityY = o.gy;
    } catch {
      /* ignore */
    }
  }

  public serializeState(): string {
    return JSON.stringify({
      width: this.width,
      height: this.height,
      gridType: Array.from(this.gridType),
      gridTemp: Array.from(this.gridTemp),
      gridLife: Array.from(this.gridLife),
      gravityX: this.gravityX,
      gravityY: this.gravityY,
      windX: this.windX,
      ambientTemp: this.ambientTemp,
    });
  }

  // Import state from string
  public deserializeState(jsonStr: string) {
    try {
      const obj = JSON.parse(jsonStr);
      if (obj.gridType && Array.isArray(obj.gridType)) {
        if (typeof obj.width === "number" && typeof obj.height === "number") {
          if (obj.width !== this.width || obj.height !== this.height) {
            this.resize(obj.width, obj.height);
          }
        }
        this.resetGrid();
        const len = Math.min(this.width * this.height, obj.gridType.length);
        for (let i = 0; i < len; i++) {
          this.gridType[i] = obj.gridType[i];
        }
        if (Array.isArray(obj.gridTemp)) {
          const tlen = Math.min(len, obj.gridTemp.length);
          for (let i = 0; i < tlen; i++) this.gridTemp[i] = obj.gridTemp[i];
        }
        if (Array.isArray(obj.gridLife)) {
          const llen = Math.min(len, obj.gridLife.length);
          for (let i = 0; i < llen; i++) this.gridLife[i] = obj.gridLife[i];
        }
        if (obj.gravityX !== undefined) this.gravityX = obj.gravityX;
        if (obj.gravityY !== undefined) this.gravityY = obj.gravityY;
        if (obj.windX !== undefined) this.windX = obj.windX;
        if (obj.ambientTemp !== undefined) this.ambientTemp = obj.ambientTemp;
      }
    } catch (e) {
      debug.error("Failed to parse grid state", e);
    }
  }

  // --- Diagnostics & System Health Inspection ---
  public getDiagnostics() {
    return getDiagnostics(this);
  }

  // --- Manual Diagnostics & Repair Actions ---
  public flushStuckCells() {
    return flushStuckCells(this);
  }

  public zeroThermalExtremes() {
    return zeroThermalExtremes(this);
  }

  public reallocateBuffers() {
    return reallocateBuffers(this);
  }

  public purgeOutOfBounds() {
    return purgeOutOfBounds(this);
  }

  public extinguishFires() {
    return extinguishFires(this);
  }

  public neutralizeAcids() {
    return neutralizeAcids(this);
  }

  public sealBedrockBorders() {
    return sealBedrockBorders(this);
  }

  public coolAllCells() {
    return coolAllCells(this);
  }

  // --- Stress Test Injectors (for testing debug diagnostics) ---
  public injectThermalSpike() {
    return injectThermalSpike(this);
  }

  public injectAcidFlood() {
    return injectAcidFlood(this);
  }

  public injectCorruptCells() {
    return injectCorruptCells(this);
  }

  public runAutoFix() {
    return runAutoFix(this);
  }
}
