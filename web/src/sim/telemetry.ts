export type SimMode = "powder" | "particle";

export type PerfSample = {
  t: number;
  mode: SimMode;
  fps: number;
  frameMs: number;
  stepMs: number;
  renderMs: number;
  bodies: number;
  canvasW: number;
  canvasH: number;
  speed: number;
  paused: boolean;
  heapMB: number;
  // powder
  fillPct: number;
  gridW: number;
  gridH: number;
  minTemp: number;
  maxTemp: number;
  avgTemp: number;
  wind: number;
  simMemKB: number;
  ticks: number;
  // particle
  maxBodies: number;
  avgSpeed: number;
  maxSpeed: number;
  nanCount: number;
  oobCount: number;
};

const EMPTY: PerfSample = {
  t: 0,
  mode: "powder",
  fps: 0,
  frameMs: 0,
  stepMs: 0,
  renderMs: 0,
  bodies: 0,
  canvasW: 0,
  canvasH: 0,
  speed: 1,
  paused: false,
  heapMB: 0,
  fillPct: 0,
  gridW: 0,
  gridH: 0,
  minTemp: 20,
  maxTemp: 20,
  avgTemp: 20,
  wind: 0,
  simMemKB: 0,
  ticks: 0,
  maxBodies: 0,
  avgSpeed: 0,
  maxSpeed: 0,
  nanCount: 0,
  oobCount: 0,
};

const HISTORY = 96;

function heapMB(): number {
  const mem = (performance as Performance & { memory?: { usedJSHeapSize: number } }).memory;
  return mem ? Math.round((mem.usedJSHeapSize / 1048576) * 10) / 10 : 0;
}

class Telemetry {
  current: PerfSample = { ...EMPTY };
  history: PerfSample[] = [];
  private listeners = new Set<() => void>();

  record(partial: Partial<PerfSample> & Pick<PerfSample, "mode" | "fps" | "bodies">) {
    const sample: PerfSample = {
      ...this.current,
      ...partial,
      t: performance.now(),
      heapMB: heapMB(),
    };
    this.current = sample;
    this.history.push(sample);
    if (this.history.length > HISTORY) this.history.shift();
    for (const fn of this.listeners) fn();
  }

  subscribe(fn: () => void) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }

  reset() {
    this.history = [];
    this.current = { ...EMPTY };
  }

  series(key: keyof PerfSample): number[] {
    return this.history.map((s) => Number(s[key]) || 0);
  }
}

export const telemetry = new Telemetry();

export function fpsTone(fps: number): "ok" | "warn" | "danger" {
  if (fps >= 50) return "ok";
  if (fps >= 30) return "warn";
  return "danger";
}
