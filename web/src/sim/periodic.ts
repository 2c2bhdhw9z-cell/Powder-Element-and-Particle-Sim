export type PeriodicItem = {
  z: number;
  symbol: string;
  name: string;
  mapsTo: number;
  why: string;
};

export const PERIODIC: PeriodicItem[] = [
  { z: 1, symbol: "H", name: "Hydrogen", mapsTo: 43, why: "Light fuel. Spark it." },
  { z: 2, symbol: "He", name: "Helium", mapsTo: 35, why: "Rises. Inert-ish boom." },
  { z: 6, symbol: "C", name: "Carbon", mapsTo: 41, why: "Coal. Slow burn." },
  { z: 8, symbol: "O", name: "Oxygen", mapsTo: 31, why: "Feeds fire." },
  { z: 11, symbol: "Na", name: "Sodium", mapsTo: 37, why: "Closest: salt." },
  { z: 13, symbol: "Al", name: "Aluminium", mapsTo: 17, why: "Metal / wire." },
  { z: 14, symbol: "Si", name: "Silicon", mapsTo: 1, why: "Sand, then glass." },
  { z: 16, symbol: "S", name: "Sulfur", mapsTo: 10, why: "Gunpowder stand-in." },
  { z: 20, symbol: "Ca", name: "Calcium", mapsTo: 7, why: "Stone." },
  { z: 26, symbol: "Fe", name: "Iron", mapsTo: 17, why: "Metal / wire." },
  { z: 29, symbol: "Cu", name: "Copper", mapsTo: 47, why: "Heat pipe." },
  { z: 47, symbol: "Ag", name: "Silver", mapsTo: 17, why: "Conductor." },
  { z: 50, symbol: "Sn", name: "Tin", mapsTo: 17, why: "Soft metal." },
  { z: 74, symbol: "W", name: "Tungsten", mapsTo: 17, why: "Hard metal." },
  { z: 78, symbol: "Pt", name: "Platinum", mapsTo: 17, why: "Inert metal." },
  { z: 79, symbol: "Au", name: "Gold", mapsTo: 17, why: "Dense metal." },
  { z: 80, symbol: "Hg", name: "Mercury", mapsTo: 44, why: "Liquid metal." },
  { z: 82, symbol: "Pb", name: "Lead", mapsTo: 44, why: "Heavy. Sinks." },
];

export const COMPOUNDS: PeriodicItem[] = [
  { z: 0, symbol: "H₂O", name: "Water", mapsTo: 2, why: "The liquid." },
  { z: 0, symbol: "NaCl", name: "Salt", mapsTo: 37, why: "Makes water conductive." },
  { z: 0, symbol: "SiO₂", name: "Silica", mapsTo: 12, why: "Glass." },
  { z: 0, symbol: "H₂", name: "H gas", mapsTo: 43, why: "Same as hydrogen." },
  { z: 0, symbol: "O₂", name: "O gas", mapsTo: 31, why: "Same as oxygen." },
  { z: 0, symbol: "C₄", name: "C4", mapsTo: 15, why: "Don’t." },
];
