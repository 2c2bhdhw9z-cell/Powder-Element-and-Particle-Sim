export type ElementState = 'solid_fixed' | 'solid_movable' | 'liquid' | 'gas' | 'plasma' | 'energy' | 'special';

export interface InteractionRule {
  targetElementId: number; // Element ID to react with
  chance: number; // 0 to 1 probability per tick
  resultSelfId?: number; // What this cell turns into (undefined = no change)
  resultTargetId?: number; // What the neighbor cell turns into
  spawnElementId?: number; // Optional third element spawned in free space nearby
  tempChange?: number; // Heat added or absorbed
  explosionRadius?: number; // Triggers explosion if > 0
}

export interface ElementDefinition {
  id: number; // 0 to 499
  name: string;
  category: 'Solids' | 'Liquids' | 'Gases' | 'Energetic' | 'Biological' | 'Special' | 'Custom';
  state: ElementState;
  color: string; // Hex color e.g. "#E0C068"
  colorVariation?: number; // Random hue/brightness jitter for natural textures
  density: number; // For buoyancy (e.g. air=1, water=10, oil=8, sand=15, iron=50)
  viscosity?: number; // Flow speed for liquids (1 = instant, 10 = sluggish like honey)
  flammability?: number; // 0 to 100 chance to catch fire when exposed to heat/fire
  burnRate?: number; // How fast it turns to ash/smoke when burning
  acidResistance?: number; // 0 to 100 resistance to acid
  heatConductivity?: number; // Heat transfer rate (0 to 1)
  ignitionTemp?: number; // Temperature at which it spontaneously ignites
  defaultTemp?: number; // Realistic initial temperature when placed (e.g. Fire = 600°C, Ice = -15°C, Lava = 1200°C)
  decayTicks?: number; // Auto decay/lifetime (e.g. fire/smoke/sparks die over time)
  decayIntoId?: number; // What element it becomes after decay (default 0 = Empty/Air)
  gravityFactor?: number; // 1 = normal, -1 = anti-gravity, 0 = stationary
  isConductor?: boolean; // Conducts electricity/sparks
  interactions?: InteractionRule[];
  description?: string;
}

export interface PresetMap {
  id: string;
  title: string;
  author: string;
  description: string;
  thumbnail: string; // Base64 data URL
  likes: number;
  downloads: number;
  tags: string[];
  createdAt: string;
  width: number;
  height: number;
  gravityX: number;
  gravityY: number;
  gridDataBase64: string; // Compressed or encoded grid data
  customElements?: ElementDefinition[];
}

export interface ParticleObject {
  id: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  mass: number;
  charge: number; // -1, 0, 1 for electrostatic attraction/repulsion
  color: string;
  colorUint32?: number;
  lifespan?: number;
  maxLife?: number;
  fixed?: boolean;
  ignoreGravity?: boolean;
  originX?: number;
  originY?: number;
  type: 'standard' | 'emitter' | 'blackhole' | 'repulsor' | 'bouncy' | 'glow';
  trail: { x: number; y: number }[];
}

export interface UserSaveSlot {
  id: string;
  name: string;
  timestamp: string;
  mode: 'powder' | 'particle';
  data: string;
}

export interface MultiplayerRoomState {
  roomId: string;
  roomName: string;
  users: { id: string; name: string; color: string; x?: number; y?: number }[];
  hostId: string;
}

export interface MultiplayerEvent {
  type: 'join' | 'leave' | 'cursor' | 'draw' | 'clear' | 'speed' | 'particle_add' | 'chat';
  roomId: string;
  userId: string;
  userName?: string;
  userColor?: string;
  payload: any;
}
