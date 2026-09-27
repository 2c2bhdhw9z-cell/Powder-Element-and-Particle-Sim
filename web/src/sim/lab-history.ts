import { getParticleEngine, getPowderEngine } from "./engines";

type Chamber = "powder" | "particle";

class LabHistory {
  private order: Chamber[] = [];
  private redoOrder: Chamber[] = [];

  record(mode: Chamber) {
    this.order.push(mode);
    if (this.order.length > 40) this.order.shift();
    this.redoOrder = [];
  }

  canUndo() {
    return this.order.length > 0 || getPowderEngine().canUndo() || getParticleEngine().canUndo();
  }

  canRedo() {
    return this.redoOrder.length > 0 || getPowderEngine().canRedo() || getParticleEngine().canRedo();
  }

  undo() {
    const mode = this.order.pop() ?? (getPowderEngine().canUndo() ? "powder" : "particle");
    const ok = mode === "powder" ? getPowderEngine().undo() : getParticleEngine().undo();
    if (ok) this.redoOrder.push(mode);
    return ok;
  }

  redo() {
    const mode = this.redoOrder.pop() ?? (getPowderEngine().canRedo() ? "powder" : "particle");
    const ok = mode === "powder" ? getPowderEngine().redo() : getParticleEngine().redo();
    if (ok) this.order.push(mode);
    return ok;
  }
}

export const labHistory = new LabHistory();
