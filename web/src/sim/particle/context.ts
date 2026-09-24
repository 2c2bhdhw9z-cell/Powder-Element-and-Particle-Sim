import type { ParticleObject } from "../types";
import type { Swarm } from "../swarm";

/**
 * Structural slice of `ParticleEngine` that the physics/render modules
 * operate on. The modules never import the engine class, which keeps them
 * independently testable and free of circular imports.
 */
export interface ParticleCtx {
  particles: ParticleObject[];
  springs: { a: number; b: number; rest: number; k: number }[];
  swarm: Swarm;

  width: number;
  height: number;

  gravityX: number;
  gravityY: number;
  damping: number;
  elasticity: number;
  electrostaticFactor: number;
  vortexForce: number;
  maxSpeed: number;
  boundaryMode: "bounce" | "wrap" | "void";
  mouseMode:
    | "attract"
    | "repel"
    | "vortex"
    | "emitter"
    | "painter"
    | "gravity_well"
    | "freeze"
    | "hawk"
    | "hyper_drive";
  mouseRadius: number;
  mouseForceMultiplier: number;
  lastMouseX: number;
  lastMouseY: number;
  lastMouseActive: boolean;
  colorMode: "element" | "velocity" | "charge" | "rainbow" | "density" | "lifespan";
  particleSize: number;
  maxParticles: number;
  showTrails: boolean;
  decaySpeed: number;
  collisionsEnabled: boolean;
  fluidEnabled: boolean;
  flockEnabled: boolean;
  nbodyEnabled: boolean;

  // Render scratch buffers
  imgData: ImageData | null;
  buf32: Uint32Array | null;

  // Lifecycle hooks
  onAfterStep: (() => void) | null;

  // Plumbing the modules rely on
  addParticle(particle: Partial<ParticleObject>): void;
  /**
   * Removes every particle matching the predicate, keeping spring endpoints valid.
   *
   * Springs store absolute indices into `particles`, so ANY code that drops or
   * shifts an element must go through here. Filtering the array directly silently
   * re-wires every spring below the removed index to a different pair whose rest
   * length no longer matches, which shears cloth and injects energy every frame
   * afterwards — and it fails silently, because the spring step can only detect an
   * out-of-range index, never a wrong one.
   *
   * @returns how many particles were removed.
   */
  removeParticles(shouldRemove: (particle: ParticleObject) => boolean): number;
  pushUndo(): void;
  clear(): void;
  parseColorToUint32(colorStr: string): number;
}
