import { ElementDefinition } from '../types/physics';

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
    color: '#38bdf8',
    colorVariation: 10,
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
    colorVariation: 20,
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
    color: '#e2e8f0',
    colorVariation: 10,
    density: -3,
    gravityFactor: -0.6,
    defaultTemp: 120,
    decayTicks: 150,
    decayIntoId: 2, // Condenses back to Water!
    description: 'Hot water vapor (120°C). Rises and condenses into water drops.',
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
    decayTicks: 6,
    decayIntoId: 0,
    isConductor: true,
    description: 'Electrical arc (1000°C). Travels along metals and wire.',
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
    color: '#0284c7',
    colorVariation: 10,
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
  }
];

function hslToHex(h: number, s: number, l: number): string {
  l /= 100;
  const a = (s * Math.min(l, 1 - l)) / 100;
  const f = (n: number) => {
    const k = (n + h / 30) % 12;
    const color = l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1);
    return Math.round(255 * color).toString(16).padStart(2, '0');
  };
  return `#${f(0)}${f(8)}${f(4)}`;
}

// Helper to generate additional unique element definitions to populate all 500 slots
function generateExtended500Elements(): ElementDefinition[] {
  const categories: ElementDefinition['category'][] = [
    'Solids', 'Liquids', 'Gases', 'Energetic', 'Biological', 'Special'
  ];

  const states: ElementDefinition['state'][] = [
    'solid_movable', 'solid_fixed', 'liquid', 'gas', 'plasma', 'energy'
  ];

  const baseSubstances = [
    // Periodic & Transition Metals
    'Titanium', 'Platinum', 'Aluminum', 'Lead', 'Zinc', 'Nickel', 'Lithium', 'Sodium', 'Potassium', 'Calcium',
    'Magnesium', 'Barium', 'Uranium', 'Plutonium', 'Thorium', 'Radium', 'Beryllium', 'Cobalt', 'Scandium', 'Gallium',
    'Germanium', 'Arsenic', 'Selenium', 'Bromine', 'Krypton', 'Rubidium', 'Strontium', 'Yttrium', 'Zirconium', 'Niobium',
    'Molybdenum', 'Technetium', 'Ruthenium', 'Rhodium', 'Palladium', 'Cadmium', 'Indium', 'Tellurium', 'Iodine', 'Cesium',
    'Lutetium', 'Hafnium', 'Tantalum', 'Tungsten', 'Rhenium', 'Osmium', 'Iridium', 'Thallium', 'Bismuth', 'Polonium',
    'Astatine', 'Francium', 'Actinium', 'Protactinium', 'Neptunium', 'Americium', 'Curium', 'Berkelium', 'Californium', 'Einsteinium',
    'Fermium', 'Mendelevium', 'Nobelium', 'Lawrencium', 'Rutherfordium', 'Dubnium', 'Seaborgium', 'Bohrium', 'Hassium', 'Meitnerium',

    // Minerals, Gems & Crystals
    'Obsidian', 'Granite', 'Basalt', 'Marble', 'Quartz', 'Emerald', 'Ruby', 'Sapphire', 'Diamond', 'Topaz',
    'Amethyst', 'Jade', 'Opal', 'Amber', 'Garnet', 'Turquoise', 'Malachite', 'Lapis Lazuli', 'Pyrite', 'Bauxite',
    'Silica', 'Feldspar', 'Mica', 'Calcite', 'Gypsum', 'Talc', 'Halite', 'Fluorite', 'Corundum', 'Apatite',
    'Olivine', 'Pyroxene', 'Amphibole', 'Serpentine', 'Zeolite', 'Hematite', 'Magnetite', 'Limonite', 'Siderite', 'Chalcopyrite',

    // Organic & Chemical Compounds
    'Ethanol', 'Methanol', 'Acetone', 'Benzene', 'Ether', 'Mercury', 'Kerosene', 'Diesel', 'Gasoline', 'Glycerin',
    'Sulfuric Acid', 'Nitric Acid', 'Hydrofluoric Acid', 'Hydrochloric Acid', 'Ammonia', 'Brine', 'Molten Glass', 'Liquid Helium', 'Liquid Oxygen', 'Liquid Nitrogen',
    'Slime', 'Glue', 'Latex', 'Resin', 'Tar', 'Pitch', 'Asphalt', 'Magma', 'Molten Copper', 'Molten Iron',
    'Methane', 'Ethane', 'Propane', 'Butane', 'Pentane', 'Hexane', 'Octane', 'Toluene', 'Xylene', 'Phenol',

    // Gases & Vapors
    'Hydrogen Gas', 'Carbon Dioxide', 'Carbon Monoxide', 'Nitrous Oxide', 'Ozone', 'Chlorine Gas',
    'Fluorine Gas', 'Radon Gas', 'Xenon Gas', 'Argon Gas', 'Neon Gas', 'Phosphine Gas', 'Silane Gas', 'Sulfur Dioxide', 'Ammonia Gas',
    'Ethylene', 'Acetylene', 'Formaldehyde', 'Phosgene', 'Cyanogen', 'Hydrazine', 'Sulfur Hexafluoride', 'Nitrogen Dioxide', 'Steam Vapor', 'Volcanic Gas',

    // Energetic, Pyrotechnic & Explosive
    'TNT', 'Dynamite', 'RDX', 'PETN', 'Nitroglycerin', 'Anfo', 'Plasma Bolt', 'Fusion Plasma', 'Solar Flare', 'Coronal Mass',
    'Laser Beam', 'Gamma Arc', 'EMP Blast', 'Stun Charge', 'Thermal Shock', 'Spark Dust', 'Fire Crystal', 'Volt Powder', 'Blaze Gel', 'Arc Flame',
    'Gunpowder', 'Cordite', 'Thermite Mix', 'Magnesium Ribbon', 'White Phosphorus', 'Red Phosphorus', 'Fulminate', 'Picric Acid', 'Tetrazene', 'Nitrostarch',

    // Biological & Organic
    'Spore', 'Bacteria', 'Fungi', 'Mold', 'Moss', 'Algae', 'Ivy', 'Kelp', 'Coral', 'Pollen',
    'Blood', 'Venom', 'Toxin', 'Pheromone', 'DNA Strand', 'Stem Cell', 'Bacterial Colony', 'Fungal Mycelium', 'Zombie Fungus', 'Bioluminescent Slime',
    'Chlorophyll', 'Keratin', 'Chitin', 'Collagen', 'Cellulose', 'Lignin', 'Enzyme Catalyst', 'Yeast Culture', 'Plankton', 'Sponge Specimen',

    // Advanced Synthesis & Physics
    'Graphene', 'Aerogel', 'Carbon Nanotube', 'Fullerene', 'Buckyball', 'Metamaterial', 'Ferrofluid', 'Non-Newtonian Fluid', 'Superfluid', 'Superconductor',
    'Antimatter', 'Dark Matter', 'Tachyon Dust', 'Quantum Foam', 'Chroniton', 'Graviton', 'Neutronium', 'Unobtainium', 'Vibranium', 'Adamantium',
    'Aether', 'Mana Powder', 'Astral Dust', 'Stardust', 'Cosmic Ash', 'Void Powder', 'Singularity Core', 'Wormhole Gel', 'Time Dilator', 'Forcefield'
  ];

  const descriptors = [
    '', 'Ore', 'Dust', 'Vapor', 'Sludge', 'Crystal', 'Isotope', 'Ion', 'Alloy', 'Extract',
    'Compound', 'Matrix', 'Filament', 'Residue', 'Solution', 'Aerosol', 'Grit', 'Gel', 'Plasma', 'Ash'
  ];

  const extended: ElementDefinition[] = [];

  for (let id = 37; id < 500; id++) {
    const baseIdx = (id - 37) % baseSubstances.length;
    const descIdx = Math.floor((id - 37) / baseSubstances.length);
    const baseName = baseSubstances[baseIdx];
    const desc = descIdx > 0 ? ` ${descriptors[descIdx % descriptors.length]}` : '';
    const name = `${baseName}${desc}`;

    let cat = categories[(id * 7) % categories.length];
    let state: ElementDefinition['state'] = states[(id * 3) % states.length];

    const isLiquid = cat === 'Liquids' || name.includes('Magma') || name.includes('Lava') || name.includes('Molten') || name.includes('Liquid') || name.includes('Acid') || name.includes('Fluid') || name.includes('Blood') || name.includes('Sludge') || name.includes('Gel') || name.includes('Solution') || name.includes('Honey') || name.includes('Tar') || name.includes('Oil') || name.includes('Slime') || name.includes('Mercury') || name.includes('Water') || name.includes('Brine') || name.includes('Kerosene') || name.includes('Diesel') || name.includes('Gasoline') || name.includes('Glycerin') || name.includes('Ethanol') || name.includes('Methanol') || name.includes('Acetone') || name.includes('Benzene') || name.includes('Ether') || name.includes('Pitch') || name.includes('Asphalt') || name.includes('Resin') || name.includes('Glue') || name.includes('Latex');

    // Infer state & category from name
    if (name.includes('Laser')) {
      cat = 'Energetic';
      state = 'energy';
    } else if (isLiquid) {
      cat = 'Liquids';
      state = 'liquid';
    } else if (cat === 'Gases' || name.includes('Gas') || name.includes('Dioxide') || name.includes('Vapor') || name.includes('Aerosol')) {
      cat = 'Gases';
      state = 'gas';
    } else if (cat === 'Energetic' && id % 2 === 0) {
      state = 'plasma';
    }

    // Realistic Color Override by Keyword
    let color: string;
    if (name.includes('Laser')) {
      color = '#ff0033'; // Neon crimson red laser
    } else if (name.includes('Lava') || name.includes('Magma') || name.includes('Molten')) {
      color = '#ff3d00'; // Incandescent orange-red
    } else if (name.includes('Ice') || name.includes('Frost') || name.includes('Glacier')) {
      color = '#7dd3fc'; // Translucent frost blue
    } else if (name.includes('Water') || name.includes('Ocean')) {
      color = '#38bdf8'; // Blue
    } else if (name.includes('Fire') || name.includes('Flame') || name.includes('Blaze') || name.includes('Solar')) {
      color = '#ff5500'; // Flame
    } else if (name.includes('Acid') || name.includes('Toxic') || name.includes('Poison') || name.includes('Venom')) {
      color = '#84cc16'; // Acidic lime green
    } else if (name.includes('Gold')) {
      color = '#ffd700';
    } else if (name.includes('Emerald') || name.includes('Jade') || name.includes('Chlorophyll')) {
      color = '#10b981';
    } else if (name.includes('Ruby') || name.includes('Blood')) {
      color = '#e11d48';
    } else if (name.includes('Sapphire') || name.includes('Lapis')) {
      color = '#2563eb';
    } else if (name.includes('Amethyst')) {
      color = '#a855f7';
    } else if (name.includes('Obsidian') || name.includes('Tar') || name.includes('Asphalt') || name.includes('Coal')) {
      color = '#1e293b';
    } else if (name.includes('Spark') || name.includes('Volt') || name.includes('Electric')) {
      color = '#facc15';
    } else if (name.includes('Plasma')) {
      color = '#d946ef';
    } else {
      // Procedural fallback
      const hue = Math.round((id * 137.5) % 360);
      const sat = 70 + (id % 25);
      const light = 50 + (id % 25);
      color = hslToHex(hue, sat, light);
    }

    let density = 10 + (id % 80);
    let gravityFactor = 1;

    if (state === 'gas') {
      density = -1 - (id % 5);
      gravityFactor = -0.5;
    } else if (state === 'plasma' || state === 'energy') {
      density = -2;
      gravityFactor = 0;
    } else if (state === 'solid_fixed') {
      gravityFactor = 0;
    } else if (name.includes('Anti-Gravity') || name.includes('Tachyon') || name.includes('Quantum')) {
      gravityFactor = -1;
    }

    let defaultTemp: number | undefined = undefined;
    if (name.includes('Fire') || name.includes('Flame') || name.includes('Blaze') || name.includes('Solar') || name.includes('Arc')) {
      defaultTemp = 600;
    } else if (name.includes('Lava') || name.includes('Magma') || name.includes('Molten')) {
      defaultTemp = 1200;
    } else if (name.includes('Plasma') || name.includes('Fusion') || name.includes('Coronal')) {
      defaultTemp = 3000;
    } else if (name.includes('Thermite') || name.includes('Incendiary')) {
      defaultTemp = 2200;
    } else if (name.includes('Ice') || name.includes('Frost') || name.includes('Glacier') || name.includes('Frozen')) {
      defaultTemp = -15;
    } else if (name.includes('Liquid Nitrogen') || name.includes('Liquid Helium') || name.includes('Superfluid')) {
      defaultTemp = -196;
    } else if (name.includes('Steam') || name.includes('Vapor')) {
      defaultTemp = 120;
    } else if (name.includes('Spark') || name.includes('Volt') || name.includes('Laser')) {
      defaultTemp = 1000;
    }

    extended.push({
      id,
      name,
      category: cat,
      state,
      color,
      colorVariation: 15,
      density,
      defaultTemp,
      viscosity: state === 'liquid' ? (
        (name.includes('Magma') || name.includes('Lava') || name.includes('Honey') || name.includes('Tar') || name.includes('Pitch') || name.includes('Resin') || name.includes('Sludge') || name.includes('Glue')) ? 6 :
        (name.includes('Oil') || name.includes('Slime') || name.includes('Glycerin') || name.includes('Gel') || name.includes('Mud')) ? 3 : 1
      ) : undefined,
      flammability: (cat === 'Energetic' || name.includes('Gas') || name.includes('Oil')) ? 80 : undefined,
      decayTicks: (state === 'plasma' || state === 'energy' || cat === 'Energetic') ? 20 + (id % 60) : undefined,
      decayIntoId: state === 'plasma' ? 5 : 0,
      gravityFactor,
      description: `Element #${id}: ${name} (${cat} - ${state.replace('_', ' ')}). Realistic simulation particle.`
    });
  }

  return extended;
}

export const ALL_500_ELEMENTS: ElementDefinition[] = [
  ...DEFAULT_ELEMENTS,
  ...generateExtended500Elements()
];

// Master 500-slot Element Registry Manager
export class ElementRegistry {
  private elements: Map<number, ElementDefinition> = new Map();

  constructor() {
    this.resetToDefaults();
  }

  public resetToDefaults() {
    this.elements.clear();
    ALL_500_ELEMENTS.forEach(el => this.elements.set(el.id, el));
  }

  public getElement(id: number): ElementDefinition {
    return this.elements.get(id) || this.elements.get(0)!; // fallback to Air
  }

  public registerElement(element: ElementDefinition): boolean {
    if (element.id < 1 || element.id >= 500) return false;
    this.elements.set(element.id, element);
    return true;
  }

  public getAllElements(): ElementDefinition[] {
    return Array.from(this.elements.values()).sort((a, b) => a.id - b.id);
  }

  public getElementsByCategory(category: string): ElementDefinition[] {
    return this.getAllElements().filter(e => e.category === category && e.id !== 0);
  }

  public getNextAvailableId(): number {
    for (let id = 1; id < 500; id++) {
      if (!this.elements.has(id)) return id;
    }
    return -1;
  }

  public deleteCustomElement(id: number): boolean {
    if (id < 36) return false; // Cannot delete built-in elements
    return this.elements.delete(id);
  }
}

export const globalElementRegistry = new ElementRegistry();
