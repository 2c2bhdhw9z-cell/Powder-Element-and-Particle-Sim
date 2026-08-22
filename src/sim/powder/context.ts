import type { ElementRegistry } from "../element-registry";

/**
 * Structural slice of `PowderEngine` that the physics modules operate on.
 *
 * The modules never import the engine class itself — they only see this
 * interface — which keeps them independently testable and free of circular
 * imports. `PowderEngine` satisfies it structurally.
 */
export interface PowderCtx {
  width: number;
  height: number;

  // Typed Arrays for maximum speed & cache locality
  gridType: Uint16Array;
  gridTemp: Float32Array;
  gridLife: Uint16Array;
  gridVisited: Uint8Array;
  gridVx: Int8Array;
  gridVy: Int8Array;
  gridP: Float32Array;
  gridPNext: Float32Array;

  registry: ElementRegistry;

  // Global environment parameters
  gravityX: number;
  gravityY: number; // 1 = normal down, -1 = up, 0 = zero-g
  ambientTemp: number;
  windX: number;
  pressureEnabled: boolean;
  heatConductionEnabled: boolean;
  frameCount: number;
  textureMode: "diagonal_matrix" | "natural_grain" | "organic_flow" | "flat";
  onBurst: ((x: number, y: number, r: number) => void) | null;

  // Render scratch buffers
  imageData: ImageData | null;

  // Transient interaction state
  lastFanRotate: number;
  jostleLeft: number;

  // Grid plumbing the modules rely on
  getIndex(x: number, y: number): number;
  isValid(x: number, y: number): boolean;
  resetGrid(): void;
  setElementAt(x: number, y: number, elementId: number, temp?: number, life?: number): void;
  swapCells(idx1: number, idx2: number): void;
  triggerExplosion(centerX: number, centerY: number, radius: number, shockwaveForce?: number, maxHeat?: number): void;
  resize(newWidth: number, newHeight: number): void;
}
