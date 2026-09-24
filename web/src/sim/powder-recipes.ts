import type { PowderEngine } from "./powder-engine";

type Cell = { x: number; y: number; id: number; temp?: number };

function put(e: PowderEngine, x: number, y: number, id: number, temp?: number) {
  if (!e.isValid(x, y)) return;
  e.setElementAt(x, y, id, temp);
}

function fillRect(e: PowderEngine, x0: number, y0: number, x1: number, y1: number, id: number, temp?: number) {
  const xa = Math.min(x0, x1);
  const xb = Math.max(x0, x1);
  const ya = Math.min(y0, y1);
  const yb = Math.max(y0, y1);
  for (let y = ya; y <= yb; y++) {
    for (let x = xa; x <= xb; x++) put(e, x, y, id, temp);
  }
}

function fillCircle(e: PowderEngine, cx: number, cy: number, r: number, id: number, temp?: number) {
  const r2 = r * r;
  for (let y = -r; y <= r; y++) {
    for (let x = -r; x <= r; x++) {
      if (x * x + y * y <= r2) put(e, cx + x, cy + y, id, temp);
    }
  }
}

function basin(e: PowderEngine) {
  const w = e.width;
  const h = e.height;
  fillRect(e, 0, h - 2, w - 1, h - 1, 29);
  fillRect(e, 0, Math.floor(h * 0.22), 1, h - 1, 29);
  fillRect(e, w - 2, Math.floor(h * 0.22), w - 1, h - 1, 29);
}

export function seedVolcano(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  const cx = Math.floor(w * 0.5);
  const base = h - 3;
  const peak = Math.floor(h * 0.28);
  const half = Math.floor(w * 0.38);
  for (let y = peak; y < base; y++) {
    const t = (y - peak) / Math.max(1, base - peak);
    const span = Math.max(3, Math.floor(half * t));
    for (let x = cx - span; x <= cx + span; x++) {
      const edge = Math.abs(x - cx) > span - 2;
      put(e, x, y, edge ? 7 : 39);
    }
  }
  const vent = Math.max(2, Math.floor(w * 0.04));
  for (let y = peak; y < Math.floor(h * 0.72); y++) {
    fillRect(e, cx - vent, y, cx + vent, y, 6, 1400);
  }
  fillCircle(e, cx, peak + 2, vent + 1, 6, 1600);
  fillCircle(e, cx, peak - 1, vent, 4, 900);
  for (let i = 0; i < 18; i++) {
    put(e, cx + ((i % 5) - 2), peak - 2 - Math.floor(i / 5), 5);
  }
}

export function seedAntFarm(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.35), w - 3, h - 3, 39);
  fillRect(e, 2, Math.floor(h * 0.72), w - 3, h - 3, 1);
  const tunnels: Cell[] = [];
  const path = [
    [0.18, 0.42, 0.55, 0.42],
    [0.55, 0.42, 0.55, 0.62],
    [0.55, 0.62, 0.82, 0.62],
    [0.3, 0.42, 0.3, 0.7],
    [0.3, 0.7, 0.48, 0.7],
  ];
  for (const [x0, y0, x1, y1] of path) {
    const ax = Math.floor(w * x0);
    const ay = Math.floor(h * y0);
    const bx = Math.floor(w * x1);
    const by = Math.floor(h * y1);
    const steps = Math.max(Math.abs(bx - ax), Math.abs(by - ay), 1);
    for (let i = 0; i <= steps; i++) {
      const x = Math.round(ax + ((bx - ax) * i) / steps);
      const y = Math.round(ay + ((by - ay) * i) / steps);
      fillCircle(e, x, y, 2, 0);
      tunnels.push({ x, y, id: 19 });
    }
  }
  for (let i = 0; i < tunnels.length; i += 6) put(e, tunnels[i].x, tunnels[i].y, 19);
  fillRect(e, Math.floor(w * 0.12), Math.floor(h * 0.28), Math.floor(w * 0.22), Math.floor(h * 0.34), 11);
  fillRect(e, Math.floor(w * 0.7), Math.floor(h * 0.3), Math.floor(w * 0.78), Math.floor(h * 0.34), 3);
  fillRect(e, Math.floor(w * 0.08), Math.floor(h * 0.78), Math.floor(w * 0.2), h - 4, 2);
}

export function seedOilFire(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.62), w - 3, h - 3, 1);
  fillRect(e, Math.floor(w * 0.18), Math.floor(h * 0.48), Math.floor(w * 0.82), Math.floor(h * 0.62), 9);
  for (let x = Math.floor(w * 0.22); x < w * 0.78; x += 3) {
    put(e, x, Math.floor(h * 0.46), 3);
    put(e, x, Math.floor(h * 0.45), 3);
  }
  fillCircle(e, Math.floor(w * 0.5), Math.floor(h * 0.44), 4, 4, 800);
  fillRect(e, Math.floor(w * 0.08), Math.floor(h * 0.7), Math.floor(w * 0.16), h - 4, 2);
}

export function seedIceDam(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.7), Math.floor(w * 0.52), h - 3, 39);
  const damX = Math.floor(w * 0.52);
  fillRect(e, damX, Math.floor(h * 0.32), damX + 4, h - 3, 13, -20);
  fillRect(e, damX + 1, Math.floor(h * 0.32), damX + 3, h - 3, 13, -30);
  fillRect(e, 2, Math.floor(h * 0.38), damX - 1, Math.floor(h * 0.7), 2);
  fillRect(e, damX + 5, Math.floor(h * 0.78), w - 3, h - 3, 1);
  for (let x = 4; x < damX - 2; x += 4) put(e, x, Math.floor(h * 0.36), 38, -10);
  fillRect(e, Math.floor(w * 0.7), Math.floor(h * 0.68), Math.floor(w * 0.86), Math.floor(h * 0.78), 11);
}

export function seedReactor(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  const x0 = Math.floor(w * 0.28);
  const x1 = Math.floor(w * 0.72);
  const y0 = Math.floor(h * 0.28);
  const y1 = Math.floor(h * 0.78);
  fillRect(e, x0, y0, x1, y1, 17);
  fillRect(e, x0 + 2, y0 + 2, x1 - 2, y1 - 2, 0);
  fillRect(e, x0 + 3, Math.floor(h * 0.52), x1 - 3, y1 - 3, 2);
  fillRect(e, x0 + 6, y0 + 4, x1 - 6, Math.floor(h * 0.48), 43);
  fillRect(e, Math.floor(w * 0.48), y0 + 3, Math.floor(w * 0.52), y0 + 6, 16);
  fillRect(e, x0 - 4, y1 - 8, x0 + 1, y1 - 2, 26);
  fillRect(e, x1 - 1, y1 - 8, x1 + 4, y1 - 2, 42);
  fillRect(e, 3, h - 8, Math.floor(w * 0.22), h - 3, 2);
}

export function seedStorm(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.62), w - 3, h - 3, 2);
  const rod = Math.floor(w * 0.5);
  fillRect(e, rod - 1, Math.floor(h * 0.22), rod + 1, Math.floor(h * 0.62), 47);
  fillRect(e, rod - 4, Math.floor(h * 0.2), rod + 4, Math.floor(h * 0.22), 17);
  fillCircle(e, rod, Math.floor(h * 0.16), 2, 16, 1200);
  fillRect(e, Math.floor(w * 0.12), Math.floor(h * 0.5), Math.floor(w * 0.28), Math.floor(h * 0.62), 9);
  fillRect(e, Math.floor(w * 0.7), Math.floor(h * 0.48), Math.floor(w * 0.84), Math.floor(h * 0.58), 3);
}

export function seedCircuit(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  const y = Math.floor(h * 0.55);
  fillRect(e, 8, y, w - 9, y + 1, 47);
  fillRect(e, 6, y - 1, 8, y + 2, 17);
  fillCircle(e, 6, y, 2, 16, 1400);
  fillRect(e, w - 14, y - 3, w - 8, y + 4, 15);
}

export function seedVacuum(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  const x0 = Math.floor(w * 0.22);
  const x1 = Math.floor(w * 0.78);
  const y0 = Math.floor(h * 0.28);
  const y1 = Math.floor(h * 0.78);
  fillRect(e, x0, y0, x1, y0 + 1, 7);
  fillRect(e, x0, y1 - 1, x1, y1, 7);
  fillRect(e, x0, y0, x0 + 1, y1, 7);
  fillRect(e, x1 - 1, y0, x1, y1, 7);
  fillCircle(e, Math.floor(w * 0.5), Math.floor(h * 0.52), 3, 20);
  fillRect(e, x0 + 3, y1 - 8, x1 - 3, y1 - 3, 5);
  fillRect(e, x0 + 4, y0 + 4, x0 + 18, y0 + 10, 14, 140);
}

export function seedSnow(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.72), w - 3, h - 3, 13);
  for (let i = 0; i < Math.floor(w * 0.8); i++) {
    put(e, 3 + (i % (w - 6)), 4 + Math.floor(i / (w - 6)), 38);
  }
  fillRect(e, Math.floor(w * 0.4), Math.floor(h * 0.45), Math.floor(w * 0.6), Math.floor(h * 0.72), 7);
  fillRect(e, Math.floor(w * 0.18), Math.floor(h * 0.58), Math.floor(w * 0.32), Math.floor(h * 0.72), 2);
}

export function seedBeach(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.62), w - 3, h - 3, 1);
  fillRect(e, 2, Math.floor(h * 0.48), Math.floor(w * 0.62), Math.floor(h * 0.62), 2);
  fillRect(e, Math.floor(w * 0.55), Math.floor(h * 0.58), w - 3, Math.floor(h * 0.72), 9);
  fillRect(e, Math.floor(w * 0.08), Math.floor(h * 0.42), Math.floor(w * 0.16), Math.floor(h * 0.62), 19);
}

export function seedForest(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  fillRect(e, 2, Math.floor(h * 0.72), w - 3, h - 3, 11);
  for (let i = 0; i < 7; i++) {
    const x = 8 + Math.floor((i / 6) * (w - 20));
    fillRect(e, x, Math.floor(h * 0.5), x + 1, Math.floor(h * 0.72), 3);
    fillCircle(e, x, Math.floor(h * 0.48), 4, 19);
  }
  fillRect(e, Math.floor(w * 0.7), Math.floor(h * 0.58), w - 4, Math.floor(h * 0.72), 2);
}

export function seedKiln(e: PowderEngine) {
  e.resetGrid();
  const w = e.width;
  const h = e.height;
  basin(e);
  const x0 = Math.floor(w * 0.28);
  const x1 = Math.floor(w * 0.72);
  const y0 = Math.floor(h * 0.38);
  const y1 = Math.floor(h * 0.78);
  fillRect(e, x0, y0, x1, y0 + 1, 7);
  fillRect(e, x0, y1 - 1, x1, y1, 7);
  fillRect(e, x0, y0, x0 + 1, y1, 7);
  fillRect(e, x1 - 1, y0, x1, y1, 7);
  fillRect(e, x0 + 3, y1 - 8, x1 - 3, y1 - 3, 6, 1100);
  fillRect(e, x0 + 4, y0 + 6, x1 - 4, y0 + 10, 1);
  fillRect(e, x0 + 2, y0 + 2, x0 + 4, y0 + 5, 4, 700);
}

export function seedRemix(e: PowderEngine) {
  const pack = [
    seedVolcano,
    seedAntFarm,
    seedOilFire,
    seedIceDam,
    seedReactor,
    seedStorm,
    seedCircuit,
    seedVacuum,
    seedSnow,
    seedBeach,
    seedForest,
    seedKiln,
  ];
  pack[Math.floor(Math.random() * pack.length)](e);
  const w = e.width;
  const h = e.height;
  for (let i = 0; i < 40; i++) {
    const x = 4 + Math.floor(Math.random() * (w - 8));
    const y = Math.floor(h * 0.3) + Math.floor(Math.random() * (h * 0.5));
    const ids = [1, 2, 6, 9, 11, 13, 47, 49];
    put(e, x, y, ids[Math.floor(Math.random() * ids.length)]);
  }
}

export const POWDER_RECIPES: { id: string; name: string; run: (e: PowderEngine) => void }[] = [
  { id: "volcano", name: "Volcano", run: seedVolcano },
  { id: "ants", name: "Ant farm", run: seedAntFarm },
  { id: "oil", name: "Oil fire", run: seedOilFire },
  { id: "dam", name: "Ice dam", run: seedIceDam },
  { id: "reactor", name: "Reactor", run: seedReactor },
  { id: "storm", name: "Storm", run: seedStorm },
  { id: "circuit", name: "Circuit", run: seedCircuit },
  { id: "vacuum", name: "Vacuum", run: seedVacuum },
  { id: "snow", name: "Snow", run: seedSnow },
  { id: "beach", name: "Beach", run: seedBeach },
  { id: "forest", name: "Forest", run: seedForest },
  { id: "kiln", name: "Kiln", run: seedKiln },
  { id: "remix", name: "Remix", run: seedRemix },
];
