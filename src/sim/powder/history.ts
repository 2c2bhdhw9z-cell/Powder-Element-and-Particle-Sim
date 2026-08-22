import type { PowderCtx } from "./context";

/**
 * A full grid state captured as typed-array copies.
 *
 * Replaces the old serialized-JSON snapshots: no per-cell JSON stringify/parse
 * churn (which was the dominant cost of undo at 240×160+ grids) and restore is
 * a straight memcpy instead of a field-by-field loop over parsed numbers.
 */
export interface PowderSnapshot {
  width: number;
  height: number;
  type: Uint16Array;
  temp: Float32Array;
  life: Uint16Array;
  gravityX: number;
  gravityY: number;
  windX: number;
  ambientTemp: number;
}

export class PowderHistory {
  private undoStack: PowderSnapshot[] = [];
  private redoStack: PowderSnapshot[] = [];
  private maxSteps: number;

  constructor(maxUndoSteps: number = 25) {
    this.maxSteps = maxUndoSteps;
  }

  /** Copy the current grid into a snapshot. */
  capture(e: PowderCtx): PowderSnapshot {
    return {
      width: e.width,
      height: e.height,
      type: e.gridType.slice(),
      temp: e.gridTemp.slice(),
      life: e.gridLife.slice(),
      gravityX: e.gravityX,
      gravityY: e.gravityY,
      windX: e.windX,
      ambientTemp: e.ambientTemp,
    };
  }

  /** Restore a snapshot (mirrors the old deserializeState grid semantics). */
  restore(e: PowderCtx, snap: PowderSnapshot) {
    if (snap.width !== e.width || snap.height !== e.height) e.resize(snap.width, snap.height);
    e.resetGrid();
    const len = Math.min(e.width * e.height, snap.type.length);
    e.gridType.set(snap.type.subarray(0, len));
    e.gridTemp.set(snap.temp.subarray(0, len));
    e.gridLife.set(snap.life.subarray(0, len));
    e.gravityX = snap.gravityX;
    e.gravityY = snap.gravityY;
    e.windX = snap.windX;
    e.ambientTemp = snap.ambientTemp;
  }

  /** Record the current state as an undo point (call BEFORE mutating). */
  push(e: PowderCtx) {
    try {
      this.undoStack.push(this.capture(e));
      if (this.undoStack.length > this.maxSteps) this.undoStack.shift();
      this.redoStack = [];
    } catch {
      /* never break a stroke over a snapshot failure */
    }
  }

  canUndo(): boolean {
    return this.undoStack.length > 0;
  }

  canRedo(): boolean {
    return this.redoStack.length > 0;
  }

  undo(e: PowderCtx): boolean {
    if (this.undoStack.length === 0) return false;
    this.redoStack.push(this.capture(e));
    const prev = this.undoStack.pop()!;
    this.restore(e, prev);
    return true;
  }

  redo(e: PowderCtx): boolean {
    if (this.redoStack.length === 0) return false;
    this.undoStack.push(this.capture(e));
    const next = this.redoStack.pop()!;
    this.restore(e, next);
    return true;
  }

  clear() {
    this.undoStack = [];
    this.redoStack = [];
  }
}
