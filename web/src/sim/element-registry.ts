import { ElementDefinition } from './types';

// Element ID 0 is ALWAYS Empty / Air
export const EMPTY_ELEMENT_ID = 0;

export const DEFAULT_ELEMENTS: ElementDefinition[] = [
  {
    id: 0,
    name: 'Air',
    category: 'Gases',
    state: 'gas',
    color: '#0a0a0c',
    density: 0,
    gravityFactor: 0,
    description: 'Empty space',
  },
  {
    id: 1,
    name: 'Sand',
    category: 'Solids',
    state: 'solid_movable',
    color: '#e5c158',
    colorVariation: 15,
    density: 15,
    gravityFactor: 1,
    description: 'Basic falling powder grain.',
  },
  {
    id: 2,
    name: 'Water',
    category: 'Liquids',
    state: 'liquid',
    color: '#2a7ab8',
    colorVariation: 2,
    density: 10,
    viscosity: 1,
    gravityFactor: 1,
    heatConductivity: 0.8,
    description: 'Liquid water. Extinguishes fire and grows plants.',
  },
  {
    id: 3,
    name: 'Wood',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#8b5a2b',
    colorVariation: 12,
    density: 50,
    flammability: 40,
    burnRate: 2,
    gravityFactor: 0,
    description: 'Flammable solid structure.',
  },
  {
    id: 4,
    name: 'Fire',
    category: 'Energetic',
    state: 'plasma',
    color: '#f97316',
    colorVariation: 30,
    density: -1,
    gravityFactor: -0.8,
    defaultTemp: 600,
    decayTicks: 40,
    decayIntoId: 5, // Smoke
    description: 'Intense thermal plasma (600°C). Ignites flammables.',
  },
  {
    id: 5,
    name: 'Smoke',
    category: 'Gases',
    state: 'gas',
    color: '#64748b',
    colorVariation: 8,
    density: -2,
    gravityFactor: -0.5,
    defaultTemp: 150,
    decayTicks: 120,
    decayIntoId: 0,
    description: 'Rising gas byproduct of combustion.',
  },
  {
    id: 6,
    name: 'Lava',
    category: 'Liquids',
    state: 'liquid',
    color: '#ff3700',
    colorVariation: 35,
    density: 25,
    viscosity: 5,
    gravityFactor: 1,
    heatConductivity: 0.9,
    defaultTemp: 1200,
    description: 'Incandescent molten rock (1200°C). Oozes down slopes, ignites flammables, melts stone/sand, boils water.',
  },
  {
    id: 7,
    name: 'Stone',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#71717a',
    colorVariation: 10,
    density: 60,
    acidResistance: 20,
    gravityFactor: 0,
    heatConductivity: 0.45,
    description: 'Durable barrier rock.',
  },
  {
    id: 8,
    name: 'Acid',
    category: 'Liquids',
    state: 'liquid',
    color: '#a3e635',
    colorVariation: 20,
    density: 12,
    viscosity: 1,
    gravityFactor: 1,
    description: 'Corrosive green liquid that dissolves most elements.',
  },
  {
    id: 9,
    name: 'Oil',
    category: 'Liquids',
    state: 'liquid',
    color: '#3f3f46',
    colorVariation: 8,
    density: 8, // Floats on water!
    viscosity: 2,
    flammability: 90,
    burnRate: 5,
    gravityFactor: 1,
    description: 'Highly flammable petroleum. Floats on water.',
  },
  {
    id: 10,
    name: 'Gunpowder',
    category: 'Energetic',
    state: 'solid_movable',
    color: '#334155',
    colorVariation: 10,
    density: 18,
    flammability: 100,
    gravityFactor: 1,
    description: 'Explosive black powder grain. Detonates on fire/spark.',
  },
  {
    id: 11,
    name: 'Plant',
    category: 'Biological',
    state: 'solid_fixed',
    color: '#22c55e',
    colorVariation: 20,
    density: 30,
    flammability: 60,
    gravityFactor: 0,
    description: 'Organic vegetation. Spreads when fed with water!',
  },
  {
    id: 12,
    name: 'Glass',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#93c5fd',
    colorVariation: 5,
    density: 40,
    acidResistance: 100,
    gravityFactor: 0,
    description: 'Transparent acid-proof glass barrier.',
  },
  {
    id: 13,
    name: 'Ice',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#7dd3fc',
    colorVariation: 12,
    density: 9,
    gravityFactor: 0,
    defaultTemp: -15,
    description: 'Translucent icy frost (-15°C / 5°F). Freezes water, melts near heat/fire/laser into water.',
  },
  {
    id: 14,
    name: 'Steam',
    category: 'Gases',
    state: 'gas',
    color: '#9aafbf',
    colorVariation: 2,
    density: -3,
    gravityFactor: -0.85,
    defaultTemp: 120,
    description: 'Hot water vapor. Rises, then rains back when it cools.',
  },
  {
    id: 15,
    name: 'C4 Explosive',
    category: 'Energetic',
    state: 'solid_fixed',
    color: '#dc2626',
    colorVariation: 5,
    density: 50,
    flammability: 100,
    description: 'Stable explosive block. Powerful shockwave when triggered.',
  },
  {
    id: 16,
    name: 'Spark / Electricity',
    category: 'Energetic',
    state: 'energy',
    color: '#facc15',
    colorVariation: 30,
    density: 0,
    defaultTemp: 1000,
    decayTicks: 12,
    decayIntoId: 0,
    isConductor: true,
    description: 'Electrical arc. Seeks water and metal, then ignites fuel.',
  },
  {
    id: 17,
    name: 'Metal / Wire',
    category: 'Energetic',
    state: 'solid_fixed',
    color: '#94a3b8',
    colorVariation: 5,
    density: 80,
    isConductor: true,
    acidResistance: 80,
    heatConductivity: 0.55,
    description: 'Conductive metal. Passes sparks across distances.',
  },
  {
    id: 18,
    name: 'Virus',
    category: 'Biological',
    state: 'solid_movable',
    color: '#d946ef',
    colorVariation: 25,
    density: 14,
    gravityFactor: 1,
    description: 'Infectious bio-agent. Converts neighboring solids into Virus!',
  },
  {
    id: 19,
    name: 'Ant',
    category: 'Biological',
    state: 'solid_movable',
    color: '#78350f',
    colorVariation: 10,
    density: 12,
    gravityFactor: 1,
    description: 'Living insect. Crawls across surfaces and digs tunnels.',
  },
  {
    id: 20,
    name: 'Void',
    category: 'Special',
    state: 'solid_fixed',
    color: '#18181b',
    colorVariation: 0,
    density: 999,
    gravityFactor: 0,
    description: 'Black hole singularity. Consumes any particle touching it.',
  },
  {
    id: 21,
    name: 'Clone / Duplicator',
    category: 'Special',
    state: 'solid_fixed',
    color: '#06b6d4',
    colorVariation: 10,
    density: 999,
    description: 'Magical copier. Duplicates whichever particle touches it.',
  },
  {
    id: 22,
    name: 'Portal A',
    category: 'Special',
    state: 'solid_fixed',
    color: '#3b82f6',
    colorVariation: 15,
    density: 999,
    description: 'Teleports particles to Portal B.',
  },
  {
    id: 23,
    name: 'Portal B',
    category: 'Special',
    state: 'solid_fixed',
    color: '#f97316',
    colorVariation: 15,
    density: 999,
    description: 'Exit destination for Portal A.',
  },
  {
    id: 24,
    name: 'Anti-Gravity Powder',
    category: 'Special',
    state: 'solid_movable',
    color: '#ec4899',
    colorVariation: 20,
    density: 5,
    gravityFactor: -1,
    description: 'Powder that falls UPWARDS against gravity.',
  },
  {
    id: 25,
    name: 'Wax',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#fef08a',
    colorVariation: 8,
    density: 11,
    flammability: 80,
    description: 'Meltable wax block. Melts into liquid wax near heat.',
  },
  {
    id: 26,
    name: 'Thermite',
    category: 'Energetic',
    state: 'solid_movable',
    color: '#b91c1c',
    colorVariation: 15,
    density: 30,
    flammability: 100,
    defaultTemp: 2200,
    description: 'Ultra-hot incendiary compound (2200°C). Melts through steel and stone.',
  },
  {
    id: 27,
    name: 'Salt Water',
    category: 'Liquids',
    state: 'liquid',
    color: '#1d6fa8',
    colorVariation: 3,
    density: 11,
    viscosity: 1,
    isConductor: true,
    description: 'Conductive ocean salt water. Sinks below fresh water.',
  },
  {
    id: 28,
    name: 'Nitro Liquid',
    category: 'Liquids',
    state: 'liquid',
    color: '#84cc16',
    colorVariation: 15,
    density: 13,
    viscosity: 1,
    flammability: 100,
    description: 'Volatile explosive liquid. Detonates on impact or heat.',
  },
  {
    id: 29,
    name: 'Bedrock',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#09090b',
    colorVariation: 0,
    density: 9999,
    acidResistance: 100,
    description: 'Indestructible border material.',
  },
  {
    id: 30,
    name: 'Rubber',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#475569',
    colorVariation: 5,
    density: 20,
    acidResistance: 90,
    description: 'Non-conductive insulator block.',
  },
  {
    id: 31,
    name: 'Oxygen Gas',
    category: 'Gases',
    state: 'gas',
    color: '#a5f3fc',
    colorVariation: 10,
    density: -1,
    gravityFactor: -0.3,
    description: 'Concentrated oxygen gas. Supercharges fire combustion.',
  },
  {
    id: 32,
    name: 'Plasma',
    category: 'Energetic',
    state: 'plasma',
    color: '#a855f7',
    colorVariation: 25,
    density: -4,
    gravityFactor: -0.9,
    defaultTemp: 3000,
    decayTicks: 30,
    decayIntoId: 0,
    description: 'Superheated ionized gas channel (3000°C).',
  },
  {
    id: 33,
    name: 'Fuse Wire',
    category: 'Energetic',
    state: 'solid_fixed',
    color: '#ca8a04',
    colorVariation: 10,
    density: 15,
    flammability: 100,
    burnRate: 1,
    description: 'Slow-burning gunpowder fuse string.',
  },
  {
    id: 34,
    name: 'Honey',
    category: 'Liquids',
    state: 'liquid',
    color: '#f59e0b',
    colorVariation: 10,
    density: 14,
    viscosity: 9,
    description: 'Thick, viscous golden honey. Flows very slowly.',
  },
  {
    id: 35,
    name: 'Helium Gas',
    category: 'Gases',
    state: 'gas',
    color: '#f472b6',
    colorVariation: 15,
    density: -5,
    gravityFactor: -1.2,
    description: 'Ultra-light gas. Soars rapidly to the top of the grid.',
  },
  {
    id: 36,
    name: 'Laser Beam',
    category: 'Energetic',
    state: 'energy',
    color: '#ff0033',
    colorVariation: 20,
    density: 0,
    gravityFactor: 0,
    defaultTemp: 1500,
    decayTicks: 15,
    decayIntoId: 0,
    description: 'High-energy focused laser beam (1500°C). Vaporizes liquids, melts ice/stone, and ignites explosives instantly.',
  },
  {
    id: 37,
    name: 'Salt',
    category: 'Solids',
    state: 'solid_movable',
    color: '#e7e5e4',
    colorVariation: 8,
    density: 16,
    gravityFactor: 1,
    description: 'Halite grains. Dissolves in water into salt water.',
    interactions: [{ targetElementId: 2, chance: 0.45, resultSelfId: 0, resultTargetId: 27 }],
  },
  {
    id: 38,
    name: 'Snow',
    category: 'Solids',
    state: 'solid_movable',
    color: '#f8fafc',
    colorVariation: 10,
    density: 6,
    gravityFactor: 1,
    defaultTemp: -10,
    description: 'Light powder. Melts to water near heat.',
    interactions: [
      { targetElementId: 4, chance: 1, resultSelfId: 2 },
      { targetElementId: 6, chance: 1, resultSelfId: 2 },
    ],
  },
  {
    id: 39,
    name: 'Dirt',
    category: 'Solids',
    state: 'solid_movable',
    color: '#6b4f3a',
    colorVariation: 14,
    density: 17,
    gravityFactor: 1,
    description: 'Soil. Seeds take root here when watered.',
  },
  {
    id: 40,
    name: 'Seed',
    category: 'Biological',
    state: 'solid_movable',
    color: '#65a30d',
    colorVariation: 10,
    density: 13,
    gravityFactor: 1,
    flammability: 50,
    description: 'Germinates into plant on wet dirt.',
    interactions: [{ targetElementId: 39, chance: 0.25, resultSelfId: 11 }],
  },
  {
    id: 41,
    name: 'Coal',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#292524',
    colorVariation: 8,
    density: 45,
    flammability: 70,
    burnRate: 3,
    gravityFactor: 0,
    description: 'Carbon fuel. Burns slowly, hot.',
  },
  {
    id: 42,
    name: 'Concrete',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#a8a29e',
    colorVariation: 6,
    density: 70,
    acidResistance: 60,
    gravityFactor: 0,
    description: 'Poured barrier. Tougher than stone, weaker than bedrock.',
  },
  {
    id: 43,
    name: 'Hydrogen',
    category: 'Gases',
    state: 'gas',
    color: '#e0f2fe',
    colorVariation: 12,
    density: -6,
    gravityFactor: -1.1,
    flammability: 100,
    description: 'Lightest gas. Detonates violently with fire.',
  },
  {
    id: 44,
    name: 'Mercury',
    category: 'Liquids',
    state: 'liquid',
    color: '#94a3b8',
    colorVariation: 6,
    density: 40,
    viscosity: 1,
    isConductor: true,
    gravityFactor: 1,
    description: 'Dense conductive metal liquid. Sinks through water.',
  },
  {
    id: 45,
    name: 'Mud',
    category: 'Liquids',
    state: 'liquid',
    color: '#57534e',
    colorVariation: 10,
    density: 16,
    viscosity: 6,
    gravityFactor: 1,
    description: 'Wet soil. Forms when dirt meets water.',
  },
  {
    id: 46,
    name: 'Obsidian',
    category: 'Solids',
    state: 'solid_fixed',
    color: '#1c1917',
    colorVariation: 8,
    density: 70,
    acidResistance: 80,
    gravityFactor: 0,
    heatConductivity: 0.35,
    defaultTemp: 200,
    description: 'Volcanic glass. Lava quenched by water. Does not remelt easily.',
  },
  {
    id: 47,
    name: 'Copper',
    category: 'Energetic',
    state: 'solid_fixed',
    color: '#b87333',
    colorVariation: 8,
    density: 70,
    acidResistance: 55,
    gravityFactor: 0,
    heatConductivity: 1,
    isConductor: true,
    defaultTemp: 20,
    description: 'Heat pipe. Moves temperature without moving mass. Also carries spark.',
  },
  {
    id: 48,
    name: 'Fan',
    category: 'Special',
    state: 'solid_fixed',
    color: '#64748b',
    colorVariation: 4,
    density: 80,
    gravityFactor: 0,
    description: 'Blows gas and light powder. Paint over a fan again to rotate it (right, down, left, up).',
  },
  {
    id: 49,
    name: 'Wet mix',
    category: 'Solids',
    state: 'solid_movable',
    color: '#78716c',
    colorVariation: 8,
    density: 22,
    viscosity: 8,
    gravityFactor: 1,
    decayTicks: 280,
    decayIntoId: 42,
    description: 'Wet concrete. Pours, then cures into concrete.',
  },
];

export const CORE_ELEMENTS: ElementDefinition[] = DEFAULT_ELEMENTS;

const CUSTOM_ID_START = 50;
const CUSTOM_ID_END = 99;

export class ElementRegistry {
  private elements: Map<number, ElementDefinition> = new Map();

  constructor() {
    this.resetToDefaults();
    this.loadCustom();
  }

  public resetToDefaults() {
    this.elements.clear();
    CORE_ELEMENTS.forEach((el) => this.elements.set(el.id, el));
  }

  public getElement(id: number): ElementDefinition {
    return this.elements.get(id) || this.elements.get(0)!;
  }

  public registerElement(element: ElementDefinition): boolean {
    if (element.id < CUSTOM_ID_START || element.id > CUSTOM_ID_END) return false;
    this.elements.set(element.id, element);
    this.persistCustom();
    return true;
  }

  public getAllElements(): ElementDefinition[] {
    return Array.from(this.elements.values()).sort((a, b) => a.id - b.id);
  }

  public getPaletteElements(): ElementDefinition[] {
    return this.getAllElements().filter((e) => e.id !== 0);
  }

  public getElementsByCategory(category: string): ElementDefinition[] {
    return this.getAllElements().filter((e) => e.category === category && e.id !== 0);
  }

  public getNextAvailableId(): number {
    for (let id = CUSTOM_ID_START; id <= CUSTOM_ID_END; id++) {
      if (!this.elements.has(id)) return id;
    }
    return -1;
  }

  public isBuiltIn(id: number): boolean {
    return id < CUSTOM_ID_START;
  }

  public deleteCustomElement(id: number): boolean {
    if (id < CUSTOM_ID_START) return false;
    const ok = this.elements.delete(id);
    if (ok) this.persistCustom();
    return ok;
  }

  private persistCustom() {
    if (typeof window === 'undefined') return;
    const custom = this.getAllElements().filter((e) => e.id >= CUSTOM_ID_START);
    try {
      localStorage.setItem('crucible.custom-elements', JSON.stringify(custom));
    } catch {
      /* ignore */
    }
  }

  private loadCustom() {
    if (typeof window === 'undefined') return;
    try {
      const raw = localStorage.getItem('crucible.custom-elements');
      if (!raw) return;
      const arr = JSON.parse(raw) as ElementDefinition[];
      if (Array.isArray(arr)) {
        for (const el of arr) {
          if (el && typeof el.id === 'number' && el.id >= CUSTOM_ID_START) {
            this.elements.set(el.id, el);
          }
        }
      }
    } catch {
      /* ignore */
    }
  }
}

export const globalElementRegistry = new ElementRegistry();
