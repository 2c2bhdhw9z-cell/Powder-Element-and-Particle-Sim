import { EMPTY_ELEMENT_ID } from "../element-registry";
import type { PowderCtx } from "./context";

/**
 * Explosion physics: multi-stage radial shockwave, shatter zone, ballistic
 * embers and a rising smoke plume.
 */
export function triggerExplosion(
  e: PowderCtx,
  centerX: number,
  centerY: number,
  radius: number,
  shockwaveForce: number = 22,
  maxHeat: number = 3000
) {
  const r2 = radius * radius;
  const outerRadius = Math.ceil(radius * 2.0);
  const outerR2 = outerRadius * outerRadius;

  // 1. Radial Blast Core, Shatter Zone & Kinetic Shockwave Wave
  for (let dy = -outerRadius; dy <= outerRadius; dy++) {
    for (let dx = -outerRadius; dx <= outerRadius; dx++) {
      const x = centerX + dx;
      const y = centerY + dy;
      const dist2 = dx * dx + dy * dy;
      if (dist2 > outerR2 || !e.isValid(x, y)) continue;

      const idx = e.getIndex(x, y);
      const type = e.gridType[idx];
      e.gridP[idx] += shockwaveForce * (1 - dist2 / (outerR2 + 1)) * 4;

      // Bedrock (29) is completely blast-proof
      if (type === 29) continue;

      const dist = Math.sqrt(dist2) || 0.1;
      const dirX = dx / dist;
      const dirY = dy / dist;

      // Falloff force
      const falloff = Math.pow(Math.max(0, 1 - dist / outerRadius), 0.8);
      const force = falloff * shockwaveForce;

      // Set outward shockwave velocity vector
      const vx = Math.round(dirX * force * (0.8 + Math.random() * 0.5));
      const vy = Math.round(dirY * force * (0.8 + Math.random() * 0.5));

      // Intense temperature pulse
      const tempPulse = Math.round(maxHeat * falloff);
      e.gridTemp[idx] = Math.max(e.gridTemp[idx], tempPulse);

      if (dist2 < r2 * 0.25) {
        // Hollow Crater Core: vaporize matter into Plasma (32) or Fire (4) with ultra heat.
        // This used to place 15 (C4 Explosive) while claiming to place plasma, so every
        // large blast seeded live charge at its own centre.
        e.setElementAt(x, y, Math.random() < 0.7 ? 32 : 4, Math.max(2800, tempPulse), 35);
        e.gridVx[idx] = Math.round(vx * 1.5);
        e.gridVy[idx] = Math.round(vy * 1.5);
      } else if (dist2 < r2 * 0.85) {
        // Inner Fireball & Blast Shell: Shatter, Melt, and Blast particles outward
        if (type !== EMPTY_ELEMENT_ID) {
          if (type === 10 || type === 28 || type === 35 || type === 9) {
            if (Math.random() < 0.8) {
              e.setElementAt(x, y, 4, 1800, 30); // Fire
            }
          } else if (type === 2) {
            // Water -> Steam (14)
            e.setElementAt(x, y, 14, 300, 60);
          } else if (type === 13) {
            // Ice -> Water/Steam
            e.setElementAt(x, y, Math.random() < 0.5 ? 2 : 14, 150);
          } else if (type === 12 || type === 1) {
            // Glass / Sand -> molten Thermite (26) or Lava (6). 26 is Thermite, not
            // Spark (16) as this comment used to claim.
            e.setElementAt(x, y, Math.random() < 0.6 ? 26 : 6, 1200, 25);
          } else if (type === 3) {
            // Wood -> Flying Embers / Fire (4) / Smoke (5)
            e.setElementAt(x, y, Math.random() < 0.7 ? 4 : 5, 1400, 40);
          } else {
            // Solids break apart into flying fiery debris/embers (26 is Thermite)
            if (Math.random() < 0.6) {
              e.setElementAt(x, y, Math.random() < 0.5 ? 4 : 26, 1100, 30);
            } else if (Math.random() < 0.4) {
              e.setElementAt(x, y, 5, 300, 60); // Smoke
            }
          }
        } else if (Math.random() < 0.5) {
          // Fill empty space with expanding fireball and smoke
          e.setElementAt(x, y, Math.random() < 0.6 ? 4 : 5, 1200, 30);
        }
        e.gridVx[idx] = vx;
        e.gridVy[idx] = vy;
      } else {
        // Outer Shockwave Wave: impart violent outward velocity to surrounding matter.
        //
        // Only to cells that actually hold something. Velocity written into empty air
        // is never damped, because `step()` skips empty cells — and `swapCells`
        // exchanges velocity, so the next particle to drift into that cell inherited
        // the stale shockwave and got launched seconds later for no visible reason.
        if (type !== EMPTY_ELEMENT_ID) {
          e.gridVx[idx] = Math.round(vx * 1.2);
          e.gridVy[idx] = Math.round(vy * 1.2);

          const def = e.registry.getElement(type);
          if (def.flammability && Math.random() < 0.6) {
            e.setElementAt(x, y, 4, 700, 30);
          }
        }
      }
    }
  }

  // 2. Launch high-velocity ballistic Ember Projectiles into 360-degree radial trajectories
  const emberCount = Math.min(80, Math.floor(radius * 1.8));
  for (let em = 0; em < emberCount; em++) {
    const angle = Math.random() * Math.PI * 2;
    const speed = 8 + Math.random() * (shockwaveForce * 0.9);
    const ex = Math.round(centerX + Math.cos(angle) * (radius * 0.4));
    const ey = Math.round(centerY + Math.sin(angle) * (radius * 0.4));

    // Bedrock is blast-proof and that has to hold here too. The radial blast above
    // skips it explicitly, but the ember phase used to overwrite it, so debris could
    // punch holes in a wall the explosion itself could not touch.
    if (e.isValid(ex, ey) && e.gridType[e.getIndex(ex, ey)] !== 29) {
      const eIdx = e.getIndex(ex, ey);
      const emberType = Math.random() < 0.4 ? 26 : 4; // Thermite or Fire
      e.setElementAt(ex, ey, emberType, 1600, 40 + Math.floor(Math.random() * 30));
      e.gridVx[eIdx] = Math.round(Math.cos(angle) * speed);
      e.gridVy[eIdx] = Math.round(Math.sin(angle) * speed - 2); // Slight upward launch bias
    }
  }

  // 3. Billowing Smoke Plume, rising against gravity.
  // Previously hardcoded upward, so under inverted gravity the plume was emitted
  // into the ground while everything else in the engine respected gravityY.
  const up = -(Math.sign(e.gravityY) || 1);
  for (let s = 0; s < radius; s++) {
    const sx = Math.round(centerX + (Math.random() - 0.5) * radius * 1.2);
    const sy = Math.round(centerY + up * (Math.random() * radius * 0.8));
    if (e.isValid(sx, sy) && e.gridType[e.getIndex(sx, sy)] === EMPTY_ELEMENT_ID) {
      const sIdx = e.getIndex(sx, sy);
      e.setElementAt(sx, sy, 5, 250, 60 + Math.floor(Math.random() * 40)); // Smoke
      e.gridVx[sIdx] = Math.round((Math.random() - 0.5) * 6);
      e.gridVy[sIdx] = Math.round(up * (4 + Math.random() * 6));
    }
  }

  e.onBurst?.(centerX, centerY, radius);
}
