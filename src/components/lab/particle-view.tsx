"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getParticleEngine } from "@/sim/engines";
import { cn } from "@/lib/utils";
import { Slider } from "@/components/ui/slider";
import { Trash2 } from "lucide-react";
import type { ParticleEngine } from "@/sim/particle-engine";
import { CanvasTools } from "./canvas-tools";
import { CanvasRecorder, captureCanvasScreenshot } from "@/sim/canvas-recorder";
import { telemetry } from "@/sim/telemetry";
import { gyro } from "@/sim/gyro";
import { GyroButton } from "./gyro-button";
import { DockGlass } from "./dock-glass";
import { applyDailyParticle, dailyParticleName } from "@/sim/daily-seed";
import { ParticleGL } from "@/sim/particle-gl";
import { labHistory } from "@/sim/lab-history";
import { settleToPowder } from "@/sim/hybrid";

const PRESETS: { id: string; name: string; run: (e: ParticleEngine) => void }[] = [
  { id: "galaxy", name: "Galaxy", run: (e) => e.spawnGalaxy(window.innerWidth < 640 ? 180 : 320) },
  { id: "burst", name: "Burst", run: (e) => e.spawnBurst(window.innerWidth < 640 ? 80 : 160) },
  { id: "fall", name: "Fall", run: (e) => e.spawnWaterfall(window.innerWidth < 640 ? 140 : 250) },
  { id: "pour", name: "Pour", run: (e) => e.spawnPour(window.innerWidth < 640 ? 280 : 520) },
  { id: "flock", name: "Flock", run: (e) => e.spawnFlock(window.innerWidth < 640 ? 160 : 280) },
  { id: "cloth", name: "Cloth", run: (e) => e.spawnCloth(window.innerWidth < 640 ? 12 : 18, window.innerWidth < 640 ? 9 : 12) },
  { id: "nbody", name: "N-body", run: (e) => e.spawnNbody(window.innerWidth < 640 ? 180 : 320) },
  { id: "blob", name: "Blob", run: (e) => e.spawnBlob(window.innerWidth < 640 ? 20 : 28) },
  { id: "rope", name: "Rope", run: (e) => e.spawnRope(window.innerWidth < 640 ? 24 : 40) },
  { id: "shock", name: "Shock", run: (e) => e.spawnShockwave(window.innerWidth < 640 ? 160 : 280) },
  { id: "well", name: "Well", run: (e) => e.spawnBlackHole(window.innerWidth < 640 ? 160 : 250) },
  { id: "vortex", name: "Vortex", run: (e) => e.spawnDoubleVortex(window.innerWidth < 640 ? 180 : 300) },
  { id: "flare", name: "Flare", run: (e) => e.spawnSolarFlare(window.innerWidth < 640 ? 180 : 320) },
  { id: "lattice", name: "Lattice", run: (e) => e.spawnQuantumLattice(12, 16) },
  { id: "helix", name: "Helix", run: (e) => e.spawnDnaHelix(window.innerWidth < 640 ? 160 : 260) },
  { id: "fountain", name: "Fountain", run: (e) => e.spawnCosmicFountain(window.innerWidth < 640 ? 140 : 240) },
  { id: "sync", name: "Ring", run: (e) => e.spawnSynchrotron(window.innerWidth < 640 ? 180 : 280) },
  { id: "repel", name: "Repulsor", run: (e) => e.spawnRepulsor() },
];

const MOUSE: { id: ParticleEngine["mouseMode"]; name: string }[] = [
  { id: "attract", name: "Attract" },
  { id: "repel", name: "Repel" },
  { id: "vortex", name: "Vortex" },
  { id: "emitter", name: "Emit" },
  { id: "painter", name: "Paint" },
  { id: "gravity_well", name: "Well" },
  { id: "freeze", name: "Freeze" },
  { id: "hawk", name: "Hawk" },
  { id: "hyper_drive", name: "Drive" },
];

const COLORS: ParticleEngine["colorMode"][] = [
  "element",
  "velocity",
  "charge",
  "rainbow",
  "density",
  "lifespan",
];

const BATCH_PRESETS = [1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000];
const CAP_PRESETS = [50_000, 100_000, 250_000, 500_000, 1_000_000];
const HARD_CAP = 1_000_000;

function fmtCount(n: number) {
  if (n >= 1_000_000) return `${n / 1_000_000}M`;
  if (n >= 1000) return `${Math.round(n / 1000)}k`;
  return String(n);
}

export function ParticleView({
  paused,
  onFps,
  compact,
  follow,
}: {
  paused: boolean;
  onFps: (n: number, count: number) => void;
  compact?: boolean;
  follow?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const glRef = useRef<HTMLCanvasElement>(null);
  const gpuRef = useRef<HTMLCanvasElement>(null);
  const glEngine = useRef<ParticleGL | null>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const engine = getParticleEngine();
  if (engine.maxParticles < HARD_CAP) engine.maxParticles = HARD_CAP;
  const mouse = useRef({ x: 0, y: 0, active: false });
  const recorder = useRef<CanvasRecorder | null>(null);
  const [preset, setPreset] = useState("galaxy");
  const [mouseMode, setMouseMode] = useState<ParticleEngine["mouseMode"]>("attract");
  const [panel, setPanel] = useState<"off" | "physics" | "visuals">("off");
  const [gravityX, setGravityX] = useState(0);
  const [gravityY, setGravityY] = useState(0);
  const [damp, setDamp] = useState(0.99);
  const [elasticity, setElasticity] = useState(0.8);
  const [charge, setCharge] = useState(100);
  const [vortex, setVortex] = useState(0);
  const [maxSpeed, setMaxSpeed] = useState(30);
  const [force, setForce] = useState(1);
  const [radius, setRadius] = useState(120);
  const [trails, setTrails] = useState(true);
  const [size, setSize] = useState(2);
  const [decay, setDecay] = useState(0);
  const [colorMode, setColorMode] = useState<ParticleEngine["colorMode"]>("element");
  const [boundary, setBoundary] = useState<ParticleEngine["boundaryMode"]>("bounce");
  const [batch, setBatch] = useState(10_000);
  const [cap, setCap] = useState(engine.maxParticles);
  const [collide, setCollide] = useState(engine.collisionsEnabled);
  const [fluid, setFluid] = useState(engine.fluidEnabled);
  const [speed, setSpeed] = useState(1);
  const [recording, setRecording] = useState(false);
  const [history, setHistory] = useState(0);
  const [dockOpen, setDockOpen] = useState(true);
  const followRef = useRef(!!follow);
  followRef.current = !!follow;
  const seeded = useRef(false);
  const speedRef = useRef(speed);
  const pausedRef = useRef(paused);
  speedRef.current = speed;
  pausedRef.current = paused;

  const bump = () => setHistory((n) => n + 1);
  const record = () => {
    labHistory.record("particle");
    bump();
  };

  const applyCap = (n: number) => {
    const next = engine.setMaxParticles(n);
    setCap(next);
    if (batch > next) setBatch(next);
    bump();
  };

  const resize = useCallback(() => {
    const wrap = wrapRef.current;
    const canvas = canvasRef.current;
    if (!wrap || !canvas) return;
    const rect = wrap.getBoundingClientRect();
    const w = Math.max(1, Math.round(rect.width));
    const h = Math.max(1, Math.round(rect.height));
    canvas.width = w;
    canvas.height = h;
    const glc = glRef.current;
    if (glc) {
      glc.width = w;
      glc.height = h;
    }
    const gpuc = gpuRef.current;
    if (gpuc) {
      gpuc.width = w;
      gpuc.height = h;
    }
    engine.resize(w, h);
  }, [engine]);

  useEffect(() => {
    resize();
    if (!seeded.current) {
      seeded.current = true;
      if (!engine.keepWorld) {
        engine.spawnGalaxy(window.innerWidth < 640 ? 200 : 360);
        setGravityY(0);
      }
    }
    const wrap = wrapRef.current;
    if (!wrap) return;
    const ro = new ResizeObserver(() => resize());
    ro.observe(wrap);
    return () => ro.disconnect();
  }, [engine, resize]);

  useEffect(() => {
    engine.mouseMode = mouseMode;
    engine.mouseForceMultiplier = force;
    engine.mouseRadius = radius;
    engine.gravityX = gravityX;
    engine.gravityY = gravityY;
    engine.damping = damp;
    engine.elasticity = elasticity;
    engine.electrostaticFactor = charge;
    engine.vortexForce = vortex;
    engine.maxSpeed = maxSpeed;
    engine.showTrails = trails;
    engine.particleSize = size;
    engine.decaySpeed = decay;
    engine.colorMode = colorMode;
    engine.boundaryMode = boundary;
    engine.collisionsEnabled = collide;
    engine.fluidEnabled = fluid;
  }, [
    engine,
    mouseMode,
    force,
    radius,
    gravityX,
    gravityY,
    damp,
    elasticity,
    charge,
    vortex,
    maxSpeed,
    trails,
    size,
    decay,
    colorMode,
    boundary,
    collide,
    fluid,
  ]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    let raf = 0;
    let lastT = performance.now();
    let frames = 0;
    let acc = 0;
    let stepAcc = 0;
    let stepMsSum = 0;
    let renderMsSum = 0;
    const loop = (now: number) => {
      const dt = Math.min(0.1, (now - lastT) / 1000);
      lastT = now;
      const tStep0 = performance.now();
      if (gyro.enabled) {
        engine.gravityX = gyro.pgx;
        engine.gravityY = gyro.pgy;
      }
      if (!pausedRef.current && !followRef.current) {
        stepAcc += Math.max(0.01, speedRef.current);
        let n = 0;
        while (stepAcc >= 1 && n < 4) {
          engine.step(mouse.current.x, mouse.current.y, mouse.current.active);
          stepAcc -= 1;
          n++;
        }
        if (stepAcc > 4) stepAcc = 0;
      }
      const tStep1 = performance.now();
      const n = engine.bodyCount();
      const glc = glRef.current;
      const gpuc = gpuRef.current;
      if (gpuc) gpuc.style.opacity = "0";
      const useGL = n > 2200 && glc !== null;
      if (useGL && glc) {
        if (glc.width !== engine.width || glc.height !== engine.height) {
          glc.width = engine.width;
          glc.height = engine.height;
        }
        if (!glEngine.current) {
          glEngine.current = new ParticleGL();
          glEngine.current.attach(glc);
        }
        if (engine.swarm.n > 0) {
          glEngine.current.drawXY(
            engine.swarm.xy,
            engine.swarm.color,
            engine.swarm.n,
            engine.width,
            engine.height,
            engine.particleSize,
            engine.swarm.colorTick,
          );
        } else {
          glEngine.current.draw(engine.particles, engine.width, engine.height, engine.particleSize);
        }
        glc.style.opacity = "1";
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (engine.particles.length && engine.swarm.n > 0) engine.render(ctx);
      } else {
        if (glc) glc.style.opacity = "0";
        engine.render(ctx);
      }
      const tDraw = performance.now();
      stepMsSum += tStep1 - tStep0;
      renderMsSum += tDraw - tStep1;
      frames++;
      acc += dt;
      if (acc >= 0.25) {
        const fps = Math.round(frames / acc);
        const bodies = engine.bodyCount();
        onFps(fps, bodies);
        const diag = engine.getDiagnostics();
        telemetry.record({
          mode: "particle",
          fps,
          frameMs: acc > 0 ? (acc * 1000) / frames : 0,
          stepMs: frames ? stepMsSum / frames : 0,
          renderMs: frames ? renderMsSum / frames : 0,
          bodies,
          canvasW: engine.width,
          canvasH: engine.height,
          speed: speedRef.current,
          paused: pausedRef.current,
          maxBodies: engine.maxParticles,
          avgSpeed: diag.maxSpeedFound * 0.4,
          maxSpeed: diag.maxSpeedFound,
          nanCount: diag.nanCount,
          oobCount: diag.outOfBoundsCount,
          simMemKB: Math.round(diag.memoryBytes / 1024),
        });
        frames = 0;
        acc = 0;
        stepMsSum = 0;
        renderMsSum = 0;
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [engine, onFps]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) labHistory.redo();
        else labHistory.undo();
        bump();
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "y") {
        e.preventDefault();
        labHistory.redo();
        bump();
      } else if (e.key.toLowerCase() === "c" && !e.ctrlKey) {
        engine.clear();
        bump();
      } else if (e.key.toLowerCase() === "s" && !e.ctrlKey) {
        const canvas = canvasRef.current;
        if (canvas) captureCanvasScreenshot(canvas, `crucible-${Date.now()}.png`);
      } else if (e.key.toLowerCase() === "r" && !e.ctrlKey) {
        const canvas = canvasRef.current;
        if (!canvas) return;
        if (!recorder.current) recorder.current = new CanvasRecorder(canvas, setRecording);
        recorder.current.toggle();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [engine]);

  const setPointer = (e: React.PointerEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const scaleX = engine.width / rect.width;
    const scaleY = engine.height / rect.height;
    mouse.current.x = (e.clientX - rect.left) * scaleX;
    mouse.current.y = (e.clientY - rect.top) * scaleY;
  };

  void history;

  return (
    <div className="flex min-h-0 w-full flex-1 flex-col">
      <div ref={wrapRef} className="relative min-h-0 w-full flex-1 bg-bg">
        <canvas ref={gpuRef} className="pointer-events-none absolute inset-0 h-full w-full" style={{ opacity: 0 }} />
        <canvas ref={glRef} className="pointer-events-none absolute inset-0 h-full w-full" style={{ opacity: 0 }} />
        <canvas
          ref={canvasRef}
          className="absolute inset-0 z-[1] h-full w-full touch-none"
          onPointerDown={(e) => {
            (e.target as HTMLElement).setPointerCapture(e.pointerId);
            mouse.current.active = true;
            setPointer(e);
          }}
          onPointerMove={(e) => setPointer(e)}
          onPointerUp={() => {
            mouse.current.active = false;
          }}
          onPointerCancel={() => {
            mouse.current.active = false;
          }}
        />
        <CanvasTools
          canUndo={labHistory.canUndo()}
          canRedo={labHistory.canRedo()}
          onUndo={() => {
            labHistory.undo();
            bump();
          }}
          onRedo={() => {
            labHistory.redo();
            bump();
          }}
          onShot={() => {
            const canvas = canvasRef.current;
            if (canvas) captureCanvasScreenshot(canvas, `crucible-${Date.now()}.png`);
          }}
          recording={recording}
          onRecord={() => {
            const canvas = canvasRef.current;
            if (!canvas) return;
            if (!recorder.current) recorder.current = new CanvasRecorder(canvas, setRecording);
            recorder.current.toggle();
          }}
          speed={speed}
          onSpeed={setSpeed}
        />
      </div>

      {!compact && (
      <DockGlass
        title="Particles"
        subtitle={`${PRESETS.find((p) => p.id === preset)?.name ?? preset} · ${MOUSE.find((m) => m.id === mouseMode)?.name ?? mouseMode}`}
        open={dockOpen}
        onOpenChange={setDockOpen}
        trailing={
          <button
            type="button"
            className="h-11 shrink-0 rounded-full bg-white/12 px-3 text-xs font-medium"
            onClick={() => {
              engine.pushUndo();
              engine.spawnBatch(Math.min(batch, engine.maxParticles - engine.bodyCount()));
              record();
            }}
          >
            +{fmtCount(batch)}
            <span className="ml-1 text-[10px] text-muted">{fmtCount(engine.bodyCount())}</span>
          </button>
        }
      >
        <div className="flex gap-1 overflow-x-auto px-3">
          {PRESETS.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => {
                setPreset(p.id);
                p.run(engine);
                if (p.id === "fall") setGravityY(0.45);
                if (p.id === "pour") {
                  setGravityY(0.38);
                  setFluid(true);
                  setCollide(true);
                } else {
                  setFluid(false);
                  engine.fluidEnabled = false;
                }
                record();
              }}
              className={cn(
                "h-9 shrink-0 rounded-full px-3 text-xs",
                preset === p.id ? "bg-primary text-primary-fg" : "text-muted hover:bg-subtle hover:text-fg",
              )}
            >
              {p.name}
            </button>
          ))}
          <button
            type="button"
            onClick={() => {
              const d = applyDailyParticle(engine);
              setPreset(d.name);
              record();
            }}
            className="h-9 shrink-0 rounded-full px-3 text-xs text-muted hover:bg-subtle hover:text-fg"
          >
            Today · {dailyParticleName()}
          </button>
        </div>
        <div className="flex gap-1 overflow-x-auto px-2 pt-1">
          {MOUSE.map((m) => (
            <button
              key={m.id}
              type="button"
              onClick={() => setMouseMode(m.id)}
              className={cn(
                "h-9 shrink-0 rounded-full px-3 text-xs",
                mouseMode === m.id ? "bg-primary text-primary-fg" : "text-muted hover:bg-subtle hover:text-fg",
              )}
            >
              {m.name}
            </button>
          ))}
        </div>
        <div className="flex gap-1 overflow-x-auto px-3 pb-2 pt-1">
          <button
            type="button"
            onClick={() => {
              engine.clear();
              bump();
            }}
            className="grid size-11 shrink-0 place-items-center rounded-md text-muted hover:text-fg"
            aria-label="Clear"
          >
            <Trash2 className="size-4" />
          </button>
          <button
            type="button"
            onClick={() => setPanel((v) => (v === "physics" ? "off" : "physics"))}
            className={cn("h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium", panel === "physics" ? "text-fg" : "text-muted")}
          >
            Physics
          </button>
          <button
            type="button"
            onClick={() => setPanel((v) => (v === "visuals" ? "off" : "visuals"))}
            className={cn("h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium", panel === "visuals" ? "text-fg" : "text-muted")}
          >
            Visuals
          </button>
          <button
            type="button"
            onClick={() => setTrails((v) => !v)}
            className={cn("h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium", trails ? "text-fg" : "text-muted")}
          >
            Trails
          </button>
          <button
            type="button"
            onClick={() => setCollide((v) => !v)}
            className={cn("h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium", collide ? "text-fg" : "text-muted")}
          >
            Collide
          </button>
          <GyroButton />
          <button
            type="button"
            onClick={() => {
              setFluid((v) => !v);
            }}
            className={cn("h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium", fluid ? "text-fg" : "text-muted")}
          >
            Fluid
          </button>
          <button
            type="button"
            className="h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium text-muted hover:text-fg"
            onClick={() => {
              settleToPowder();
              record();
            }}
          >
            Settle
          </button>
          <button
            type="button"
            className="h-11 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium text-muted hover:text-fg"
            onClick={() => {
              engine.placeWell(mouse.current.x || engine.width / 2, mouse.current.y || engine.height / 2);
              record();
            }}
          >
            Drop well
          </button>
        </div>
        <div className="max-h-[42dvh] overflow-y-auto">
        {panel === "physics" && (
          <div className="grid grid-cols-2 gap-3 border-t border-border px-3 py-3 text-xs">
            <label className="space-y-1">
              <span className="text-muted">Gravity X {gravityX.toFixed(2)}</span>
              <Slider min={-1.2} max={1.2} step={0.05} value={[gravityX]} onValueChange={(v) => setGravityX(v[0] ?? 0)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Gravity Y {gravityY.toFixed(2)}</span>
              <Slider min={-1.2} max={1.2} step={0.05} value={[gravityY]} onValueChange={(v) => setGravityY(v[0] ?? 0)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Drag {damp.toFixed(3)}</span>
              <Slider min={0.9} max={1} step={0.005} value={[damp]} onValueChange={(v) => setDamp(v[0] ?? 0.99)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Bounce {elasticity.toFixed(2)}</span>
              <Slider min={0} max={1} step={0.05} value={[elasticity]} onValueChange={(v) => setElasticity(v[0] ?? 0.8)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Charge {charge}</span>
              <Slider min={0} max={400} step={10} value={[charge]} onValueChange={(v) => setCharge(v[0] ?? 100)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Vortex {vortex.toFixed(1)}</span>
              <Slider min={-8} max={8} step={0.1} value={[vortex]} onValueChange={(v) => setVortex(v[0] ?? 0)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Max speed {maxSpeed}</span>
              <Slider min={4} max={80} step={1} value={[maxSpeed]} onValueChange={(v) => setMaxSpeed(v[0] ?? 30)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Mouse force {force.toFixed(1)}</span>
              <Slider min={0.2} max={4} step={0.1} value={[force]} onValueChange={(v) => setForce(v[0] ?? 1)} />
            </label>
            <label className="col-span-2 space-y-1">
              <span className="text-muted">Mouse radius {radius}</span>
              <Slider min={20} max={280} step={4} value={[radius]} onValueChange={(v) => setRadius(v[0] ?? 120)} />
            </label>
            <div className="col-span-2 flex gap-1">
              {(["bounce", "wrap", "void"] as const).map((b) => (
                <button
                  key={b}
                  type="button"
                  onClick={() => setBoundary(b)}
                  className={cn(
                    "h-9 flex-1 rounded-sm capitalize",
                    boundary === b ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                  )}
                >
                  {b}
                </button>
              ))}
            </div>
            <label className="col-span-2 space-y-1">
              <span className="flex items-center justify-between text-muted">
                <span>Max particles</span>
                <span className="font-mono tabular-nums text-fg">{cap.toLocaleString()}</span>
              </span>
              <Slider min={5000} max={HARD_CAP} step={5000} value={[cap]} onValueChange={(v) => applyCap(v[0] ?? HARD_CAP)} />
              <div className="flex flex-wrap gap-1 pt-1">
                {CAP_PRESETS.map((n) => (
                  <button
                    key={n}
                    type="button"
                    onClick={() => applyCap(n)}
                    className={cn(
                      "h-8 rounded-sm px-2 font-mono text-xs tabular-nums",
                      cap === n ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                    )}
                  >
                    {fmtCount(n)}
                  </button>
                ))}
              </div>
            </label>
            <label className="col-span-2 space-y-1">
              <span className="flex items-center justify-between text-muted">
                <span>Batch spawn</span>
                <span className="font-mono tabular-nums text-fg">{batch.toLocaleString()}</span>
              </span>
              <Slider
                min={1000}
                max={cap}
                step={1000}
                value={[Math.min(batch, cap)]}
                onValueChange={(v) => setBatch(v[0] ?? 10_000)}
              />
              <div className="flex flex-wrap gap-1 pt-1">
                {BATCH_PRESETS.filter((n) => n <= cap).map((n) => (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setBatch(n)}
                    className={cn(
                      "h-8 rounded-sm px-2 font-mono text-xs tabular-nums",
                      batch === n ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                    )}
                  >
                    {fmtCount(n)}
                  </button>
                ))}
              </div>
            </label>
          </div>
        )}
        {panel === "visuals" && (
          <div className="grid grid-cols-2 gap-3 border-t border-border px-3 py-3 text-xs">
            <label className="space-y-1">
              <span className="text-muted">Size {size.toFixed(1)}</span>
              <Slider min={1} max={8} step={0.5} value={[size]} onValueChange={(v) => setSize(v[0] ?? 2)} />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Decay {decay === 0 ? "off" : `${decay}×`}</span>
              <Slider min={0} max={10} step={1} value={[decay]} onValueChange={(v) => setDecay(v[0] ?? 0)} />
            </label>
            <div className="col-span-2 flex flex-wrap gap-1">
              {COLORS.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setColorMode(c)}
                  className={cn(
                    "h-8 rounded-sm px-2 capitalize",
                    colorMode === c ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                  )}
                >
                  {c}
                </button>
              ))}
            </div>
          </div>
        )}
        </div>
      </DockGlass>
      )}
    </div>
  );
}
