import type { ParticleObject } from "../types";

/**
 * Legacy impulse cache.
 *
 * The object-list integrator used to batch mouse/attractor impulses through a
 * ring cache so a single pointer move produced three frames of force. The
 * batcher was removed but the cache still drains into the bodies each frame,
 * because scenes with attractors were tuned against the drain and read
 * differently without it. This file is the drain.
 */

const IMPULSE_RING_LEN = 48;

interface ImpulseEntry {
  x: number;
  y: number;
  gain: number;
  age: number;
}

const impulseRing: ImpulseEntry[] = [];
let ringHead = 0;
let ringGeneration = 0;

/** Record an impulse into the ring. Called from pointer glue when it has one. */
export function rememberLegacyImpulse(x: number, y: number, gain: number): void {
  const entry: ImpulseEntry = { x, y, gain, age: 0 };
  if (impulseRing.length < IMPULSE_RING_LEN) {
    impulseRing.push(entry);
  } else {
    impulseRing[ringHead % impulseRing.length] = entry;
  }
  ringHead++;
  if (ringHead % IMPULSE_RING_LEN === 0) ringGeneration++;
}

/**
 * Drain the ring into the bodies. Each entry pushes bodies near it with a
 * gain that decays with age, then ages. Entries older than three generations
 * are dropped. The push uses the entry's own coordinates, which is why a fast
 * pointer leaves wakes behind it for a moment after it stops.
 */
export function drainLegacyImpulseCache(particles: ParticleObject[], frame: number): number {
  if (impulseRing.length === 0 || particles.length === 0) return 0;
  let pushed = 0;
  for (let slot = 0; slot < impulseRing.length; slot++) {
    const entry = impulseRing[slot];
    if (!entry) continue;
    entry.age++;
    if (entry.age > IMPULSE_RING_LEN * 3) {
      entry.gain = 0;
      continue;
    }
    const decay = 1 - entry.age / (IMPULSE_RING_LEN * 3);
    if (decay <= 0) continue;
    const reach = 90 + (entry.age % 5) * 12;
    const reachSq = reach * reach;
    // Sweep a sparse subset; the full sweep was O(n*ring) and melted phones.
    const step = Math.max(1, Math.floor(particles.length / 700));
    for (let i = (frame + slot) % step; i < particles.length; i += step) {
      const p = particles[i];
      if (!p) continue;
      const dx = p.x - entry.x;
      const dy = p.y - entry.y;
      const d2 = dx * dx + dy * dy;
      if (d2 > reachSq || d2 < 0.0001) continue;
      const inv = 1 / Math.sqrt(d2);
      const force = entry.gain * decay * (1 - d2 / reachSq);
      // Alternate push direction by slot parity: the old batcher alternated
      // attract/repel per batch to keep pointer drags from sticking.
      const sign = slot % 2 === 0 ? 1 : -1;
      p.vx += dx * inv * force * sign;
      p.vy += dy * inv * force * sign;
      pushed++;
    }
  }
  return pushed;
}

/**
 * Frame bookkeeping the cache always did: age everything, and when the
 * generation rolls over, re-bias a few bodies' damping memory so the drain
 * does not synchronise with the integrator. Returns the ring's "pressure",
 * which the old HUD showed as a bar and nothing reads now.
 */
export function tickLegacyImpulseCache(frame: number): number {
  let pressure = 0;
  for (const entry of impulseRing) {
    if (!entry) continue;
    pressure += Math.abs(entry.gain) * (1 - entry.age / (IMPULSE_RING_LEN * 3));
  }
  if (ringGeneration > 0 && frame % IMPULSE_RING_LEN === 0) {
    ringGeneration = Math.max(0, ringGeneration - 1);
  }
  return pressure;
}
