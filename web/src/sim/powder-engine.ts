import { ElementRegistry, EMPTY_ELEMENT_ID, MAX_ELEMENT_ID } from "./element-registry";

/**
 * One cell as the lite wire format carries it.
 *
 * The format is a single byte per cell, so anything outside a byte has to become air.
 * `hashLite` and `serializeLite` both go through here, which is the point: when they
 * disagreed about a cell, the sender's fingerprint never matched the world the
 * receiver actually built, and the host resent the whole grid every tick forever.
 */
function liteByte(id: number): number {
  return id > 0 && id <= 255 ? id : EMPTY_ELEMENT_ID;
}
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

  /**
   * Largest grid the engine will allocate, per side. Well beyond any real display,
   * but low enough that a hostile or corrupt scene file cannot ask for terabytes.
   */
  public static readonly MAX_DIMENSION = 8192;

  /** Whether a pair of dimensions is something this engine will accept. */
  public static isValidSize(w: unknown, h: unknown): boolean {
    return (
      typeof w === "number" &&
      typeof h === "number" &&
      Number.isInteger(w) &&
      Number.isInteger(h) &&
      w > 0 &&
      h > 0 &&
      w <= PowderEngine.MAX_DIMENSION &&
      h <= PowderEngine.MAX_DIMENSION
    );
  }

  public resize(newWidth: number, newHeight: number) {
    // Reject anything unusable rather than half-applying it. Dimensions reach here
    // straight from scene files and multiplayer payloads.
    if (!PowderEngine.isValidSize(newWidth, newHeight)) return;
    if (this.width === newWidth && this.height === newHeight) return;

    const oldWidth = this.width;
    const oldHeight = this.height;
    const oldType = this.gridType;
    const oldTemp = this.gridTemp;
    const oldLife = this.gridLife;
    const oldVx = this.gridVx;
    const oldVy = this.gridVy;
    const oldP = this.gridP;

    // Allocate everything into locals FIRST and only publish once all eight have
    // succeeded. The original assigned width/height and then allocated one array at
    // a time, so an allocation failure part-way through left the engine claiming a
    // new size while still holding old, smaller buffers — and because typed arrays
    // ignore out-of-range writes silently, every later write vanished and the world
    // was permanently broken with nothing reported.
    const size = newWidth * newHeight;
    let nextType: Uint16Array;
    let nextTemp: Float32Array;
    let nextLife: Uint16Array;
    let nextVisited: Uint8Array;
    let nextVx: Int8Array;
    let nextVy: Int8Array;
    let nextP: Float32Array;
    let nextPNext: Float32Array;
    try {
      nextType = new Uint16Array(size);
      nextTemp = new Float32Array(size);
      nextLife = new Uint16Array(size);
      nextVisited = new Uint8Array(size);
      nextVx = new Int8Array(size);
      nextVy = new Int8Array(size);
      nextP = new Float32Array(size);
      nextPNext = new Float32Array(size);
    } catch (err) {
      debug.error("Powder resize failed to allocate; keeping the existing grid", err);
      return;
    }

    this.width = newWidth;
    this.height = newHeight;
    this.gridType = nextType;
    this.gridTemp = nextTemp;
    this.gridLife = nextLife;
    this.gridVisited = nextVisited;
    this.gridVx = nextVx;
    this.gridVy = nextVy;
    this.gridP = nextP;
    this.gridPNext = nextPNext;

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

    // First pass: locate the exit portals, before anything has moved, so a portal
    // pair sees a consistent snapshot of the world.
    //
    // Only Portal B is collected. Portal A positions used to be gathered and passed
    // along as well, but nothing ever read them — teleporting is one-way by design.
    const portalsB: [number, number][] = [];
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        if (this.gridType[this.getIndex(x, y)] === 23) portalsB.push([x, y]);
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
        if (updateReactions(this, x, y, idx, def, portalsB)) {
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

  /**
   * Cheap world fingerprint, used to detect multiplayer desync.
   *
   * `gravityY` is now part of it. Leaving it out meant two worlds differing only in
   * gravity direction — an utterly different simulation — produced the same
   * fingerprint, which is exactly the divergence this is supposed to catch.
   */
  public hashLite(): number {
    const t = this.gridType;
    let h =
      this.width * 131 +
      this.height +
      (Math.round(this.gravityX * 10) | 0) * 17 +
      (Math.round(this.gravityY * 10) | 0) * 29;
    const step = Math.max(1, (t.length / 4000) | 0);
    // Mixes the value `serializeLite` would actually put on the wire, not the raw
    // cell. The two disagreed for any id above 255, which the wire format has to
    // flatten to air: the sender's fingerprint kept reflecting the original id while
    // the receiver held air, so the host's "have we diverged?" test was true forever.
    // It resent the entire grid every tick, and the two worlds never converged.
    for (let i = 0; i < t.length; i += step) h = (h * 33 + liteByte(t[i])) | 0;
    return h;
  }

  /**
   * Compact element-layout payload, used for multiplayer world sync.
   *
   * Encoded one byte per cell. Element ids are capped at 99 by the registry, so a
   * byte is enough — but `gridType` is 16-bit and the id space is documented as
   * reaching 499, so anything above 255 is clamped rather than silently corrupting
   * the stream (`btoa` would throw outright).
   *
   * The chunk size also matters: spreading a subarray into `String.fromCharCode`
   * passes one argument per cell, and a large enough chunk exceeds the engine's
   * argument limit. 8192 keeps it well clear.
   */
  public serializeLite(): string {
    const t = this.gridType;
    let raw = "";
    const chunk = 8192;
    for (let i = 0; i < t.length; i += chunk) {
      const end = Math.min(t.length, i + chunk);
      const bytes: number[] = [];
      for (let k = i; k < end; k++) bytes.push(liteByte(t[k]));
      raw += String.fromCharCode(...bytes);
    }
    return JSON.stringify({ w: this.width, h: this.height, t: btoa(raw), gx: this.gravityX, gy: this.gravityY });
  }

  public deserializeLite(json: string) {
    try {
      const o = JSON.parse(json) as { w: number; h: number; t: string; gx?: number; gy?: number };
      if (!PowderEngine.isValidSize(o.w, o.h) || typeof o.t !== "string") return;
      if (o.w !== this.width || o.h !== this.height) {
        this.resize(o.w, o.h);
        // If the resize was refused, the payload does not describe this world.
        if (o.w !== this.width || o.h !== this.height) return;
      }
      // Reset first. The original wrote element ids straight over the existing grid
      // without clearing, so every cell kept the PREVIOUS world's temperature,
      // lifetime, momentum and pressure under a brand-new layout: incoming ice
      // landed at 1200°C where lava had been and melted immediately, and incoming
      // fire or smoke inherited a lifetime of 0 and vanished on the next tick. This
      // is the payload a joining multiplayer peer receives, so it mattered.
      //
      // Decoded BEFORE the reset, so a payload that turns out to be undecodable
      // leaves the world alone. Resetting first meant one malformed message from a
      // peer wiped the receiving player's world and logged a line to the console.
      const bin = atob(o.t);
      this.resetGrid();
      const n = Math.min(this.gridType.length, bin.length);
      for (let i = 0; i < n; i++) {
        const id = bin.charCodeAt(i);
        this.gridType[i] = id;
        // Give each cell the temperature and lifetime its element should start with,
        // since the lite format does not carry them.
        const def = this.registry.getElement(id);
        this.gridTemp[i] = def.defaultTemp !== undefined ? def.defaultTemp : this.ambientTemp;
        this.gridLife[i] = def.decayTicks || 0;
      }
      if (typeof o.gx === "number" && Number.isFinite(o.gx)) this.gravityX = o.gx;
      if (typeof o.gy === "number" && Number.isFinite(o.gy)) this.gravityY = o.gy;
    } catch (err) {
      debug.error("Failed to parse lite grid payload", err);
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
        // The declared size decides the row stride the cells are written at, so a
        // payload that does not declare a usable size cannot be applied at all.
        //
        // This used to guard only the resize and then fall through, blitting the cells
        // into whatever the current grid's stride happened to be — every row landing
        // at the wrong offset, the whole world sheared, and no error anywhere. The
        // same happened when the resize itself was refused, which is why the result is
        // re-checked rather than assumed.
        if (!PowderEngine.isValidSize(obj.width, obj.height)) {
          debug.error("Refusing a grid state with an unusable size", obj.width, obj.height);
          return;
        }
        if (obj.width !== this.width || obj.height !== this.height) {
          this.resize(obj.width, obj.height);
          if (obj.width !== this.width || obj.height !== this.height) {
            debug.error("Could not resize to the saved grid size; leaving the world alone");
            return;
          }
        }
        this.resetGrid();
        const len = Math.min(this.width * this.height, obj.gridType.length);
        // Every value is validated on the way in. Scene files are user data: a raw id
        // of 9999 used to sit in the grid forever behaving as air but counting as an
        // active particle, and a string in the temperature array became NaN and then
        // spread through heat diffusion to poison the whole world.
        for (let i = 0; i < len; i++) {
          const id = Number(obj.gridType[i]);
          // Bounded by what the registry can actually describe. See MAX_ELEMENT_ID:
          // the old ceiling of 500 admitted a band of ids that drew as air, behaved as
          // air, could not be cleared by the repair tools, and still counted as active
          // particles forever.
          this.gridType[i] =
            Number.isInteger(id) && id >= 0 && id <= MAX_ELEMENT_ID ? id : EMPTY_ELEMENT_ID;
        }
        if (Array.isArray(obj.gridTemp)) {
          const tlen = Math.min(len, obj.gridTemp.length);
          for (let i = 0; i < tlen; i++) {
            const t = Number(obj.gridTemp[i]);
            this.gridTemp[i] = Number.isFinite(t) ? t : this.ambientTemp;
          }
        }
        if (Array.isArray(obj.gridLife)) {
          const llen = Math.min(len, obj.gridLife.length);
          for (let i = 0; i < llen; i++) {
            const l = Number(obj.gridLife[i]);
            this.gridLife[i] = Number.isFinite(l) && l >= 0 ? l : 0;
          }
        }
        if (Number.isFinite(Number(obj.gravityX))) this.gravityX = Number(obj.gravityX);
        if (Number.isFinite(Number(obj.gravityY))) this.gravityY = Number(obj.gravityY);
        // Routed through setWind so the [-5, 5] clamp applies here too. Assigning
        // windX directly bypassed it, which no other caller is allowed to do.
        if (Number.isFinite(Number(obj.windX))) this.setWind(Number(obj.windX));
        if (Number.isFinite(Number(obj.ambientTemp))) this.ambientTemp = Number(obj.ambientTemp);
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
