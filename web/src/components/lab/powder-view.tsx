"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  Circle,
  Eraser,
  Minus,
  PaintBucket,
  Pipette,
  Replace,
  SprayCan,
  Square,
  Trash2,
  Volume2,
  VolumeX,
} from "lucide-react";
import { getPowderEngine, getRegistry } from "@/sim/engines";
import type { ElementDefinition } from "@/sim/types";
import { cn } from "@/lib/utils";
import { Slider } from "@/components/ui/slider";
import { Input } from "@/components/ui/input";
import { CanvasTools } from "./canvas-tools";
import { CanvasRecorder, captureCanvasScreenshot } from "@/sim/canvas-recorder";
import { soundEngine } from "@/sim/audio-engine";
import { telemetry } from "@/sim/telemetry";
import { POWDER_RECIPES } from "@/sim/powder-recipes";
import { gyro } from "@/sim/gyro";
import { GyroButton } from "./gyro-button";
import { DockGlass } from "./dock-glass";
import { PeriodicOverlay, LoreOverlay } from "./lab-modals";
import { applyDailyPowder, dailyPowderName } from "@/sim/daily-seed";
import { labHistory } from "@/sim/lab-history";

const CATS = ["All", "Solids", "Liquids", "Gases", "Energetic", "Biological", "Special", "Custom"] as const;

type Brush = "circle" | "square" | "spray" | "fill" | "line" | "replace" | "eraser" | "picker";
type Heat = "normal" | "temp_overlay" | "temp" | "density";

type DrawPayload = {
  x: number;
  y: number;
  size: number;
  elementId: number;
  shape: "circle" | "square" | "spray" | "fill" | "replace";
};

function seedBasin() {
  const engine = getPowderEngine();
  const w = engine.width;
  const h = engine.height;
  if (w < 40 || h < 40) return;
  if (engine.getActiveParticleCount() > 40) return;
  for (let x = 0; x < w; x++) {
    engine.setElementAt(x, h - 1, 29);
    engine.setElementAt(x, h - 2, 7);
    engine.setElementAt(x, h - 3, 7);
  }
  const wallL = 2;
  const wallR = w - 3;
  for (let y = Math.floor(h * 0.28); y < h - 3; y++) {
    engine.setElementAt(wallL, y, 7);
    engine.setElementAt(wallL + 1, y, 7);
    engine.setElementAt(wallR, y, 7);
    engine.setElementAt(wallR + 1, y, 7);
  }
  const sandTop = Math.floor(h * 0.32);
  const sandRight = Math.floor(w * 0.48);
  for (let y = sandTop; y < h - 4; y++) {
    const slope = Math.floor(((y - sandTop) / Math.max(1, h - 4 - sandTop)) * sandRight);
    for (let x = 4; x < 6 + slope; x++) {
      if (x < wallR - 2 && Math.random() > 0.08) engine.setElementAt(x, y, 1);
    }
  }
  const waterLeft = Math.floor(w * 0.42);
  const waterTop = Math.floor(h * 0.52);
  for (let y = waterTop; y < h - 4; y++) {
    for (let x = waterLeft; x < wallR - 2; x++) {
      engine.setElementAt(x, y, 2);
    }
  }
  for (let x = 6; x < 14 && x < w - 6; x++) {
    engine.setElementAt(x, sandTop - 1, 3);
    engine.setElementAt(x, sandTop - 2, 3);
  }
}

export function PowderView({
  paused,
  onFps,
  onDraw,
  remoteDraw,
  paletteTick,
  compact,
  follow,
}: {
  paused: boolean;
  onFps: (n: number, count: number) => void;
  onDraw?: (p: DrawPayload) => void;
  remoteDraw?: DrawPayload | null;
  paletteTick?: number;
  compact?: boolean;
  follow?: boolean;
}) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  const engine = getPowderEngine();
  const registry = getRegistry();
  const [elements, setElements] = useState<ElementDefinition[]>(() => registry.getPaletteElements());
  const [cat, setCat] = useState<string>("All");
  const [search, setSearch] = useState("");
  const [tool, setTool] = useState(1);
  const [brush, setBrush] = useState<Brush>("circle");
  const [brushSize, setBrushSize] = useState(5);
  const [envOpen, setEnvOpen] = useState(false);
  const [heatmap, setHeatmap] = useState<Heat>("normal");
  const [wind, setWind] = useState(0);
  const [amb, setAmb] = useState(20);
  const [tempUnit, setTempUnit] = useState<"C" | "F">("C");
  const [grav, setGrav] = useState<"down" | "up" | "left" | "right" | "zero">("down");
  const [texture, setTexture] = useState(engine.textureMode);
  const [speed, setSpeed] = useState(1);
  const [sound, setSound] = useState(true);
  const [recording, setRecording] = useState(false);
  const [history, setHistory] = useState(0);
  const [inspect, setInspect] = useState<{ name: string; temp: number; color: string; id: number } | null>(null);
  const [spawnN, setSpawnN] = useState(400);
  const [recipe, setRecipe] = useState<string | null>(null);
  const [pressureOn, setPressureOn] = useState(engine.pressureEnabled);
  const [tableOpen, setTableOpen] = useState(false);
  const [loreId, setLoreId] = useState<number | null>(null);
  const [downscale, setDownscale] = useState(1);
  const [dockOpen, setDockOpen] = useState(true);
  const followRef = useRef(!!follow);
  followRef.current = !!follow;
  const shakeRef = useRef(0);
  const drawing = useRef(false);
  const last = useRef<{ x: number; y: number } | null>(null);
  const replaceTarget = useRef<number>(0);
  const recorder = useRef<CanvasRecorder | null>(null);
  const toolRef = useRef(tool);
  const brushRef = useRef(brush);
  const sizeRef = useRef(brushSize);
  const speedRef = useRef(speed);
  const pausedRef = useRef(paused);
  const heatmapRef = useRef(heatmap);
  toolRef.current = tool;
  brushRef.current = brush;
  sizeRef.current = brushSize;
  speedRef.current = speed;
  pausedRef.current = paused;
  heatmapRef.current = heatmap;

  useEffect(() => {
    setElements(registry.getPaletteElements());
  }, [registry, paletteTick]);

  useEffect(() => {
    soundEngine.enabled = sound;
  }, [sound]);

  const filtered = elements.filter((e) => {
    if (cat === "Custom" && !(e.category === "Custom" || e.id >= 50)) return false;
    if (cat !== "All" && cat !== "Custom" && e.category !== cat) return false;
    if (search.trim()) {
      const q = search.toLowerCase();
      return e.name.toLowerCase().includes(q) || String(e.id) === q;
    }
    return true;
  });

  const seeded = useRef(false);
  const allowReseed = useRef(true);

  const resize = useCallback(() => {
    const wrap = wrapRef.current;
    if (!wrap) return;
    const rect = wrap.getBoundingClientRect();
    if (rect.width < 40 || rect.height < 40) return;
    const isMobile = window.innerWidth < 640;
    const scale = (isMobile ? 3 : 2.6) * downscale;
    const w = Math.max(80, Math.round(rect.width / scale));
    const h = Math.max(80, Math.round(rect.height / scale));
    const changed = w !== engine.width || h !== engine.height;
    if (changed) {
      engine.resize(w, h);
      const canvas = canvasRef.current;
      if (canvas) {
        canvas.width = w;
        canvas.height = h;
      }
    }
    if (engine.keepWorld) {
      seeded.current = true;
      allowReseed.current = false;
    }
    if (allowReseed.current && (changed || !seeded.current)) {
      engine.resetGrid();
      seedBasin();
      seeded.current = true;
    }
  }, [engine, downscale]);

  useEffect(() => {
    resize();
    const wrap = wrapRef.current;
    if (!wrap) return;
    const ro = new ResizeObserver(() => resize());
    ro.observe(wrap);
    return () => ro.disconnect();
  }, [resize]);

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
        engine.gravityX = gyro.gx;
        engine.gravityY = gyro.gy;
        if (gyro.shake > 0.45) engine.jostle(gyro.shake);
      }
      if (!pausedRef.current && !followRef.current) {
        stepAcc += Math.max(0.01, speedRef.current);
        let n = 0;
        while (stepAcc >= 1 && n < 8) {
          engine.step();
          stepAcc -= 1;
          n++;
        }
        if (stepAcc > 5) stepAcc = 0;
      }
      const tStep1 = performance.now();
      if (canvas.width !== engine.width || canvas.height !== engine.height) {
        canvas.width = engine.width;
        canvas.height = engine.height;
      }
      engine.renderToCanvas(ctx, heatmapRef.current);
      const tDraw = performance.now();
      stepMsSum += tStep1 - tStep0;
      renderMsSum += tDraw - tStep1;
      if (wrapRef.current) {
        if (shakeRef.current > 0) {
          wrapRef.current.style.transform = `translate(${(Math.random() - 0.5) * shakeRef.current}px, ${(Math.random() - 0.5) * shakeRef.current}px)`;
          shakeRef.current -= 1;
        } else {
          wrapRef.current.style.transform = "";
        }
      }
      frames++;
      acc += dt;
      if (acc >= 0.25) {
        const fps = Math.round(frames / acc);
        const bodies = engine.getActiveParticleCount();
        onFps(fps, bodies);
        const diag = engine.getDiagnostics();
        telemetry.record({
          mode: "powder",
          fps,
          frameMs: acc > 0 ? (acc * 1000) / frames : 0,
          stepMs: frames ? stepMsSum / frames : 0,
          renderMs: frames ? renderMsSum / frames : 0,
          bodies,
          canvasW: engine.width,
          canvasH: engine.height,
          speed: speedRef.current,
          paused: pausedRef.current,
          fillPct: diag.loadPercentage,
          gridW: diag.width,
          gridH: diag.height,
          minTemp: diag.minTemp,
          maxTemp: diag.maxTemp,
          avgTemp: diag.avgTemp,
          wind: engine.windX,
          simMemKB: Math.round(diag.memoryBytes / 1024),
          ticks: diag.frameCount,
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

  const toGrid = (clientX: number, clientY: number) => {
    const canvas = canvasRef.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    const x = Math.floor(((clientX - rect.left) / rect.width) * engine.width);
    const y = Math.floor(((clientY - rect.top) / rect.height) * engine.height);
    if (!engine.isValid(x, y)) return null;
    return { x, y };
  };

  const paintAt = (x: number, y: number) => {
    const b = brushRef.current;
    const id = b === "eraser" ? 0 : toolRef.current;
    if (b === "picker") {
      const el = engine.getElementAt(x, y);
      if (el.id !== 0) setTool(el.id);
      return;
    }
    if (b === "fill") {
      engine.drawBrush(x, y, 1, id, "fill");
      onDraw?.({ x, y, size: 1, elementId: id, shape: "fill" });
      return;
    }
    if (b === "replace") {
      engine.drawBrush(x, y, sizeRef.current, id, "replace", replaceTarget.current);
      onDraw?.({ x, y, size: sizeRef.current, elementId: id, shape: "replace" });
      return;
    }
    const shape = b === "eraser" || b === "line" ? "circle" : b;
    engine.drawBrush(x, y, sizeRef.current, id, shape);
    onDraw?.({ x, y, size: sizeRef.current, elementId: id, shape });
  };

  const paintLine = (a: { x: number; y: number }, b: { x: number; y: number }) => {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const steps = Math.max(1, Math.hypot(dx, dy));
    for (let i = 0; i <= steps; i++) {
      paintAt(Math.round(a.x + (dx * i) / steps), Math.round(a.y + (dy * i) / steps));
    }
  };

  const bumpHistory = () => setHistory((n) => n + 1);
  const record = () => {
    labHistory.record("powder");
    bumpHistory();
  };

  const onPointerDown = (e: React.PointerEvent) => {
    (e.target as HTMLElement).setPointerCapture(e.pointerId);
    drawing.current = true;
    allowReseed.current = false;
    engine.pushUndo();
    record();
    const p = toGrid(e.clientX, e.clientY);
    if (!p) return;
    last.current = p;
    replaceTarget.current = engine.gridType[engine.getIndex(p.x, p.y)];
    paintAt(p.x, p.y);
    const el = engine.getElementAt(p.x, p.y);
    const dir =
      el.id === 48
        ? ["→", "↓", "←", "↑"][(engine.gridLife[engine.getIndex(p.x, p.y)] || 0) % 4]
        : "";
    setInspect({
      id: el.id,
      name: dir ? `${el.name} ${dir}` : el.name,
      temp: engine.gridTemp[engine.getIndex(p.x, p.y)],
      color: el.color,
    });
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const p = toGrid(e.clientX, e.clientY);
    if (p) {
      const el = engine.getElementAt(p.x, p.y);
      const dir =
        el.id === 48
          ? ["→", "↓", "←", "↑"][(engine.gridLife[engine.getIndex(p.x, p.y)] || 0) % 4]
          : "";
      setInspect({
        id: el.id,
        name: dir ? `${el.name} ${dir}` : el.name,
        temp: engine.gridTemp[engine.getIndex(p.x, p.y)],
        color: el.color,
      });
    }
    if (!drawing.current || !p) return;
    if (brushRef.current === "fill") return;
    if (last.current) paintLine(last.current, p);
    last.current = p;
  };
  const onPointerUp = () => {
    drawing.current = false;
    last.current = null;
  };

  const fmtTemp = (c: number) =>
    tempUnit === "F" ? `${Math.round((c * 9) / 5 + 32)}°F` : `${Math.round(c)}°C`;

  const applyGrav = (d: typeof grav) => {
    setGrav(d);
    if (d === "down") {
      engine.gravityX = 0;
      engine.gravityY = 1;
    } else if (d === "up") {
      engine.gravityX = 0;
      engine.gravityY = -1;
    } else if (d === "left") {
      engine.gravityX = -1;
      engine.gravityY = 0;
    } else if (d === "right") {
      engine.gravityX = 1;
      engine.gravityY = 0;
    } else {
      engine.gravityX = 0;
      engine.gravityY = 0;
    }
  };

  const meteor = () => {
    soundEngine.playMeteor();
    shakeRef.current = 16;
    const cx = Math.floor(engine.width / 2);
    for (let dy = -10; dy <= 10; dy++) {
      for (let dx = -10; dx <= 10; dx++) {
        if (dx * dx + dy * dy > 100) continue;
        const x = cx + dx;
        const y = 14 + dy;
        if (!engine.isValid(x, y)) continue;
        engine.setElementAt(x, y, Math.random() < 0.8 ? 6 : 4, 2800);
        engine.gridVy[engine.getIndex(x, y)] = 18;
      }
    }
    window.setTimeout(() => {
      engine.triggerExplosion(cx, Math.floor(engine.height * 0.65), 28, 18, 3000);
      shakeRef.current = 22;
      soundEngine.playExplosion(2);
    }, 180);
  };

  const nuke = () => {
    soundEngine.playExplosion(3);
    shakeRef.current = 24;
    const cx = Math.floor(engine.width / 2);
    const cy = Math.floor(engine.height / 2);
    engine.triggerExplosion(cx, cy, 36, 22, 3500);
    window.setTimeout(() => {
      engine.triggerExplosion(cx - 22, cy - 14, 22, 16, 2800);
      engine.triggerExplosion(cx + 22, cy + 14, 22, 16, 2800);
      shakeRef.current = 16;
    }, 120);
  };

  const tsunami = () => {
    const startY = Math.floor(engine.height * 0.28);
    for (let y = startY; y < engine.height - 2; y++) {
      for (let x = 2; x < Math.min(28, engine.width - 4); x++) {
        engine.setElementAt(x, y, 2, 12);
        engine.gridVx[engine.getIndex(x, y)] = 14;
      }
    }
  };

  const freezeAll = () => {
    for (let i = 0; i < engine.gridType.length; i++) {
      const t = engine.gridType[i];
      if (t === 0 || t === 29) continue;
      engine.gridTemp[i] = -200;
      if (t === 2 || t === 8 || t === 9 || t === 27) engine.gridType[i] = 13;
      if (t === 6) engine.gridType[i] = 7;
    }
  };

  useEffect(() => {
    if (!remoteDraw) return;
    engine.drawBrush(remoteDraw.x, remoteDraw.y, remoteDraw.size, remoteDraw.elementId, remoteDraw.shape);
  }, [engine, remoteDraw]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) return;
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) labHistory.redo();
        else labHistory.undo();
        bumpHistory();
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "y") {
        e.preventDefault();
        labHistory.redo();
        bumpHistory();
      } else if (e.key === "[" || e.key === "{") setBrushSize((s) => Math.max(1, s - 1));
      else if (e.key === "]" || e.key === "}") setBrushSize((s) => Math.min(24, s + 1));
      else if (e.key.toLowerCase() === "e") setBrush("eraser");
      else if (e.key.toLowerCase() === "b") setBrush(e.shiftKey ? "fill" : "circle");
      else if (e.key.toLowerCase() === "c" && !e.ctrlKey) {
        engine.clear();
        bumpHistory();
      } else if (e.key.toLowerCase() === "s" && !e.ctrlKey) {
        const canvas = canvasRef.current;
        if (canvas) captureCanvasScreenshot(canvas, `crucible-${Date.now()}.png`);
      } else if (e.key.toLowerCase() === "r" && !e.ctrlKey) {
        const canvas = canvasRef.current;
        if (!canvas) return;
        if (!recorder.current) recorder.current = new CanvasRecorder(canvas, setRecording);
        recorder.current.toggle();
      } else if (e.key.toLowerCase() === "t") {
        setHeatmap((m) =>
          m === "normal" ? "temp_overlay" : m === "temp_overlay" ? "temp" : m === "temp" ? "density" : "normal",
        );
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [engine]);

  void history;

  return (
    <div className="flex min-h-0 w-full flex-1 flex-col">
      <div ref={wrapRef} className="relative min-h-0 w-full flex-1 bg-bg">
        <canvas
          ref={canvasRef}
          className="absolute inset-0 h-full w-full touch-none"
          style={{ imageRendering: "pixelated" }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        />
        <CanvasTools
          canUndo={labHistory.canUndo()}
          canRedo={labHistory.canRedo()}
          onUndo={() => {
            labHistory.undo();
            bumpHistory();
          }}
          onRedo={() => {
            labHistory.redo();
            bumpHistory();
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
        {inspect && (
          <button
            type="button"
            onClick={() => setLoreId(inspect.id || tool)}
            className="absolute right-2 top-2 rounded-md border border-border bg-elevated/90 px-2 py-1.5 text-left text-xs backdrop-blur-sm"
          >
            <span className="mr-1.5 inline-block size-2 rounded-[1px] align-middle" style={{ backgroundColor: inspect.color }} />
            {inspect.name} · {fmtTemp(inspect.temp)}
          </button>
        )}
      </div>

      {!compact && (
      <DockGlass
        title="Powder"
        subtitle={registry.getElement(tool)?.name ?? "Sand"}
        open={dockOpen}
        onOpenChange={setDockOpen}
      >
        <div className="flex gap-1 overflow-x-auto px-3">
          {POWDER_RECIPES.map((r) => (
            <button
              key={r.id}
              type="button"
              onClick={() => {
                allowReseed.current = false;
                r.run(engine);
                setRecipe(r.id);
                record();
              }}
              className={cn(
                "h-9 shrink-0 rounded-full px-3 text-xs",
                recipe === r.id ? "bg-primary text-primary-fg" : "text-muted hover:bg-subtle hover:text-fg",
              )}
            >
              {r.name}
            </button>
          ))}
          <button
            type="button"
            onClick={() => {
              allowReseed.current = false;
              const d = applyDailyPowder(engine);
              setRecipe(`today-${d.name}`);
              record();
            }}
            className={cn(
              "h-9 shrink-0 rounded-full px-3 text-xs",
              recipe?.startsWith("today") ? "bg-primary text-primary-fg" : "text-muted hover:bg-subtle hover:text-fg",
            )}
          >
            Today · {dailyPowderName()}
          </button>
          <button
            type="button"
            onClick={() => setTableOpen(true)}
            className="h-9 shrink-0 rounded-full px-3 text-xs text-muted hover:bg-subtle hover:text-fg"
          >
            Table
          </button>
        </div>
        <div className="flex items-center gap-2 px-2 pt-2">
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search elements"
            className="h-9 text-xs"
          />
        </div>
        <div className="flex gap-1 overflow-x-auto px-2 pt-2">
          {CATS.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => setCat(c)}
              className={cn(
                "h-8 shrink-0 rounded-full px-3 text-xs font-medium",
                cat === c ? "bg-primary text-primary-fg" : "text-muted hover:bg-subtle hover:text-fg",
              )}
            >
              {c}
            </button>
          ))}
        </div>
        <div className="flex gap-1 overflow-x-auto px-2 pt-2">
          {filtered.map((el) => (
            <button
              key={el.id}
              type="button"
              title={el.description}
              onClick={() => setTool(el.id)}
              onContextMenu={(ev) => {
                ev.preventDefault();
                setLoreId(el.id);
              }}
              onDoubleClick={() => setLoreId(el.id)}
              className={cn(
                "flex h-11 shrink-0 items-center gap-2 rounded-md border px-2.5 text-xs",
                tool === el.id ? "border-primary bg-subtle text-fg" : "border-border text-muted hover:border-border-strong hover:text-fg",
              )}
            >
              <span className="size-2.5 rounded-[2px]" style={{ backgroundColor: el.color }} />
              {el.name}
            </button>
          ))}
        </div>
        <div className="flex gap-1 overflow-x-auto px-3 pb-2 pt-1">
          {(
            [
              ["circle", Circle],
              ["square", Square],
              ["spray", SprayCan],
              ["line", Minus],
              ["fill", PaintBucket],
              ["replace", Replace],
              ["eraser", Eraser],
              ["picker", Pipette],
            ] as const
          ).map(([id, Icon]) => (
            <button
              key={id}
              type="button"
              onClick={() => setBrush(id)}
              className={cn("grid size-10 shrink-0 place-items-center rounded-md", brush === id ? "text-fg" : "text-muted hover:text-fg")}
              aria-label={id}
            >
              <Icon className="size-4" />
            </button>
          ))}
          <button
            type="button"
            onClick={() => setSound((v) => !v)}
            className="grid size-10 shrink-0 place-items-center rounded-md text-muted hover:text-fg"
            aria-label="Sound"
          >
            {sound ? <Volume2 className="size-4" /> : <VolumeX className="size-4" />}
          </button>
          <button
            type="button"
            onClick={() => {
              engine.clear();
              record();
            }}
            className="grid size-10 shrink-0 place-items-center rounded-md text-muted hover:text-fg"
            aria-label="Clear"
          >
            <Trash2 className="size-4" />
          </button>
          <button
            type="button"
            onClick={() => setEnvOpen((v) => !v)}
            className="h-10 shrink-0 whitespace-nowrap rounded-md px-3 text-xs font-medium text-muted hover:bg-subtle hover:text-fg"
          >
            Env
          </button>
          <GyroButton />
        </div>
        {envOpen && (
          <div className="grid grid-cols-2 gap-3 border-t border-border px-3 py-3 text-xs">
            <label className="space-y-1">
              <span className="text-muted">Wind {wind}</span>
              <Slider
                min={-5}
                max={5}
                step={1}
                value={[wind]}
                onValueChange={(v) => {
                  const n = v[0] ?? 0;
                  setWind(n);
                  engine.setWind(n);
                }}
              />
            </label>
            <label className="space-y-1">
              <span className="text-muted">Ambient {tempUnit === "F" ? fmtTemp(amb) : `${amb}°C`}</span>
              <Slider
                min={-40}
                max={400}
                step={5}
                value={[amb]}
                onValueChange={(v) => {
                  const n = v[0] ?? 20;
                  setAmb(n);
                  engine.ambientTemp = n;
                }}
              />
            </label>
            <div className="col-span-2 flex gap-1">
              {(["down", "up", "left", "right", "zero"] as const).map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => applyGrav(d)}
                  className={cn(
                    "h-9 flex-1 rounded-sm capitalize",
                    grav === d ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                  )}
                >
                  {d}
                </button>
              ))}
            </div>
            <div className="col-span-2 flex gap-1">
              {(["normal", "temp_overlay", "temp", "density"] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => setHeatmap(m)}
                  className={cn(
                    "h-9 flex-1 rounded-sm",
                    heatmap === m ? "bg-primary text-primary-fg" : "bg-subtle text-muted",
                  )}
                >
                  {m === "normal" ? "Matter" : m === "temp" ? "Heat" : m === "density" ? "Mass" : "Glow"}
                </button>
              ))}
            </div>
            <div className="col-span-2 flex gap-1">
              {(["natural_grain", "organic_flow", "diagonal_matrix", "flat"] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => {
                    setTexture(m);
                    engine.textureMode = m;
                  }}
                  className={cn(
                    "h-9 flex-1 rounded-sm capitalize",
                    texture === m ? "bg-subtle text-fg" : "text-muted hover:text-fg",
                  )}
                >
                  {m === "natural_grain" ? "Grain" : m === "organic_flow" ? "Flow" : m === "diagonal_matrix" ? "Matrix" : "Flat"}
                </button>
              ))}
            </div>
            <div className="col-span-2 flex gap-1">
              {([1, 1.5, 2] as const).map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => setDownscale(f)}
                  className={cn(
                    "h-9 flex-1 rounded-sm",
                    downscale === f ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                  )}
                >
                  {f === 1 ? "Native" : f === 1.5 ? "Fast" : "Ultra"}
                </button>
              ))}
            </div>
            <div className="col-span-2 flex gap-1">
              <button
                type="button"
                onClick={() => {
                  const next = !pressureOn;
                  setPressureOn(next);
                  engine.pressureEnabled = next;
                }}
                className={cn(
                  "h-9 flex-1 rounded-sm",
                  pressureOn ? "bg-primary text-primary-fg" : "bg-subtle text-muted hover:text-fg",
                )}
              >
                Pressure {pressureOn ? "on" : "off"}
              </button>
              <button type="button" onClick={() => setTempUnit((u) => (u === "C" ? "F" : "C"))} className="h-9 rounded-sm bg-subtle px-3 text-muted">
                °{tempUnit}
              </button>
            </div>
            <div className="col-span-2 flex gap-1">
              <button type="button" onClick={meteor} className="h-9 flex-1 rounded-sm bg-subtle text-muted hover:text-fg">
                Meteor
              </button>
              <button type="button" onClick={nuke} className="h-9 flex-1 rounded-sm bg-subtle text-muted hover:text-fg">
                Blast
              </button>
              <button type="button" onClick={tsunami} className="h-9 flex-1 rounded-sm bg-subtle text-muted hover:text-fg">
                Wave
              </button>
              <button type="button" onClick={freezeAll} className="h-9 flex-1 rounded-sm bg-subtle text-muted hover:text-fg">
                Freeze
              </button>
            </div>
            <label className="col-span-2 space-y-1">
              <span className="text-muted">Brush {brushSize}</span>
              <Slider min={1} max={24} step={1} value={[brushSize]} onValueChange={(v) => setBrushSize(v[0] ?? 5)} />
            </label>
            <label className="col-span-2 space-y-1">
              <span className="text-muted">Spawn {spawnN}</span>
              <Slider min={20} max={2000} step={20} value={[spawnN]} onValueChange={(v) => setSpawnN(v[0] ?? 400)} />
            </label>
          </div>
        )}
      </DockGlass>
      )}
      <PeriodicOverlay open={tableOpen} onClose={() => setTableOpen(false)} onPick={(id) => setTool(id)} />
      <LoreOverlay open={loreId !== null} onClose={() => setLoreId(null)} elementId={loreId} />
    </div>
  );
}
