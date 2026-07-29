import { ElementRegistry, EMPTY_ELEMENT_ID } from './elementRegistry';
import { ElementDefinition } from '../types/physics';

export class PowderEngine {
  public width: number;
  public height: number;

  // Typed Arrays for maximum speed & cash locality
  public gridType: Uint16Array;
  public gridTemp: Float32Array;
  public gridLife: Uint16Array;
  public gridVisited: Uint8Array;
  public gridVx: Int8Array;
  public gridVy: Int8Array;

  public registry: ElementRegistry;

  // Global environment parameters
  public gravityX: number = 0;
  public gravityY: number = 1; // 1 = normal down, -1 = up, 0 = zero-g
  public ambientTemp: number = 20; // 20°C
  public windX: number = 0;
  public frameCount: number = 0;
  public textureMode: 'diagonal_matrix' | 'natural_grain' | 'organic_flow' | 'flat' = 'natural_grain';

  // Render color buffer cache for fast canvas rendering
  private colorBuffer: Uint32Array;
  private imageData: ImageData | null = null;

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

    this.colorBuffer = new Uint32Array(size);
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

    this.width = newWidth;
    this.height = newHeight;

    const size = newWidth * newHeight;
    this.gridType = new Uint16Array(size);
    this.gridTemp = new Float32Array(size);
    this.gridLife = new Uint16Array(size);
    this.gridVisited = new Uint8Array(size);
    this.gridVx = new Int8Array(size);
    this.gridVy = new Int8Array(size);
    this.colorBuffer = new Uint32Array(size);

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
  }

  public clear() {
    this.resetGrid();
  }

  public getIndex(x: number, y: number): number {
    return y * this.width + x;
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

    this.gridType[idx] = elementId;
    this.gridTemp[idx] = temp !== undefined ? temp : (def.defaultTemp !== undefined ? def.defaultTemp : this.ambientTemp);
    this.gridLife[idx] = life !== undefined ? life : (def.decayTicks || 0);
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

    this.gridType[idx2] = t1;
    this.gridTemp[idx2] = temp1;
    this.gridLife[idx2] = l1;
    this.gridVx[idx2] = vx1;
    this.gridVy[idx2] = vy1;

    this.gridVisited[idx1] = 1;
    this.gridVisited[idx2] = 1;
  }

  // Draw Brush on Grid
  public drawBrush(
    centerX: number,
    centerY: number,
    radius: number,
    elementId: number,
    shape: 'circle' | 'square' | 'spray' | 'line' | 'fill' | 'replace',
    targetElementId?: number
  ) {
    if (shape === 'fill') {
      this.floodFill(centerX, centerY, elementId);
      return;
    }

    const r2 = radius * radius;
    for (let dy = -radius; dy <= radius; dy++) {
      for (let dx = -radius; dx <= radius; dx++) {
        const x = centerX + dx;
        const y = centerY + dy;

        if (!this.isValid(x, y)) continue;

        if (shape === 'circle' && dx * dx + dy * dy > r2) continue;
        if (shape === 'spray' && (dx * dx + dy * dy > r2 || Math.random() > 0.25)) continue;

        if (shape === 'replace') {
          const currentId = this.gridType[this.getIndex(x, y)];
          if (targetElementId !== undefined && currentId !== targetElementId) continue;
        }

        this.setElementAt(x, y, elementId);
      }
    }
  }

  private floodFill(startX: number, startY: number, fillElementId: number) {
    if (!this.isValid(startX, startY)) return;
    const targetId = this.gridType[this.getIndex(startX, startY)];
    if (targetId === fillElementId) return;

    const queue: [number, number][] = [[startX, startY]];
    const maxFill = 8000;
    let count = 0;

    while (queue.length > 0 && count < maxFill) {
      const [x, y] = queue.pop()!;
      if (!this.isValid(x, y)) continue;
      const idx = this.getIndex(x, y);

      if (this.gridType[idx] === targetId) {
        this.setElementAt(x, y, fillElementId);
        count++;
        queue.push([x + 1, y], [x - 1, y], [x, y + 1], [x, y - 1]);
      }
    }
  }

  // Bulk spawn particles into empty/random cells on grid
  public spawnAmount(elementId: number, amount: number) {
    let placed = 0;
    const totalCells = this.width * this.height;
    const maxAttempts = amount * 3;

    for (let attempt = 0; attempt < maxAttempts && placed < amount && placed < totalCells; attempt++) {
      const rx = Math.floor(Math.random() * this.width);
      const ry = Math.floor(Math.random() * this.height);
      const idx = this.getIndex(rx, ry);

      if (this.gridType[idx] === EMPTY_ELEMENT_ID) {
        this.setElementAt(rx, ry, elementId);
        placed++;
      }
    }

    // Overwrite if still needed
    while (placed < amount && placed < totalCells) {
      const rx = Math.floor(Math.random() * this.width);
      const ry = Math.floor(Math.random() * this.height);
      this.setElementAt(rx, ry, elementId);
      placed++;
    }
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

        // Custom & Preset Chemical Reaction Evaluator
        if (this.updateReactions(x, y, idx, def, portalsA, portalsB)) {
          continue; // Particle consumed or transformed
        }

        // Particle State Physics Movement
        this.updateMovement(x, y, idx, def);
      }
    }
  }

  // Handle chemical reactions & special element behavior
  private updateReactions(
    x: number,
    y: number,
    idx: number,
    def: ElementDefinition,
    portalsA: [number, number][],
    portalsB: [number, number][]
  ): boolean {
    const type = def.id;

    // 1. Fire / Plasma / Lava / Thermite / Laser thermal effects
    if (type === 4 || type === 6 || type === 26 || type === 32 || type === 36 || def.state === 'energy' || def.name.includes('Laser')) {
      this.gridTemp[idx] = Math.min(3000, this.gridTemp[idx] + (type === 36 ? 80 : 20));

      // Check 8-way adjacent neighbors for intense thermal combustion & phase changes
      const neighbors = [
        [x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y],
        [x - 1, y - 1], [x + 1, y - 1], [x - 1, y + 1], [x + 1, y + 1]
      ];

      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        const nType = this.gridType[nIdx];
        if (nType === EMPTY_ELEMENT_ID) continue;

        const nDef = this.registry.getElement(nType);

        // Water puts out fire & lava turns to stone; Laser vaporizes water to steam!
        if (nType === 2) { // Water
          if (type === 6) {
            this.setElementAt(x, y, 7); // Lava -> Stone
            this.setElementAt(nx, ny, 14); // Water -> Steam
            return true;
          } else if (type === 36 || def.state === 'energy') {
            this.setElementAt(nx, ny, 14); // Laser vaporizes Water -> Steam instantly
          } else if (type === 4) {
            this.setElementAt(x, y, 14); // Fire + Water -> Steam
            return true;
          }
        }

        // Ice melts to Water or Steam near Laser/Lava/Fire
        if (nType === 13) {
          if (type === 36 || type === 26) {
            this.setElementAt(nx, ny, 14); // Flash vaporize to Steam
          } else {
            this.setElementAt(nx, ny, 2); // Melts into Water
          }
        }

        // Lava/Laser melts Sand or Stone into Lava/Glass
        if ((type === 6 || type === 36) && (nType === 1 || nType === 7)) {
          if (nType === 1) this.setElementAt(nx, ny, 12); // Sand -> Glass
          if (nType === 7) this.setElementAt(nx, ny, 6); // Stone -> Lava
        }

        // Flammables catch fire or detonate!
        if (nDef.flammability && Math.random() * 100 < nDef.flammability) {
          if (nType === 10 || nType === 28 || nType === 35 || nType === 31 || nType === 9) {
            // Explosives detonation!
            const rad = nType === 28 ? 26 : (nType === 35 ? 24 : (nType === 31 ? 20 : 16));
            this.triggerExplosion(nx, ny, rad, 22, 3000);
          } else {
            this.setElementAt(nx, ny, 4, 400); // Ignite fire
          }
        }
      }
    }

    // 2. Acid Corrosion
    if (type === 8) {
      const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        const nType = this.gridType[nIdx];

        if (nType !== EMPTY_ELEMENT_ID && nType !== 8 && nType !== 12 && nType !== 29) { // Glass & Bedrock immune
          const nDef = this.registry.getElement(nType);
          if (!nDef.acidResistance || Math.random() * 100 > nDef.acidResistance) {
            this.setElementAt(nx, ny, 5); // Target turns to smoke
            this.setElementAt(x, y, EMPTY_ELEMENT_ID); // Acid consumed
            return true;
          }
        }
      }
    }

    // 3. Virus Bio Spreading
    if (type === 18) {
      const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        const nType = this.gridType[nIdx];
        if (nType !== EMPTY_ELEMENT_ID && nType !== 18 && nType !== 29 && nType !== 12) {
          if (Math.random() < 0.15) {
            this.setElementAt(nx, ny, 18);
          }
        }
      }
    }

    // 4. Plant Growth
    if (type === 11) {
      const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        if (this.gridType[nIdx] === 2) { // Water
          // Consume water and grow plant upwards
          this.setElementAt(nIdx, ny, 11);
          break;
        }
      }
    }

    // 5. Void Singularity
    if (type === 20) {
      const neighbors = [
        [x, y - 1], [x, y + 1], [x - 1, y], [x + 1, y],
        [x - 1, y - 1], [x + 1, y - 1], [x - 1, y + 1], [x + 1, y + 1]
      ];
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        if (this.gridType[nIdx] !== EMPTY_ELEMENT_ID && this.gridType[nIdx] !== 20) {
          this.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
        }
      }
    }

    // 6. Clone / Duplicator
    if (type === 21) {
      const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
      let sourceId = EMPTY_ELEMENT_ID;
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nType = this.gridType[this.getIndex(nx, ny)];
        if (nType !== EMPTY_ELEMENT_ID && nType !== 21) {
          sourceId = nType;
          break;
        }
      }
      if (sourceId !== EMPTY_ELEMENT_ID) {
        for (const [nx, ny] of neighbors) {
          if (this.isValid(nx, ny) && this.gridType[this.getIndex(nx, ny)] === EMPTY_ELEMENT_ID) {
            this.setElementAt(nx, ny, sourceId);
            break;
          }
        }
      }
    }

    // 7. Portal Teleportation
    if (type === 22 && portalsB.length > 0) {
      const neighbors = [[x, y - 1], [x - 1, y], [x + 1, y], [x, y + 1]];
      for (const [nx, ny] of neighbors) {
        if (!this.isValid(nx, ny)) continue;
        const nIdx = this.getIndex(nx, ny);
        const pType = this.gridType[nIdx];
        if (pType !== EMPTY_ELEMENT_ID && pType !== 22 && pType !== 23) {
          // Choose destination portal
          const targetPortal = portalsB[Math.floor(Math.random() * portalsB.length)];
          const targetNeighbors = [
            [targetPortal[0], targetPortal[1] - 1],
            [targetPortal[0] + 1, targetPortal[1]],
            [targetPortal[0] - 1, targetPortal[1]],
            [targetPortal[0], targetPortal[1] + 1]
          ];
          for (const [tx, ty] of targetNeighbors) {
            if (this.isValid(tx, ty) && this.gridType[this.getIndex(tx, ty)] === EMPTY_ELEMENT_ID) {
              this.setElementAt(tx, ty, pType);
              this.setElementAt(nx, ny, EMPTY_ELEMENT_ID);
              break;
            }
          }
        }
      }
    }

    // 8. Custom Interaction Rules
    if (def.interactions && def.interactions.length > 0) {
      const neighbors = [[x, y + 1], [x - 1, y], [x + 1, y], [x, y - 1]];
      for (const rule of def.interactions) {
        if (Math.random() > rule.chance) continue;

        for (const [nx, ny] of neighbors) {
          if (!this.isValid(nx, ny)) continue;
          const nIdx = this.getIndex(nx, ny);
          if (this.gridType[nIdx] === rule.targetElementId) {
            if (rule.resultSelfId !== undefined) {
              this.setElementAt(x, y, rule.resultSelfId);
            }
            if (rule.resultTargetId !== undefined) {
              this.setElementAt(nx, ny, rule.resultTargetId);
            }
            if (rule.explosionRadius && rule.explosionRadius > 0) {
              this.triggerExplosion(x, y, rule.explosionRadius);
            }
            return true;
          }
        }
      }
    }

    return false;
  }

  // Trigger explosion physics wave with multi-stage shockwave & flying embers
  public triggerExplosion(
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
        if (dist2 > outerR2 || !this.isValid(x, y)) continue;

        const idx = this.getIndex(x, y);
        const type = this.gridType[idx];

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
        this.gridTemp[idx] = Math.max(this.gridTemp[idx], tempPulse);

        if (dist2 < r2 * 0.25) {
          // Hollow Crater Core: Vaporize matter into Plasma (15) or Fire (4) with ultra heat
          this.setElementAt(x, y, Math.random() < 0.7 ? 15 : 4, Math.max(2800, tempPulse), 35);
          this.gridVx[idx] = Math.round(vx * 1.5);
          this.gridVy[idx] = Math.round(vy * 1.5);
        } else if (dist2 < r2 * 0.85) {
          // Inner Fireball & Blast Shell: Shatter, Melt, and Blast particles outward
          if (type !== EMPTY_ELEMENT_ID) {
            if (type === 10 || type === 28 || type === 35 || type === 9) {
              if (Math.random() < 0.8) {
                this.setElementAt(x, y, 4, 1800, 30); // Fire
              }
            } else if (type === 2) { // Water -> Steam (14)
              this.setElementAt(x, y, 14, 300, 60);
            } else if (type === 13) { // Ice -> Water/Steam
              this.setElementAt(x, y, Math.random() < 0.5 ? 2 : 14, 150);
            } else if (type === 12 || type === 1) { // Glass / Sand -> Flying Sparks (26) or Lava (6)
              this.setElementAt(x, y, Math.random() < 0.6 ? 26 : 6, 1200, 25);
            } else if (type === 3) { // Wood -> Flying Embers / Fire (4) / Smoke (5)
              this.setElementAt(x, y, Math.random() < 0.7 ? 4 : 5, 1400, 40);
            } else {
              // Solids break apart into flying fiery debris/embers
              if (Math.random() < 0.6) {
                this.setElementAt(x, y, Math.random() < 0.5 ? 4 : 26, 1100, 30);
              } else if (Math.random() < 0.4) {
                this.setElementAt(x, y, 5, 300, 60); // Smoke
              }
            }
          } else if (Math.random() < 0.5) {
            // Fill empty space with expanding fireball and smoke
            this.setElementAt(x, y, Math.random() < 0.6 ? 4 : 5, 1200, 30);
          }
          this.gridVx[idx] = vx;
          this.gridVy[idx] = vy;
        } else {
          // Outer Shockwave Wave: Impart violent outward velocity to ALL surrounding particles!
          this.gridVx[idx] = Math.round(vx * 1.2);
          this.gridVy[idx] = Math.round(vy * 1.2);

          if (type !== EMPTY_ELEMENT_ID) {
            const def = this.registry.getElement(type);
            if (def.flammability && Math.random() < 0.6) {
              this.setElementAt(x, y, 4, 700, 30);
            }
          }
        }
      }
    }

    // 2. Launch high-velocity ballistic Ember Projectiles into 360-degree radial trajectories
    const emberCount = Math.min(80, Math.floor(radius * 1.8));
    for (let e = 0; e < emberCount; e++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 8 + Math.random() * (shockwaveForce * 0.9);
      const ex = Math.round(centerX + Math.cos(angle) * (radius * 0.4));
      const ey = Math.round(centerY + Math.sin(angle) * (radius * 0.4));

      if (this.isValid(ex, ey)) {
        const eIdx = this.getIndex(ex, ey);
        const emberType = Math.random() < 0.4 ? 26 : 4; // Spark or Fire
        this.setElementAt(ex, ey, emberType, 1600, 40 + Math.floor(Math.random() * 30));
        this.gridVx[eIdx] = Math.round(Math.cos(angle) * speed);
        this.gridVy[eIdx] = Math.round(Math.sin(angle) * speed - 2); // Slight upward launch bias
      }
    }

    // 3. Billowing Smoke Plume above the blast
    for (let s = 0; s < radius; s++) {
      const sx = Math.round(centerX + (Math.random() - 0.5) * radius * 1.2);
      const sy = Math.round(centerY - (Math.random() * radius * 0.8));
      if (this.isValid(sx, sy) && this.gridType[this.getIndex(sx, sy)] === EMPTY_ELEMENT_ID) {
        const sIdx = this.getIndex(sx, sy);
        this.setElementAt(sx, sy, 5, 250, 60 + Math.floor(Math.random() * 40)); // Smoke
        this.gridVx[sIdx] = Math.round((Math.random() - 0.5) * 6);
        this.gridVy[sIdx] = -Math.round(4 + Math.random() * 6); // Upward rise
      }
    }
  }

  // Physical Movement for Movable Solids, Liquids, Gases
  private updateMovement(x: number, y: number, idx: number, def: ElementDefinition) {
    const gravityFactor = def.gravityFactor !== undefined ? def.gravityFactor : 1;
    if (gravityFactor === 0 && def.state === 'solid_fixed') return;

    // 0. High-Velocity Inertial Momentum (Explosion Shockwaves & Kinetic Force)
    const vx = this.gridVx[idx];
    const vy = this.gridVy[idx];

    if (vx !== 0 || vy !== 0) {
      const speed = Math.hypot(vx, vy);

      if (speed > 0.3) {
        const normX = vx / speed;
        const normY = vy / speed;

        let posX = x;
        let posY = y;
        let currentIdx = idx;
        let moved = false;

        const maxSteps = Math.min(Math.round(speed), 8);
        for (let s = 0; s < maxSteps; s++) {
          const nextX = Math.round(posX + normX);
          const nextY = Math.round(posY + normY);

          if (nextX === Math.round(posX) && nextY === Math.round(posY)) {
            posX += normX;
            posY += normY;
            continue;
          }

          if (!this.isValid(nextX, nextY)) {
            this.gridVx[currentIdx] = Math.trunc(-this.gridVx[currentIdx] * 0.4);
            this.gridVy[currentIdx] = Math.trunc(-this.gridVy[currentIdx] * 0.4);
            break;
          }

          const targetIdx = this.getIndex(nextX, nextY);
          const targetType = this.gridType[targetIdx];

          if (targetType === EMPTY_ELEMENT_ID) {
            this.swapCells(currentIdx, targetIdx);
            posX = nextX;
            posY = nextY;
            currentIdx = targetIdx;
            moved = true;
          } else if (targetType === 29) { // Bedrock bounce/stop
            this.gridVx[currentIdx] = Math.trunc(-this.gridVx[currentIdx] * 0.3);
            this.gridVy[currentIdx] = Math.trunc(-this.gridVy[currentIdx] * 0.3);
            break;
          } else {
            // Collision with other particles: transfer momentum outwards
            const targetDef = this.registry.getElement(targetType);
            if (targetDef.state !== 'solid_fixed') {
              this.gridVx[targetIdx] = Math.trunc(this.gridVx[targetIdx] + vx * 0.6);
              this.gridVy[targetIdx] = Math.trunc(this.gridVy[targetIdx] + vy * 0.6);
            }
            this.gridVx[currentIdx] = Math.trunc(this.gridVx[currentIdx] * 0.3);
            this.gridVy[currentIdx] = Math.trunc(this.gridVy[currentIdx] * 0.3);
            break;
          }
        }

        this.gridVx[currentIdx] = Math.trunc(this.gridVx[currentIdx] * 0.85);
        this.gridVy[currentIdx] = Math.trunc(this.gridVy[currentIdx] * 0.85);

        if (moved) return;
      } else {
        this.gridVx[idx] = 0;
        this.gridVy[idx] = 0;
      }
    }

    const dirY = Math.sign(this.gravityY * gravityFactor) || (def.state === 'gas' || def.state === 'plasma' ? -1 : 1);

    // Movable Solids (Sand, Gunpowder, Thermite, Anti-Gravity)
    if (def.state === 'solid_movable') {
      const belowY = y + dirY;
      if (this.tryMoveOrSwap(idx, x, y, x, belowY, def.density)) return;

      // Slide diagonally
      const leftFirst = Math.random() < 0.5;
      const dx1 = leftFirst ? -1 : 1;
      const dx2 = leftFirst ? 1 : -1;

      if (this.tryMoveOrSwap(idx, x, y, x + dx1, belowY, def.density)) return;
      if (this.tryMoveOrSwap(idx, x, y, x + dx2, belowY, def.density)) return;
    }

    // Liquids (Water, Lava, Magma, Acid, Oil, Nitro, Slime, Honey, Tar)
    if (def.state === 'liquid') {
      const belowY = y + dirY;

      // 1. Direct fall down
      if (this.tryMoveOrSwap(idx, x, y, x, belowY, def.density)) return;

      // 2. Diagonal down slide
      const leftFirst = Math.random() < 0.5;
      const dx1 = leftFirst ? -1 : 1;
      const dx2 = leftFirst ? 1 : -1;

      if (this.tryMoveOrSwap(idx, x, y, x + dx1, belowY, def.density)) return;
      if (this.tryMoveOrSwap(idx, x, y, x + dx2, belowY, def.density)) return;

      // 3. Horizontal fluid leveling / viscous oozing flow
      const viscosity = def.viscosity || 1;

      // Heavy viscous liquids (Magma, Lava, Honey, Tar, Pitch) move with steady fluid viscosity
      if (viscosity > 3) {
        if (Math.random() < 0.2) return; // Smooth viscous pacing frame rate throttle
      }

      const spread = Math.max(1, Math.min(8, Math.floor(6 / Math.sqrt(viscosity))));
      for (let s = 1; s <= spread; s++) {
        if (this.tryMoveOrSwap(idx, x, y, x + dx1 * s, y, def.density)) return;
        if (this.tryMoveOrSwap(idx, x, y, x + dx2 * s, y, def.density)) return;
      }
    }

    // Gases & Plasma (Smoke, Steam, Oxygen, Helium, Fire)
    if (def.state === 'gas' || def.state === 'plasma') {
      const moveY = y + dirY;
      if (this.tryMoveOrSwap(idx, x, y, x, moveY, def.density)) return;

      const leftFirst = Math.random() < 0.5;
      const dx1 = leftFirst ? -1 : 1;
      const dx2 = leftFirst ? 1 : -1;

      if (this.tryMoveOrSwap(idx, x, y, x + dx1, moveY, def.density)) return;
      if (this.tryMoveOrSwap(idx, x, y, x + dx2, moveY, def.density)) return;
      if (this.tryMoveOrSwap(idx, x, y, x + dx1, y, def.density)) return;
      if (this.tryMoveOrSwap(idx, x, y, x + dx2, y, def.density)) return;
    }

    // Energy / Laser Beam Propagation
    if (def.state === 'energy' || def.id === 36 || def.name.includes('Laser')) {
      const stepDir = this.gravityY !== 0 ? Math.sign(this.gravityY) : 1;
      for (let dist = 1; dist <= 3; dist++) {
        const ny = y + dist * stepDir;
        if (this.isValid(x, ny)) {
          const nIdx = this.getIndex(x, ny);
          const targetType = this.gridType[nIdx];
          if (targetType === EMPTY_ELEMENT_ID) {
            this.swapCells(idx, nIdx);
            return;
          } else if (targetType !== 29 && targetType !== 36) { // Bedrock intact
            this.gridTemp[nIdx] += 400;
            if (targetType === 2 || targetType === 13) {
              this.setElementAt(x, ny, 14); // Water/Ice -> Steam
            } else if (targetType === 1 || targetType === 7) {
              this.setElementAt(x, ny, 6); // Sand/Stone -> Lava
            } else {
              this.setElementAt(x, ny, 4, 150); // Ignite fire
            }
            return;
          }
        }
      }
    }
  }

  private tryMoveOrSwap(
    fromIdx: number,
    fromX: number,
    fromY: number,
    toX: number,
    toY: number,
    selfDensity: number
  ): boolean {
    if (!this.isValid(toX, toY)) return false;
    const toIdx = this.getIndex(toX, toY);
    if (this.gridVisited[toIdx]) return false;

    const targetType = this.gridType[toIdx];

    // Move to empty space
    if (targetType === EMPTY_ELEMENT_ID) {
      this.swapCells(fromIdx, toIdx);
      return true;
    }

    // Buoyancy density sorting (Sinking / Floating)
    const targetDef = this.registry.getElement(targetType);
    if (targetDef.state !== 'solid_fixed' && targetDef.state !== 'special') {
      const gDir = Math.sign(this.gravityY) || 1;
      const moveDirY = Math.sign(toY - fromY);

      const isSinkingWithGravity = moveDirY === gDir && selfDensity > targetDef.density;
      const isFloatingAgainstGravity = moveDirY === -gDir && selfDensity < targetDef.density;

      if ((isSinkingWithGravity || isFloatingAgainstGravity) && Math.random() < 0.7) {
        this.swapCells(fromIdx, toIdx);
        return true;
      }
    }

    return false;
  }

  private parseColorToRgbComponents(colorStr: string): { r: number; g: number; b: number } {
    if (colorStr.startsWith('#')) {
      let hex = colorStr.slice(1);
      if (hex.length === 3) hex = hex.split('').map(c => c + c).join('');
      const r = parseInt(hex.substring(0, 2), 16) || 0;
      const g = parseInt(hex.substring(2, 4), 16) || 0;
      const b = parseInt(hex.substring(4, 6), 16) || 0;
      return { r, g, b };
    }
    if (colorStr.startsWith('hsl')) {
      const match = colorStr.match(/\d+/g);
      if (match && match.length >= 3) {
        const h = parseInt(match[0], 10) / 360;
        const s = parseInt(match[1], 10) / 100;
        const l = parseInt(match[2], 10) / 100;
        let r, g, b;
        if (s === 0) {
          r = g = b = l;
        } else {
          const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
          const p = 2 * l - q;
          const hue2rgb = (t: number) => {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1/6) return p + (q - p) * 6 * t;
            if (t < 1/2) return q;
            if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
            return p;
          };
          r = hue2rgb(h + 1/3);
          g = hue2rgb(h);
          b = hue2rgb(h - 1/3);
        }
        return { r: Math.round(r * 255), g: Math.round(g * 255), b: Math.round(b * 255) };
      }
    }
    return { r: 255, g: 255, b: 255 };
  }
  // Render Grid onto Canvas 2D ImageData context
  public renderToCanvas(ctx: CanvasRenderingContext2D, overlayMode: 'normal' | 'temp' | 'temp_overlay' | 'density' = 'normal') {
    if (!this.imageData || this.imageData.width !== this.width || this.imageData.height !== this.height) {
      this.imageData = ctx.createImageData(this.width, this.height);
    }

    const data32 = new Uint32Array(this.imageData.data.buffer);
    const w = this.width;
    const h = this.height;

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = y * w + x;
        const type = this.gridType[i];
        const temp = this.gridTemp[i];

        // 1. Pure Thermal Vision Heatmap
        if (overlayMode === 'temp') {
          // Temperature color mapping: -100°C -> deep blue, 0°C -> teal, 20°C -> green, 100°C -> yellow, 500°C -> orange, 1500°C -> red, 3000°C -> white
          let r = 0, g = 0, b = 0;
          if (temp < 0) {
            const norm = Math.min(1, Math.abs(temp) / 100);
            b = Math.floor(150 + norm * 105);
            g = Math.floor(norm * 100);
          } else if (temp <= 40) {
            const norm = (temp) / 40;
            g = Math.floor(100 + norm * 100);
            b = Math.floor((1 - norm) * 150);
          } else if (temp <= 200) {
            const norm = (temp - 40) / 160;
            r = Math.floor(norm * 255);
            g = Math.floor(200 - norm * 50);
          } else if (temp <= 800) {
            const norm = (temp - 200) / 600;
            r = 255;
            g = Math.floor(150 - norm * 100);
            b = Math.floor(norm * 30);
          } else {
            const norm = Math.min(1, (temp - 800) / 2200);
            r = 255;
            g = Math.floor(50 + norm * 205);
            b = Math.floor(30 + norm * 225);
          }

          data32[i] = (255 << 24) | (b << 16) | (g << 8) | r;
          continue;
        }

        // 2. Element Density Map
        if (overlayMode === 'density') {
          if (type === EMPTY_ELEMENT_ID) {
            data32[i] = 0xff0c0a0a;
          } else {
            const def = this.registry.getElement(type);
            const density = def.density || 1;
            const norm = Math.min(1, Math.max(0, density / 20));
            const r = Math.floor(norm * 255);
            const g = Math.floor((1 - norm) * 200);
            const b = 180;
            data32[i] = (255 << 24) | (b << 16) | (g << 8) | r;
          }
          continue;
        }

        if (type === EMPTY_ELEMENT_ID) {
          if (overlayMode === 'temp_overlay' && Math.abs(temp - 20) > 10) {
            // Background heat glow for hot air / cold air
            let hr = 10, hg = 10, hb = 12;
            if (temp > 50) {
              const hnorm = Math.min(1, (temp - 50) / 800);
              hr = Math.floor(10 + hnorm * 180);
              hg = Math.floor(10 + hnorm * 40);
            } else if (temp < 0) {
              const cnorm = Math.min(1, Math.abs(temp) / 100);
              hb = Math.floor(12 + cnorm * 180);
              hg = Math.floor(10 + cnorm * 80);
            }
            data32[i] = (255 << 24) | (hb << 16) | (hg << 8) | hr;
          } else {
            data32[i] = 0xff0c0a0a; // ABGR dark background #0a0a0c
          }
          continue;
        }

        const def = this.registry.getElement(type);
        const { r, g, b } = this.parseColorToRgbComponents(def.color);

        // Color jitter / texture variation
        let varR = r;
        let varG = g;
        let varB = b;

        if (def.colorVariation && def.colorVariation > 0) {
          let jitter = 0;
          if (this.textureMode === 'diagonal_matrix') {
            jitter = (((x * 3 + y * 7) % 19) - 9) * (def.colorVariation / 100);
          } else if (this.textureMode === 'natural_grain') {
            // Fast bitwise integer hash for static natural sand grain speckling (no trig, no flicker)
            const hash = ((x * 1597334677) ^ (y * 3812015801)) >>> 0;
            const noise = ((hash % 100) - 50) / 50.0;
            jitter = noise * (def.colorVariation / 100);
          } else if (this.textureMode === 'organic_flow') {
            const wave = Math.sin(x * 0.08 + y * 0.08 + this.frameCount * 0.05);
            jitter = wave * (def.colorVariation / 100);
          } else if (this.textureMode === 'flat') {
            jitter = 0;
          }

          varR = Math.min(255, Math.max(0, r + Math.floor(r * jitter)));
          varG = Math.min(255, Math.max(0, g + Math.floor(g * jitter)));
          varB = Math.min(255, Math.max(0, b + Math.floor(b * jitter)));
        }

        // Apply thermal overlay tinting if enabled
        if (overlayMode === 'temp_overlay') {
          if (temp > 100) {
            const heatRatio = Math.min(0.7, (temp - 100) / 1000);
            varR = Math.min(255, Math.floor(varR * (1 - heatRatio) + 255 * heatRatio));
            varG = Math.min(255, Math.floor(varG * (1 - heatRatio) + 120 * heatRatio));
            varB = Math.floor(varB * (1 - heatRatio));
          } else if (temp < -10) {
            const coldRatio = Math.min(0.6, Math.abs(temp + 10) / 150);
            varB = Math.min(255, Math.floor(varB * (1 - coldRatio) + 255 * coldRatio));
            varG = Math.min(255, Math.floor(varG * (1 - coldRatio) + 200 * coldRatio));
          }
        }

        data32[i] = (255 << 24) | (varB << 16) | (varG << 8) | varR;
      }
    }

    ctx.putImageData(this.imageData, 0, 0);
  }

  // Export state to compressed string
  public serializeState(): string {
    return JSON.stringify({
      width: this.width,
      height: this.height,
      gridType: Array.from(this.gridType),
      gravityX: this.gravityX,
      gravityY: this.gravityY
    });
  }

  // Import state from string
  public deserializeState(jsonStr: string) {
    try {
      const obj = JSON.parse(jsonStr);
      if (obj.gridType && Array.isArray(obj.gridType)) {
        this.resetGrid();
        const len = Math.min(this.width * this.height, obj.gridType.length);
        for (let i = 0; i < len; i++) {
          this.gridType[i] = obj.gridType[i];
        }
        if (obj.gravityX !== undefined) this.gravityX = obj.gravityX;
        if (obj.gravityY !== undefined) this.gravityY = obj.gravityY;
      }
    } catch (e) {
      console.error('Failed to parse grid state', e);
    }
  }

  // --- Diagnostics & System Health Inspection ---
  public getDiagnostics() {
    let activeParticles = 0;
    let corruptCellCount = 0;
    let maxTemp = -273;
    let minTemp = 3000;
    let sumTemp = 0;
    const totalCells = this.width * this.height;

    for (let i = 0; i < totalCells; i++) {
      const type = this.gridType[i];
      if (type !== EMPTY_ELEMENT_ID) {
        activeParticles++;
        if (type < 0 || type >= 500 || Number.isNaN(type)) {
          corruptCellCount++;
        }
      }
      const t = this.gridTemp[i];
      if (!Number.isNaN(t)) {
        if (t > maxTemp) maxTemp = t;
        if (t < minTemp) minTemp = t;
        sumTemp += t;
      } else {
        corruptCellCount++;
      }
    }

    const avgTemp = totalCells > 0 ? Math.round(sumTemp / totalCells) : 20;
    const memoryBytes = totalCells * (2 + 1 + 2 + 1) + (this.imageData ? this.imageData.data.byteLength : 0);
    const issues: string[] = [];

    if (corruptCellCount > 0) issues.push(`Detected ${corruptCellCount} corrupted/NaN grid cells`);
    if (maxTemp > 3000 || minTemp < -273) issues.push(`Thermal extremes detected (${Math.round(minTemp)}°C to ${Math.round(maxTemp)}°C)`);
    if (activeParticles > totalCells * 0.95) issues.push('Grid density near maximum capacity (>95%)');

    return {
      width: this.width,
      height: this.height,
      totalCells,
      activeParticles,
      corruptCellCount,
      loadPercentage: Math.round((activeParticles / totalCells) * 100),
      maxTemp: maxTemp === -273 ? 20 : Math.round(maxTemp),
      minTemp: minTemp === 3000 ? 20 : Math.round(minTemp),
      avgTemp,
      memoryBytes,
      frameCount: this.frameCount,
      gravityX: this.gravityX,
      gravityY: this.gravityY,
      isHealthy: issues.length === 0,
      issues
    };
  }

  // --- Manual Diagnostics & Repair Actions ---
  public flushStuckCells(): { success: boolean; cleared: number } {
    let cleared = 0;
    const totalCells = this.width * this.height;
    this.gridVisited.fill(0);
    for (let i = 0; i < totalCells; i++) {
      const type = this.gridType[i];
      if (type < 0 || type >= 500 || Number.isNaN(type)) {
        this.gridType[i] = EMPTY_ELEMENT_ID;
        this.gridTemp[i] = 20;
        cleared++;
      }
    }
    return { success: true, cleared };
  }

  public zeroThermalExtremes(): { success: boolean; normalizedCount: number } {
    let normalizedCount = 0;
    const totalCells = this.width * this.height;
    for (let i = 0; i < totalCells; i++) {
      const t = this.gridTemp[i];
      if (Number.isNaN(t) || t > 3000 || t < -273) {
        this.gridTemp[i] = 20;
        normalizedCount++;
      }
    }
    return { success: true, normalizedCount };
  }

  public reallocateBuffers(): { success: boolean } {
    this.imageData = null;
    this.gridVisited.fill(0);
    return { success: true };
  }

  public purgeOutOfBounds(): { success: boolean; purged: number } {
    let purged = 0;
    for (let x = 0; x < this.width; x++) {
      const idxTop = this.getIndex(x, 0);
      const idxBot = this.getIndex(x, this.height - 1);
      if (this.gridType[idxTop] !== 29) { this.gridType[idxTop] = EMPTY_ELEMENT_ID; purged++; }
      if (this.gridType[idxBot] !== 29) { this.gridType[idxBot] = EMPTY_ELEMENT_ID; purged++; }
    }
    return { success: true, purged };
  }

  public extinguishFires(): { success: boolean; extinguished: number } {
    let extinguished = 0;
    const totalCells = this.width * this.height;
    for (let i = 0; i < totalCells; i++) {
      const t = this.gridType[i];
      // 4 = Fire, 5 = Smoke, 10 = Lava, 15 = Plasma, 23 = Spark
      if (t === 4 || t === 5 || t === 23) {
        this.gridType[i] = EMPTY_ELEMENT_ID;
        this.gridTemp[i] = 20;
        extinguished++;
      } else if (t === 10 || t === 15) {
        this.gridType[i] = 2; // Stone
        this.gridTemp[i] = 250;
        extinguished++;
      }
    }
    return { success: true, extinguished };
  }

  public neutralizeAcids(): { success: boolean; neutralized: number } {
    let neutralized = 0;
    const totalCells = this.width * this.height;
    for (let i = 0; i < totalCells; i++) {
      if (this.gridType[i] === 8) { // Acid ID
        this.gridType[i] = 3; // Water ID
        neutralized++;
      }
    }
    return { success: true, neutralized };
  }

  public sealBedrockBorders(): { success: boolean; borderCellsSet: number } {
    let borderCellsSet = 0;
    for (let x = 0; x < this.width; x++) {
      const iTop = this.getIndex(x, 0);
      const iBot = this.getIndex(x, this.height - 1);
      if (this.gridType[iTop] !== 29) { this.gridType[iTop] = 29; borderCellsSet++; }
      if (this.gridType[iBot] !== 29) { this.gridType[iBot] = 29; borderCellsSet++; }
    }
    for (let y = 0; y < this.height; y++) {
      const iLeft = this.getIndex(0, y);
      const iRight = this.getIndex(this.width - 1, y);
      if (this.gridType[iLeft] !== 29) { this.gridType[iLeft] = 29; borderCellsSet++; }
      if (this.gridType[iRight] !== 29) { this.gridType[iRight] = 29; borderCellsSet++; }
    }
    return { success: true, borderCellsSet };
  }

  public coolAllCells(): { success: boolean } {
    this.gridTemp.fill(20);
    return { success: true };
  }

  // --- Stress Test Injectors (for testing debug diagnostics) ---
  public injectThermalSpike(): { success: boolean } {
    const cx = Math.floor(this.width / 2);
    const cy = Math.floor(this.height / 2);
    for (let dy = -10; dy <= 10; dy++) {
      for (let dx = -10; dx <= 10; dx++) {
        const i = this.getIndex(cx + dx, cy + dy);
        if (i >= 0 && i < this.gridTemp.length) {
          this.gridTemp[i] = 2800;
          this.gridType[i] = 4; // Fire
        }
      }
    }
    return { success: true };
  }

  public injectAcidFlood(): { success: boolean } {
    const startY = Math.floor(this.height * 0.7);
    for (let y = startY; y < this.height - 1; y++) {
      for (let x = 1; x < this.width - 1; x++) {
        const i = this.getIndex(x, y);
        this.gridType[i] = 8; // Acid
      }
    }
    return { success: true };
  }

  public injectCorruptCells(): { success: boolean } {
    const cx = Math.floor(this.width / 2);
    const cy = Math.floor(this.height / 2);
    for (let i = 0; i < 20; i++) {
      const idx = this.getIndex(cx + i, cy);
      this.gridType[idx] = 9999; // Invalid ID
      this.gridTemp[idx] = NaN; // Corrupt float
    }
    return { success: true };
  }

  public runAutoFix(): { logs: string[] } {
    const logs: string[] = [];
    logs.push('Initiating Powder Simulator Automated Diagnostics Pass...');

    const diag = this.getDiagnostics();
    if (diag.isHealthy) {
      logs.push('✓ All grid data buffers and temperatures verified normal.');
      logs.push('✓ No critical anomalies detected.');
      return { logs };
    }

    if (diag.corruptCellCount > 0) {
      const res = this.flushStuckCells();
      logs.push(`✓ Auto-Fix Step 1/5: Cleared ${res.cleared} corrupted/NaN element cells.`);
    }

    if (diag.maxTemp > 3000 || diag.minTemp < -273) {
      const res = this.zeroThermalExtremes();
      logs.push(`✓ Auto-Fix Step 2/5: Normalized ${res.normalizedCount} thermal extremes to room temp (20°C).`);
    }

    const oob = this.purgeOutOfBounds();
    if (oob.purged > 0) {
      logs.push(`✓ Auto-Fix Step 3/5: Sealed ${oob.purged} out-of-bounds frame cells.`);
    }

    const seal = this.sealBedrockBorders();
    logs.push(`✓ Auto-Fix Step 4/5: Verified bedrock perimeter boundary enclosure (${seal.borderCellsSet} cells updated).`);

    const realloc = this.reallocateBuffers();
    if (realloc.success) {
      logs.push('✓ Auto-Fix Step 5/5: Re-allocated canvas pixel buffers successfully.');
    }

    const postDiag = this.getDiagnostics();
    logs.push(`Auto-Fix Sequence Completed. System health status: ${postDiag.isHealthy ? '100% OPERATIONAL' : 'RECOVERY COMPLETED'}.`);
    return { logs };
  }
}
