"use client";

import { useCallback, useEffect, useState } from "react";
import { Atom, Columns2, Flame, Menu, Pause, Play, Timer } from "lucide-react";
import { Link } from "@tanstack/react-router";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { UserButton } from "@/lib/auth/gates";
import { cn } from "@/lib/utils";
import { PowderView } from "./powder-view";
import { ParticleView } from "./particle-view";
import {
  DiagnosticsOverlay,
  EditorOverlay,
  HelpOverlay,
  RoomOverlay,
  SavesOverlay,
  WorkshopOverlay,
} from "./lab-modals";
import { useP2PRoom } from "@/lib/multiplayer/use-p2p-room";
import { getParticleEngine, getPowderEngine, getRegistry } from "@/sim/engines";
import { Button } from "@/components/ui/button";
import { PerfHud } from "./perf-hud";
import { telemetry } from "@/sim/telemetry";
import { wireHybrid } from "@/sim/hybrid";
import { downloadLabScene, openLabSceneFile } from "@/sim/scene";
import { writeAutosave, readAutosave, clearAutosave } from "@/sim/autosave";
import { GlassSheet } from "./glass-sheet";
import { LAB_STATUS, markGlyph } from "./lab-status";

type Mode = "powder" | "particle";
type OverlayId = "help" | "saves" | "workshop" | "room" | "diag" | "editor" | "menu" | null;

type DrawPayload = {
  x: number;
  y: number;
  size: number;
  elementId: number;
  shape: "circle" | "square" | "spray" | "fill" | "replace";
};

function AuthChip() {
  const { user, isPending } = useCurrentUserState();
  if (isPending) return <div className="size-8 animate-pulse rounded-full bg-subtle" />;
  if (user) return <UserButton />;
  return (
    <Link
      to="/login"
      className="grid h-11 place-items-center rounded-md px-3 text-xs font-medium text-muted hover:text-fg"
    >
      Sign in
    </Link>
  );
}

function LiveRoom({
  room,
  name,
  onRemoteDraw,
  onSend,
  onHost,
}: {
  room: string;
  name: string;
  onRemoteDraw: (d: DrawPayload) => void;
  onSend: (fn: (d: unknown) => void) => void;
  onHost: (host: boolean) => void;
}) {
  const p2p = useP2PRoom({ room, name, enabled: true });
  const host =
    p2p.peers.length === 0 || p2p.selfId <= [...p2p.peers.map((p) => p.id), p2p.selfId].sort()[0];

  useEffect(() => {
    onHost(host);
  }, [host, onHost]);

  useEffect(() => {
    onSend((d) => p2p.send(d));
  }, [p2p, onSend]);

  useEffect(
    () =>
      p2p.onMessage((_from, data) => {
        const msg = data as {
          t?: string;
          powder?: string;
          lite?: string;
          gx?: number;
          gy?: number;
          collide?: boolean;
          b?: string;
          n?: number;
          snap?: ReturnType<ReturnType<typeof getParticleEngine>["liveSnapshot"]>;
        } & DrawPayload;
        if (!msg) return;
        if (msg.t === "draw") onRemoteDraw(msg);
        if (msg.t === "world" && msg.lite) {
          getPowderEngine().deserializeLite(msg.lite);
        } else if (msg.t === "world" && msg.powder) {
          try {
            getPowderEngine().deserializeState(msg.powder);
          } catch {
            /* ignore */
          }
        }
        if (msg.t === "part") {
          const pe = getParticleEngine();
          if (typeof msg.gx === "number") pe.gravityX = msg.gx;
          if (typeof msg.gy === "number") pe.gravityY = msg.gy;
          if (typeof msg.collide === "boolean") pe.collisionsEnabled = msg.collide;
        }
        if (msg.t === "psnap" && msg.snap) {
          getParticleEngine().applyLive(msg.snap);
        }
        if (msg.t === "px" && msg.b && msg.n) {
          getParticleEngine().applyPos(msg.n, msg.b);
        }
      }),
    [p2p, onRemoteDraw],
  );

  useEffect(() => {
    if (!p2p.joined) return;
    const host =
      p2p.peers.length === 0 || p2p.selfId <= [...p2p.peers.map((p) => p.id), p2p.selfId].sort()[0];
    if (!host) return;
    let lastHash = 0;
    let ticks = 0;
    const blast = () => {
      const pe = getParticleEngine();
      const n = pe.swarm.n;
      const powder = getPowderEngine();
      const h = powder.hashLite();
      if (h !== lastHash) {
        lastHash = h;
        p2p.send({ t: "world", lite: powder.serializeLite() });
      }
      const cap = n > 40000 ? 1600 : n > 8000 ? 2800 : n > 0 ? Math.min(n, 6000) : 400;
      ticks++;
      if (ticks % 3 === 0) {
        p2p.send({ t: "part", gx: pe.gravityX, gy: pe.gravityY, collide: pe.collisionsEnabled });
        p2p.send({ t: "psnap", snap: pe.liveSnapshot(cap) });
      } else {
        const pos = pe.livePos(cap);
        if (pos) p2p.send({ t: "px", n: pos.n, b: pos.b });
      }
    };
    blast();
    const onDump = () => blast();
    window.addEventListener("crucible:live-dump", onDump);
    const id = window.setInterval(blast, 110);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("crucible:live-dump", onDump);
    };
  }, [p2p]);

  return (
    <span className="hidden text-[11px] text-muted tabular-nums sm:inline">
      {p2p.joined ? `${p2p.peers.length} live${host ? " · host" : " · follow"}` : "joining…"}
    </span>
  );
}

export function LabApp() {
  const [mode, setMode] = useState<Mode>("powder");
  const [split, setSplit] = useState(false);
  const [bothClocks, setBothClocks] = useState(true);
  const [focus, setFocus] = useState<Mode>("powder");
  const [paused, setPaused] = useState(false);
  const [overlay, setOverlay] = useState<OverlayId>(null);
  const [recNext, setRecNext] = useState(false);
  const [fps, setFps] = useState(60);
  const [count, setCount] = useState(0);
  const [paletteTick, setPaletteTick] = useState(0);
  const [roomCode, setRoomCode] = useState("crucible");
  const [roomOn, setRoomOn] = useState(false);
  const [isHost, setIsHost] = useState(true);
  const [remoteDraw, setRemoteDraw] = useState<DrawPayload | null>(null);
  const [sendFn, setSendFn] = useState<(d: unknown) => void>(() => () => {});
  const { user } = useCurrentUserState();
  useState(() => {
    readAutosave();
    return 0;
  });

  useEffect(() => {
    getRegistry();
    wireHybrid();
  }, []);

  useEffect(() => {
    const onStop = () => setRecNext(true);
    window.addEventListener("crucible:rec-stop", onStop);
    return () => window.removeEventListener("crucible:rec-stop", onStop);
  }, []);

  useEffect(() => {
    const id = window.setInterval(writeAutosave, 8000);
    const onHide = () => writeAutosave();
    window.addEventListener("pagehide", onHide);
    return () => {
      window.clearInterval(id);
      window.removeEventListener("pagehide", onHide);
    };
  }, []);

  useEffect(() => {
    if (split || !bothClocks) return;
    let raf = 0;
    const loop = () => {
      if (!paused && !(roomOn && !isHost)) {
        if (mode === "powder") getParticleEngine().step();
        else getPowderEngine().step();
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [mode, split, paused, bothClocks, roomOn, isHost]);

  useEffect(() => {
    telemetry.reset();
  }, [mode]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement;
      if (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) return;
      if (e.key === " ") {
        e.preventDefault();
        setPaused((v) => !v);
      } else if (e.key === "Tab") {
        e.preventDefault();
        setMode((m) => (m === "powder" ? "particle" : "powder"));
      } else if (e.key === "h" || e.key === "H") {
        setOverlay("help");
      } else if (e.key === "i" || e.key === "I") {
        setOverlay("diag");
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const onFps = useCallback((f: number, c: number) => {
    setFps(f);
    setCount(c);
  }, []);

  const onDraw = useCallback(
    (p: DrawPayload) => {
      if (roomOn) sendFn({ t: "draw", ...p });
    },
    [roomOn, sendFn],
  );

  const closeHelp = () => {
    setOverlay(null);
  };

  return (
    <div className="flex h-dvh flex-col bg-bg text-fg">
      <header className="border-b border-white/12 bg-black/40 pt-[max(0.4rem,env(safe-area-inset-top))] backdrop-blur-3xl">
        <div className="flex items-center gap-2 px-3 pb-1">
          <div className="min-w-0 flex-1">
            <p className="font-display text-base font-semibold leading-none tracking-tight">Crucible</p>
            <p className="mt-0.5 text-[11px] text-muted">{mode === "powder" ? "Powder world" : "Particle field"}</p>
          </div>
          <button
            type="button"
            onClick={() => setPaused((v) => !v)}
            className="grid size-11 place-items-center rounded-full bg-white/8 text-muted hover:text-fg"
            aria-label={paused ? "Play" : "Pause"}
          >
            {paused ? <Play className="size-4" /> : <Pause className="size-4" />}
          </button>
          <button
            type="button"
            onClick={() => setOverlay("menu")}
            className="grid size-11 place-items-center rounded-full bg-white/8 text-muted hover:text-fg"
            aria-label="Menu"
          >
            <Menu className="size-4" />
          </button>
        </div>
        <div className="flex items-center gap-1 overflow-x-auto px-2 pb-2">
          <div className="flex shrink-0 rounded-full border border-white/12 bg-white/6 p-0.5">
            <button
              type="button"
              onClick={() => setMode("powder")}
              className={cn(
                "flex h-9 items-center gap-1.5 rounded-full px-3 text-xs font-medium",
                mode === "powder" ? "bg-primary text-primary-fg" : "text-muted hover:text-fg",
              )}
            >
              <Flame className="size-3.5" />
              Powder
            </button>
            <button
              type="button"
              onClick={() => setMode("particle")}
              className={cn(
                "flex h-9 items-center gap-1.5 rounded-full px-3 text-xs font-medium",
                mode === "particle" ? "bg-primary text-primary-fg" : "text-muted hover:text-fg",
              )}
            >
              <Atom className="size-3.5" />
              Particles
            </button>
          </div>
          <button
            type="button"
            onClick={() => setSplit((v) => !v)}
            className={cn(
              "grid size-9 shrink-0 place-items-center rounded-full",
              split ? "text-fg" : "text-muted hover:text-fg",
            )}
            aria-label="Split view"
          >
            <Columns2 className="size-4" />
          </button>
          <button
            type="button"
            onClick={() => setBothClocks((v) => !v)}
            className={cn(
              "grid size-9 shrink-0 place-items-center rounded-full",
              bothClocks ? "text-fg" : "text-muted hover:text-fg",
            )}
            aria-label="Both rooms keep time"
          >
            <Timer className="size-4" />
          </button>
          <div className="ml-auto flex shrink-0 items-center gap-1">
            <PerfHud mode={mode} />
            {roomOn && (
              <LiveRoom
                room={roomCode}
                name={user?.displayName || "guest"}
                onRemoteDraw={setRemoteDraw}
                onSend={(fn) => setSendFn(() => fn)}
                onHost={setIsHost}
              />
            )}
            <AuthChip />
          </div>
        </div>
      </header>

      {split ? (
        <div className="flex min-h-0 flex-1 flex-col md:flex-row">
          <div
            className={cn("flex min-h-0 min-w-0 flex-1 flex-col", focus === "powder" && "bg-elevated/20")}
            onPointerDownCapture={() => {
              setFocus("powder");
              setMode("powder");
            }}
          >
            <PowderView
              paused={paused}
              onFps={onFps}
              onDraw={onDraw}
              remoteDraw={remoteDraw}
              paletteTick={paletteTick}
            compact={focus !== "powder"}
            follow={roomOn && !isHost}
            />
          </div>
          <div
            className={cn("flex min-h-0 min-w-0 flex-1 flex-col border-t border-border md:border-l md:border-t-0", focus === "particle" && "bg-elevated/20")}
            onPointerDownCapture={() => {
              setFocus("particle");
              setMode("particle");
            }}
          >
            <ParticleView paused={paused} onFps={onFps} compact={focus !== "particle"} follow={roomOn && !isHost} />
          </div>
        </div>
      ) : mode === "powder" ? (
        <PowderView
          paused={paused}
          onFps={onFps}
          onDraw={onDraw}
          remoteDraw={remoteDraw}
          paletteTick={paletteTick}
          follow={roomOn && !isHost}
        />
      ) : (
        <ParticleView paused={paused} onFps={onFps} follow={roomOn && !isHost} />
      )}

      {recNext && (
        <GlassSheet open onClose={() => setRecNext(false)} title="Clip ready">
          <p className="px-1 pb-3 text-sm text-muted">Share sheet should have popped. If not, the file downloaded.</p>
          <p className="px-1 pb-2 font-display text-sm font-semibold">What’s next</p>
          <button
            type="button"
            className="mb-2 w-full rounded-2xl bg-white/8 px-4 py-3 text-left"
            onClick={() => {
              setRecNext(false);
              setMode("particle");
            }}
          >
            <p className="text-sm font-medium">1 · Smoother million</p>
            <p className="text-[12px] text-muted">Open Particles, turn Collide on, dump +50k / +500k. They shove in place now. True glass marbles at 60fps is still the hard job.</p>
          </button>
          <button
            type="button"
            className="w-full rounded-2xl bg-white/8 px-4 py-3 text-left"
            onClick={() => {
              setRecNext(false);
              setOverlay("room");
            }}
          >
            <p className="text-sm font-medium">2 · Same world, two phones</p>
            <p className="text-[12px] text-muted">Live room copies powder + a sample of the swarm, about twice a second. Not every grain of a million.</p>
          </button>
          <button
            type="button"
            className="mt-3 h-12 w-full rounded-full bg-primary text-sm font-medium text-primary-fg"
            onClick={() => setRecNext(false)}
          >
            Done
          </button>
        </GlassSheet>
      )}

      <HelpOverlay open={overlay === "help"} onClose={closeHelp} />
      <SavesOverlay open={overlay === "saves"} onClose={() => setOverlay(null)} mode={mode} />
      <WorkshopOverlay open={overlay === "workshop"} onClose={() => setOverlay(null)} />
      <EditorOverlay
        open={overlay === "editor"}
        onClose={() => setOverlay(null)}
        onSaved={() => setPaletteTick((n) => n + 1)}
      />
      <DiagnosticsOverlay
        open={overlay === "diag"}
        onClose={() => setOverlay(null)}
        fps={fps}
        count={count}
        mode={mode}
      />
      <RoomOverlay
        open={overlay === "room"}
        onClose={() => setOverlay(null)}
        roomCode={roomCode}
        setRoomCode={setRoomCode}
        connected={roomOn}
        peers={[]}
        onJoin={() => {
          setRoomOn(true);
          setOverlay(null);
        }}
        onLeave={() => setRoomOn(false)}
      />

      {overlay === "menu" && (
        <GlassSheet open onClose={() => setOverlay(null)} title="Lab" wide>
          <p className="px-1 pb-3 text-xs text-muted">Tap a row. Drag the bar down to close.</p>
          <ul className="mb-4 space-y-1">
            {LAB_STATUS.map((row) => (
              <li
                key={row.name}
                className="flex items-start gap-2 rounded-2xl bg-white/5 px-3 py-2.5"
              >
                <span className="mt-0.5 text-sm leading-none">{markGlyph(row.mark)}</span>
                <div className="min-w-0">
                  <p className="text-sm font-medium text-fg">{row.name}</p>
                  <p className="text-[11px] text-muted">{row.note}</p>
                </div>
              </li>
            ))}
          </ul>
          <p className="px-1 pb-2 text-[11px] text-muted">✅ in · ☑️ just shipped / live · ✔️ next</p>
          <div className="space-y-1">
            {[
              ["editor", "Element editor"],
              ["workshop", "Workshop maps"],
              ["saves", "Cloud saves"],
              ["room", "Live room — same powder world"],
              ["diag", "Diagnostics"],
              ["help", "How to use"],
            ].map(([id, label]) => (
              <button
                key={id}
                type="button"
                className="flex h-12 w-full items-center rounded-2xl px-3 text-left text-sm hover:bg-white/8"
                onClick={() => setOverlay(id as OverlayId)}
              >
                {label}
              </button>
            ))}
            <button
              type="button"
              className="flex h-12 w-full items-center rounded-2xl px-3 text-left text-sm hover:bg-white/8"
              onClick={() => {
                downloadLabScene();
                setOverlay(null);
              }}
            >
              Export scene
            </button>
            <button
              type="button"
              className="flex h-12 w-full items-center rounded-2xl px-3 text-left text-sm hover:bg-white/8"
              onClick={async () => {
                await openLabSceneFile();
                setOverlay(null);
              }}
            >
              Import scene
            </button>
            <button
              type="button"
              className="flex h-12 w-full items-center rounded-2xl px-3 text-left text-sm hover:bg-white/8"
              onClick={() => {
                writeAutosave();
                setOverlay(null);
              }}
            >
              Save on this phone
            </button>
            <button
              type="button"
              className="flex h-12 w-full items-center rounded-2xl px-3 text-left text-sm hover:bg-white/8"
              onClick={() => {
                clearAutosave();
                setOverlay(null);
              }}
            >
              Forget phone save
            </button>
          </div>
        </GlassSheet>
      )}
    </div>
  );
}
