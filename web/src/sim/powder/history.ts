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
    // At least one, always. A depth of zero made `push` discard the snapshot it had
    // just taken, so `canUndo` was permanently false and undo was silently dead with
    // nothing to indicate why.
    this.maxSteps = Number.isFinite(maxUndoSteps) ? Math.max(1, Math.floor(maxUndoSteps)) : 25;
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

  /**
   * Restore a snapshot.
   *
   * @returns whether the snapshot was applied. A refused resize is the one case where
   *   it cannot be, and the caller needs to know rather than be handed a broken world.
   */
  restore(e: PowderCtx, snap: PowderSnapshot): boolean {
    if (snap.width !== e.width || snap.height !== e.height) {
      e.resize(snap.width, snap.height);
      // Verified rather than assumed. `resize` returns quietly when the size is
      // unusable or an allocation fails, and the copy below would then write the
      // snapshot at the wrong row stride — every row landing at the wrong offset, the
      // whole world sheared, and nothing reported. The loaders re-check this; this did
      // not.
      if (snap.width !== e.width || snap.height !== e.height) return false;
    }

    // Ambient goes on before the clear, because the clear is what fills the grid with
    // it. Assigning it afterwards left every cell the snapshot did not cover holding
    // the temperature of the world being replaced.
    e.ambientTemp = snap.ambientTemp;
    e.resetGrid();

    const len = Math.min(e.width * e.height, snap.type.length);
    e.gridType.set(snap.type.subarray(0, len));
    e.gridTemp.set(snap.temp.subarray(0, len));
    e.gridLife.set(snap.life.subarray(0, len));
    e.gravityX = snap.gravityX;
    e.gravityY = snap.gravityY;
    // Through the clamp, like every other writer. A snapshot taken while `windX` held
    // an out-of-range value — it is a public field, so anything could have put one
    // there — preserved it verbatim through undo.
    e.setWind(snap.windX);
    return true;
  }

  /** Record the current state as an undo point (call BEFORE mutating). */
  push(e: PowderCtx) {
    // Cleared FIRST. The original cleared it last, inside the same try — so if
    // capturing threw (an allocation failure, which is exactly what the catch is
    // there for) the redo stack survived, still holding snapshots taken before the
    // mutation that was about to happen. A later redo would then apply a future that
    // never existed.
    this.redoStack = [];
    try {
      this.undoStack.push(this.capture(e));
      if (this.undoStack.length > this.maxSteps) this.undoStack.shift();
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

  /**
   * Capture without letting an allocation failure escape.
   *
   * `push` already tolerated a failed capture; `undo` and `redo` captured outside any
   * guard, so the very failure the guard exists for threw out of the engine and into
   * the interface instead. One policy, applied everywhere: a capture that fails costs
   * you the opposite-direction step, and nothing else.
   */
  private tryCapture(e: PowderCtx): PowderSnapshot | null {
    try {
      return this.capture(e);
    } catch {
      return null;
    }
  }

  undo(e: PowderCtx): boolean {
    if (this.undoStack.length === 0) return false;
    const current = this.tryCapture(e);
    const prev = this.undoStack.pop()!;
    if (!this.restore(e, prev)) {
      // Could not be applied, so put it back rather than losing the step.
      this.undoStack.push(prev);
      return false;
    }
    if (current) {
      this.redoStack.push(current);
      if (this.redoStack.length > this.maxSteps) this.redoStack.shift();
    }
    return true;
  }

  redo(e: PowderCtx): boolean {
    if (this.redoStack.length === 0) return false;
    const current = this.tryCapture(e);
    const next = this.redoStack.pop()!;
    if (!this.restore(e, next)) {
      this.redoStack.push(next);
      return false;
    }
    if (current) {
      this.undoStack.push(current);
      // Trimmed here as well as in push(). Without it, repeated undo/redo cycling grew
      // the undo stack past its own limit.
      if (this.undoStack.length > this.maxSteps) this.undoStack.shift();
    }
    return true;
  }

  clear() {
    this.undoStack = [];
    this.redoStack = [];
  }
}
