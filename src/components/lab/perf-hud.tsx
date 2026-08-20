"use client";

import { useEffect, useRef, useState } from "react";
import { Activity } from "lucide-react";
import { telemetry, fpsTone, type PerfSample, type SimMode } from "@/sim/telemetry";
import { cn } from "@/lib/utils";
import { GlassSheet } from "./glass-sheet";

function readCss(name: string, fallback: string) {
  if (typeof window === "undefined") return fallback;
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

function Spark({
  values,
  accent,
  budget,
}: {
  values: number[];
  accent: string;
  budget?: number;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = canvas.clientWidth || 140;
    const h = canvas.clientHeight || 36;
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    if (values.length < 2) return;
    const max = Math.max(budget ?? 0, ...values, 0.001);
    const min = Math.min(0, ...values);
    const span = max - min || 1;
    if (budget && budget > 0) {
      const y = h - 4 - ((budget - min) / span) * (h - 8);
      ctx.strokeStyle = readCss("--color-border-strong", "#3a3a40");
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.beginPath();
    values.forEach((v, i) => {
      const x = (i / (values.length - 1)) * (w - 2) + 1;
      const y = h - 4 - ((v - min) / span) * (h - 8);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.strokeStyle = accent;
    ctx.lineWidth = 1.4;
    ctx.stroke();
  }, [values, accent, budget]);

  return <canvas ref={ref} className="h-9 w-full" />;
}

function Card({
  label,
  value,
  unit,
  series,
  accent,
  budget,
}: {
  label: string;
  value: string;
  unit?: string;
  series: number[];
  accent: string;
  budget?: number;
}) {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 px-2.5 py-2">
      <div className="flex items-baseline justify-between gap-2">
        <p className="text-xs text-muted">{label}</p>
        <p className="font-mono text-xs tabular-nums text-fg">
          {value}
          {unit ? <span className="text-muted"> {unit}</span> : null}
        </p>
      </div>
      <Spark values={series} accent={accent} budget={budget} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs text-muted">{label}</dt>
      <dd className="font-mono text-sm tabular-nums text-fg">{value}</dd>
    </div>
  );
}

function formatSample(s: PerfSample, mode: SimMode) {
  const graphs: { key: keyof PerfSample; label: string; value: string; unit?: string; budget?: number }[] = [
    { key: "fps", label: "FPS", value: String(s.fps), unit: "", budget: 60 },
    { key: "frameMs", label: "Frame", value: s.frameMs.toFixed(1), unit: "ms", budget: 16.7 },
    { key: "stepMs", label: "Physics", value: s.stepMs.toFixed(2), unit: "ms" },
    { key: "renderMs", label: "Draw", value: s.renderMs.toFixed(2), unit: "ms" },
    { key: "bodies", label: mode === "powder" ? "Cells" : "Particles", value: s.bodies.toLocaleString() },
    { key: "simMemKB", label: "Sim RAM", value: s.simMemKB.toLocaleString(), unit: "KB" },
  ];
  if (s.heapMB > 0) graphs.push({ key: "heapMB" as const, label: "JS heap", value: s.heapMB.toFixed(1), unit: "MB" });
  if (mode === "powder") {
    graphs.push(
      { key: "fillPct" as const, label: "Fill", value: String(s.fillPct), unit: "%" },
      { key: "maxTemp" as const, label: "Peak heat", value: String(s.maxTemp), unit: "°C" },
      { key: "avgTemp" as const, label: "Avg heat", value: String(s.avgTemp), unit: "°C" },
      { key: "wind" as const, label: "Wind", value: String(s.wind) },
    );
  } else {
    graphs.push(
      { key: "avgSpeed" as const, label: "Avg speed", value: s.avgSpeed.toFixed(1) },
      { key: "maxSpeed" as const, label: "Max speed", value: s.maxSpeed.toFixed(1) },
      { key: "nanCount" as const, label: "NaN", value: String(s.nanCount) },
      { key: "oobCount" as const, label: "OOB", value: String(s.oobCount) },
    );
  }
  return graphs;
}

export function PerfHud({ mode }: { mode: SimMode }) {
  const [open, setOpen] = useState(false);
  const [snap, setSnap] = useState<PerfSample>(telemetry.current);

  useEffect(() => {
    return telemetry.subscribe(() => setSnap({ ...telemetry.current }));
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) return;
      if (e.key === "`" || e.key.toLowerCase() === "p") {
        if (e.key.toLowerCase() === "p" && (e.metaKey || e.ctrlKey)) return;
        e.preventDefault();
        setOpen((v) => !v);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const tone = fpsTone(snap.fps);
  const accent = readCss(
    tone === "ok" ? "--color-ok" : tone === "warn" ? "--color-warn" : "--color-danger",
    "#7d9b84",
  );
  const silver = readCss("--color-primary", "#c8ccd4");
  const graphs = formatSample(snap, mode);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex h-11 min-w-11 items-center gap-1.5 rounded-md px-2 text-left hover:bg-subtle"
        aria-label="Open performance"
      >
        <Activity
          className={cn(
            "size-3.5",
            tone === "ok" && "text-ok",
            tone === "warn" && "text-warn",
            tone === "danger" && "text-danger",
          )}
        />
        <span className="font-mono text-xs tabular-nums leading-none">
          <span
            className={cn(
              "font-medium",
              tone === "ok" && "text-ok",
              tone === "warn" && "text-warn",
              tone === "danger" && "text-danger",
            )}
          >
            {snap.fps || "—"}
          </span>
          <span className="text-muted"> fps</span>
        </span>
      </button>

      <GlassSheet open={open} onClose={() => setOpen(false)} title="Performance" wide>
        <p className="mb-3 text-xs text-muted">
          {mode === "powder" ? "Powder world" : "Particle field"} · live graphs · drag or tap to close
        </p>
        <div className="mb-3 flex items-end justify-between gap-3 rounded-2xl border border-white/10 bg-white/5 px-3 py-3">
          <div>
            <p className="text-xs text-muted">Frame rate</p>
            <p className="font-display text-3xl font-semibold tabular-nums leading-none" style={{ color: accent }}>
              {snap.fps}
              <span className="ml-1 text-sm font-normal text-muted">fps</span>
            </p>
          </div>
          <p className="font-mono text-xs tabular-nums text-muted">
            {snap.frameMs.toFixed(1)} ms · {snap.bodies.toLocaleString()} live
          </p>
        </div>

        <div className="grid grid-cols-2 gap-2">
          {graphs.map((g) => (
            <Card
              key={g.key}
              label={g.label}
              value={g.value}
              unit={g.unit}
              series={telemetry.series(g.key)}
              accent={g.key === "fps" || g.key === "frameMs" ? accent : silver}
              budget={"budget" in g ? g.budget : undefined}
            />
          ))}
        </div>

        <dl className="mt-3 grid grid-cols-2 gap-3 rounded-2xl border border-white/10 bg-white/5 px-3 py-3">
          <Stat label="Canvas" value={`${snap.canvasW}×${snap.canvasH}`} />
          <Stat label="Speed" value={`${snap.speed}×${snap.paused ? " paused" : ""}`} />
          {mode === "powder" ? (
            <>
              <Stat label="Grid" value={`${snap.gridW}×${snap.gridH}`} />
              <Stat label="Sim RAM" value={`${snap.simMemKB.toLocaleString()} KB`} />
              <Stat label="Heat range" value={`${snap.minTemp}–${snap.maxTemp}°C`} />
              <Stat label="Ticks" value={snap.ticks.toLocaleString()} />
            </>
          ) : (
            <>
              <Stat label="Cap" value={snap.maxBodies.toLocaleString()} />
              <Stat label="Sim RAM" value={`${snap.simMemKB.toLocaleString()} KB`} />
              <Stat label="NaN / OOB" value={`${snap.nanCount} / ${snap.oobCount}`} />
              <Stat label="Heap" value={snap.heapMB ? `${snap.heapMB} MB` : "n/a"} />
            </>
          )}
        </dl>
      </GlassSheet>
    </>
  );
}
