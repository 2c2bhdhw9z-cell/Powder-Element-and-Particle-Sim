"use client";

import { useCallback, useEffect, useState } from "react";
import { Overlay } from "./overlay";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getPowderEngine, getParticleEngine, getRegistry } from "@/sim/engines";
import { exportLabScene, importLabScene } from "@/sim/scene";
import {
  createSave,
  deleteSave,
  downloadMap,
  likeMap,
  listMaps,
  listSaves,
  loadSave,
  publishMap,
} from "@/lib/lab-api";
import { useCurrentUserState } from "@/lib/auth/use-current-user";
import { Link } from "@tanstack/react-router";
import type { ElementDefinition, InteractionRule } from "@/sim/types";
import type { PeerInfo } from "@/lib/multiplayer";
import { telemetry } from "@/sim/telemetry";
import { PERIODIC, COMPOUNDS } from "@/sim/periodic";
import { loreFor } from "@/sim/encyclopedia";

export function HelpOverlay({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Overlay open={open} onClose={onClose} title="Lab notes">
      <div className="space-y-3 text-sm text-muted">
        <p>Two chambers. Powder is falling matter. Particles are free bodies. Switch anytime — both keep their state.</p>
        <ul className="space-y-1.5 font-medium text-fg">
          <li>Space pause · Tab switch · Ctrl+Z undo</li>
          <li>P performance graphs · I diagnostics</li>
          <li>[ ] brush size · E eraser · B brush · T heatmap</li>
          <li>S screenshot · R record · C clear</li>
          <li>Recipes: volcano, ant farm, oil fire, ice dam, reactor, storm</li>
          <li>Table maps real elements. Tap the inspect chip for encyclopedia</li>
          <li>Today is the same world for everyone that UTC day</li>
          <li>Split (header icon): both chambers live. Tap one to get its dock</li>
          <li>Undo is shared across chambers</li>
          <li>Blasts throw particles. Settle drops them back as sand/water</li>
          <li>Pour is SPH water. GPU path kicks in above ~2k particles</li>
          <li>Flock / Cloth / N-body presets. Fan + wet mix in powder</li>
          <li>Water erodes sand. Sealed steam can rupture. Void sucks pressure</li>
          <li>Blob is jelly. Hold on flock to scare them. Pull cloth to rip it</li>
          <li>Paint a fan again to rotate it. Live room copies the powder world</li>
          <li>Huge particle dumps use the fast swarm. Menu has the checklist</li>
        </ul>
        <p>Water boils, oil floats and burns, lava melts, ice freezes, acid eats, sparks travel metal, plants drink, C4 and hydrogen boom.</p>
      </div>
    </Overlay>
  );
}

export function SavesOverlay({
  open,
  onClose,
  mode,
}: {
  open: boolean;
  onClose: () => void;
  mode: "powder" | "particle";
}) {
  const { user, isPending } = useCurrentUserState();
  const [name, setName] = useState("");
  const [rows, setRows] = useState<{ id: string; name: string; mode: string; created_at: string }[]>([]);
  const [msg, setMsg] = useState("");

  const refresh = useCallback(() => {
    if (!user) return;
    listSaves()
      .then(setRows)
      .catch(() => setRows([]));
  }, [user]);

  useEffect(() => {
    if (open && user) refresh();
  }, [open, user, refresh]);

  return (
    <Overlay open={open} onClose={onClose} title="Saves">
      {isPending ? (
        <div className="h-24 animate-pulse rounded-md bg-subtle" />
      ) : !user ? (
        <div className="space-y-3 text-sm">
          <p className="text-muted">Sign in to keep cloud saves. Local canvas state already survives a chamber switch.</p>
          <Button asChild className="w-full">
            <Link to="/login">Sign in</Link>
          </Button>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="flex gap-2">
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Snapshot name" />
            <Button
              onClick={async () => {
                const data =
                  mode === "powder"
                    ? getPowderEngine().serializeState()
                    : JSON.stringify(exportLabScene());
                await createSave({
                  data: { name: name.trim() || `${mode} snapshot`, mode, data },
                });
                setName("");
                setMsg("Saved");
                refresh();
              }}
            >
              Save
            </Button>
          </div>
          {msg && <p className="text-xs text-muted">{msg}</p>}
          <ul className="space-y-2">
            {rows.map((r) => (
              <li key={r.id} className="flex items-center justify-between gap-2 rounded-md border border-border px-3 py-2">
                <div>
                  <p className="text-sm font-medium">{r.name}</p>
                  <p className="text-xs text-muted">{r.mode}</p>
                </div>
                <div className="flex gap-1">
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={async () => {
                      const row = await loadSave({ data: r.id });
                      if (!row) return;
                      if (row.mode === "powder") getPowderEngine().deserializeState(row.data);
                      else {
                        try {
                          const parsed = JSON.parse(row.data);
                          if (parsed?.v === 1) importLabScene(parsed);
                          else if (Array.isArray(parsed)) getParticleEngine().particles = parsed;
                        } catch {
                          /* ignore */
                        }
                      }
                      onClose();
                    }}
                  >
                    Load
                  </Button>
                  <Button size="sm" variant="ghost" onClick={async () => { await deleteSave({ data: r.id }); refresh(); }}>
                    Delete
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </Overlay>
  );
}

export function WorkshopOverlay({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const { user } = useCurrentUserState();
  const [tab, setTab] = useState<"browse" | "publish">("browse");
  const [maps, setMaps] = useState<Awaited<ReturnType<typeof listMaps>>>([]);
  const [title, setTitle] = useState("");
  const [desc, setDesc] = useState("");
  const [tag, setTag] = useState("all");
  const [sort, setSort] = useState<"new" | "hot">("hot");
  const [tagsInput, setTagsInput] = useState("sandbox");

  useEffect(() => {
    if (open) listMaps().then(setMaps).catch(() => setMaps([]));
  }, [open]);

  return (
    <Overlay open={open} onClose={onClose} title="Workshop" wide>
      <div className="mb-3 flex gap-1">
        <Button size="sm" variant={tab === "browse" ? "default" : "ghost"} onClick={() => setTab("browse")}>
          Browse
        </Button>
        <Button size="sm" variant={tab === "publish" ? "default" : "ghost"} onClick={() => setTab("publish")}>
          Publish
        </Button>
      </div>
      {tab === "browse" ? (
        <>
          <div className="mb-3 flex flex-wrap gap-1">
            <button
              type="button"
              onClick={() => listMaps().then(setMaps).catch(() => setMaps([]))}
              className="h-8 rounded-full bg-white/8 px-3 text-xs text-muted"
            >
              Refresh
            </button>
            {(["hot", "new"] as const).map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => setSort(s)}
                className={`h-8 rounded-full px-3 text-xs capitalize ${sort === s ? "bg-primary text-primary-fg" : "bg-white/8 text-muted"}`}
              >
                {s}
              </button>
            ))}
            {["all", "sandbox", "volcano", "storm", "puzzle", "remix"].map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTag(t)}
                className={`h-8 rounded-full px-3 text-xs capitalize ${tag === t ? "bg-primary text-primary-fg" : "bg-white/8 text-muted"}`}
              >
                {t}
              </button>
            ))}
          </div>
        <ul className="space-y-3">
          {(() => {
            const rows = maps
              .filter((m) => tag === "all" || (m.tags || "").toLowerCase().includes(tag))
              .slice()
              .sort((a, b) => (sort === "hot" ? b.likes - a.likes : b.created_at.localeCompare(a.created_at)));
            if (rows.length === 0) {
              return <p className="text-sm text-muted">No maps yet. Publish the basin you’re painting.</p>;
            }
            return rows.map((m) => (
            <li key={m.id} className="overflow-hidden rounded-2xl border border-white/10 bg-white/5">
              {m.thumbnail ? <img src={m.thumbnail} alt="" className="h-28 w-full object-cover" /> : null}
              <div className="p-3">
              <p className="font-medium">{m.title}</p>
              <p className="text-xs text-muted">
                {m.author} · {m.likes} likes · {m.downloads} plays · {m.tags || "sandbox"}
              </p>
              <p className="mt-1 text-sm text-muted">{m.description}</p>
              <div className="mt-2 flex gap-2">
                <Button
                  size="sm"
                  onClick={async () => {
                    const row = await downloadMap({ data: m.id });
                    if (row?.grid_data) getPowderEngine().deserializeState(row.grid_data);
                    onClose();
                  }}
                >
                  Load
                </Button>
                <Button size="sm" variant="outline" onClick={() => likeMap({ data: m.id }).then(() => listMaps().then(setMaps))}>
                  Like
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={async () => {
                    const row = await downloadMap({ data: m.id });
                    if (row?.grid_data) getPowderEngine().deserializeState(row.grid_data);
                    onClose();
                  }}
                >
                  Remix
                </Button>
              </div>
              </div>
            </li>
            ));
          })()}
        </ul>
        </>
      ) : !user ? (
        <p className="text-sm text-muted">
          Sign in to publish.{" "}
          <Link to="/login" className="text-fg underline">
            Sign in
          </Link>
        </p>
      ) : (
        <div className="space-y-3">
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Map title" />
          <Input value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="What should people try?" />
          <Input value={tagsInput} onChange={(e) => setTagsInput(e.target.value)} placeholder="tags: volcano, remix, puzzle" />
          <Button
            className="w-full"
            disabled={!title.trim()}
            onClick={async () => {
              const engine = getPowderEngine();
              await publishMap({
                data: {
                  title: title.trim(),
                  description: desc,
                  tags: tagsInput.trim() || "sandbox",
                  thumbnail: engine.captureThumbnail(240),
                  gridData: engine.serializeState(),
                },
              });
              setTitle("");
              setDesc("");
              setTab("browse");
              listMaps().then(setMaps);
            }}
          >
            Publish current powder world
          </Button>
        </div>
      )}
    </Overlay>
  );
}

export function RoomOverlay({
  open,
  onClose,
  roomCode,
  setRoomCode,
  connected,
  peers,
  onJoin,
  onLeave,
}: {
  open: boolean;
  onClose: () => void;
  roomCode: string;
  setRoomCode: (v: string) => void;
  connected: boolean;
  peers: PeerInfo[];
  onJoin: () => void;
  onLeave: () => void;
}) {
  return (
    <Overlay open={open} onClose={onClose} title="Live room">
      <div className="space-y-3 text-sm">
        <p className="text-muted">
          Casual co-op paint. Peers share a powder brush. Up to 8 people. Not for competitive play.
        </p>
        <Input
          value={roomCode}
          onChange={(e) => setRoomCode(e.target.value.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 24))}
          placeholder="Room code"
        />
        {connected ? (
          <>
            <p className="text-xs text-muted">{peers.length} connected</p>
            <ul className="text-xs text-muted">
              {peers.map((p) => (
                <li key={p.id}>
                  {p.name} · {p.connectionState}
                  {p.rttMs != null ? ` · ${Math.round(p.rttMs)}ms` : ""}
                </li>
              ))}
            </ul>
            <Button variant="outline" className="w-full" onClick={onLeave}>
              Leave
            </Button>
          </>
        ) : (
          <Button className="w-full" onClick={onJoin} disabled={!roomCode}>
            Join room
          </Button>
        )}
      </div>
    </Overlay>
  );
}

export function DiagnosticsOverlay({
  open,
  onClose,
  fps,
  count,
  mode,
}: {
  open: boolean;
  onClose: () => void;
  fps: number;
  count: number;
  mode: "powder" | "particle";
}) {
  const powder = getPowderEngine();
  const particle = getParticleEngine();
  const t = telemetry.current;
  const d = mode === "powder" ? powder.getDiagnostics() : particle.getDiagnostics();
  return (
    <Overlay open={open} onClose={onClose} title="Diagnostics">
      <dl className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt className="text-xs text-muted">FPS</dt>
          <dd className="font-mono font-medium tabular-nums">{fps || t.fps}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">{mode === "powder" ? "Cells" : "Particles"}</dt>
          <dd className="font-mono font-medium tabular-nums">{count.toLocaleString()}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Physics</dt>
          <dd className="font-mono tabular-nums">{t.stepMs.toFixed(2)} ms</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Draw</dt>
          <dd className="font-mono tabular-nums">{t.renderMs.toFixed(2)} ms</dd>
        </div>
        {mode === "powder" && "width" in d && (
          <>
            <div>
              <dt className="text-xs text-muted">Grid</dt>
              <dd className="font-mono tabular-nums">
                {d.width}×{d.height}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Fill</dt>
              <dd className="font-mono tabular-nums">{d.loadPercentage}%</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Heat</dt>
              <dd className="font-mono tabular-nums">
                {d.minTemp}–{d.maxTemp}°C
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Sim RAM</dt>
              <dd className="font-mono tabular-nums">{Math.round(d.memoryBytes / 1024)} KB</dd>
            </div>
          </>
        )}
        {mode === "particle" && "particleCount" in d && (
          <>
            <div>
              <dt className="text-xs text-muted">Cap</dt>
              <dd className="font-mono tabular-nums">{d.maxParticles.toLocaleString()}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Max speed</dt>
              <dd className="font-mono tabular-nums">{d.maxSpeedFound}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">NaN / OOB</dt>
              <dd className="font-mono tabular-nums">
                {d.nanCount} / {d.outOfBoundsCount}
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Sim RAM</dt>
              <dd className="font-mono tabular-nums">{Math.round(d.memoryBytes / 1024)} KB</dd>
            </div>
          </>
        )}
      </dl>
      <p className="mt-4 text-xs text-muted">Open Performance in the header (or tap P) for live graphs of every metric.</p>
    </Overlay>
  );
}

export function EditorOverlay({
  open,
  onClose,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const registry = getRegistry();
  const next = registry.getNextAvailableId();
  const [id, setId] = useState(next === -1 ? 50 : next);
  const [name, setName] = useState("Alloy");
  const [color, setColor] = useState("#c8ccd4");
  const [state, setState] = useState<ElementDefinition["state"]>("solid_movable");
  const [density, setDensity] = useState(15);
  const [flam, setFlam] = useState(0);
  const [grav, setGrav] = useState(1);
  const [target, setTarget] = useState(2);
  const [chance, setChance] = useState(0.4);
  const [result, setResult] = useState(0);

  useEffect(() => {
    if (!open) return;
    const nid = registry.getNextAvailableId();
    if (nid !== -1) setId(nid);
  }, [open, registry]);

  const builtins = registry.getAllElements().filter((e) => e.id < 50);

  return (
    <Overlay open={open} onClose={onClose} title="Element editor" wide>
      <div className="space-y-3 text-sm">
        <p className="text-muted">Slots 50–99 are yours. Make a powder, a liquid, or a gas. Give it a reaction.</p>
        <div className="flex gap-1 overflow-x-auto pb-1">
          {[
            { name: "Goo", color: "#86efac", state: "liquid" as const, density: 9, flam: 0, grav: 1, target: 2, chance: 0.2, result: 11 },
            { name: "Foam", color: "#e7e5e4", state: "gas" as const, density: 2, flam: 10, grav: -0.2, target: 4, chance: 0.5, result: 5 },
            { name: "Slag", color: "#78716c", state: "solid_movable" as const, density: 22, flam: 0, grav: 1, target: 6, chance: 0.35, result: 7 },
          ].map((p) => (
            <button
              key={p.name}
              type="button"
              className="h-9 shrink-0 rounded-full bg-white/8 px-3 text-xs"
              onClick={() => {
                setName(p.name);
                setColor(p.color);
                setState(p.state);
                setDensity(p.density);
                setFlam(p.flam);
                setGrav(p.grav);
                setTarget(p.target);
                setChance(p.chance);
                setResult(p.result);
              }}
            >
              {p.name}
            </button>
          ))}
        </div>
        <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Name" />
        <div className="flex gap-2">
          <Input type="color" value={color} onChange={(e) => setColor(e.target.value)} className="w-16 p-1" />
          <select
            className="h-11 flex-1 rounded-md border border-border bg-elevated px-3"
            value={state}
            onChange={(e) => setState(e.target.value as ElementDefinition["state"])}
          >
            <option value="solid_movable">Powder</option>
            <option value="solid_fixed">Solid</option>
            <option value="liquid">Liquid</option>
            <option value="gas">Gas</option>
            <option value="plasma">Plasma</option>
          </select>
        </div>
        <div className="grid grid-cols-3 gap-2 text-xs text-muted">
          <label>
            Density
            <Input type="number" value={density} onChange={(e) => setDensity(Number(e.target.value))} />
          </label>
          <label>
            Flame 0–100
            <Input type="number" value={flam} onChange={(e) => setFlam(Number(e.target.value))} />
          </label>
          <label>
            Gravity
            <Input type="number" step="0.1" value={grav} onChange={(e) => setGrav(Number(e.target.value))} />
          </label>
        </div>
        <p className="text-xs font-medium text-fg">Reaction</p>
        <div className="grid grid-cols-3 gap-2">
          <select className="h-11 rounded-md border border-border bg-elevated px-2 text-xs" value={target} onChange={(e) => setTarget(Number(e.target.value))}>
            {builtins.map((e) => (
              <option key={e.id} value={e.id}>
                touches {e.name}
              </option>
            ))}
          </select>
          <Input type="number" step="0.05" value={chance} onChange={(e) => setChance(Number(e.target.value))} />
          <select className="h-11 rounded-md border border-border bg-elevated px-2 text-xs" value={result} onChange={(e) => setResult(Number(e.target.value))}>
            <option value={0}>become Air</option>
            {builtins.map((e) => (
              <option key={e.id} value={e.id}>
                become {e.name}
              </option>
            ))}
          </select>
        </div>
        <Button
          className="w-full"
          onClick={() => {
            const slot = registry.getNextAvailableId();
            const useId = slot === -1 ? id : slot;
            const interactions: InteractionRule[] =
              chance > 0
                ? [{ targetElementId: target, chance, resultSelfId: result }]
                : [];
            registry.registerElement({
              id: useId,
              name: name.trim() || `Element ${useId}`,
              category: "Custom",
              state,
              color,
              density,
              flammability: flam,
              gravityFactor: grav,
              interactions,
              description: "Custom lab element",
            });
            onSaved();
            onClose();
          }}
        >
          Save element
        </Button>
        <ul className="space-y-1">
          {registry
            .getAllElements()
            .filter((e) => e.id >= 50)
            .map((e) => (
              <li key={e.id} className="flex items-center justify-between rounded-2xl bg-white/5 px-3 py-2 text-xs">
                <span>
                  {e.name} <span className="text-muted">#{e.id}</span>
                </span>
                <button
                  type="button"
                  className="text-muted"
                  onClick={() => {
                    registry.deleteCustomElement(e.id);
                    onSaved();
                  }}
                >
                  Delete
                </button>
              </li>
            ))}
        </ul>
      </div>
    </Overlay>
  );
}

export function PeriodicOverlay({
  open,
  onClose,
  onPick,
}: {
  open: boolean;
  onClose: () => void;
  onPick: (elementId: number) => void;
}) {
  const registry = getRegistry();
  return (
    <Overlay open={open} onClose={onClose} title="Periodic drawer" wide>
      <p className="mb-3 text-xs text-muted">Tap a real element. We map it onto the closest thing the lab can simulate.</p>
      <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
        {PERIODIC.map((el) => {
          const mapped = registry.getElement(el.mapsTo);
          return (
            <button
              key={el.symbol}
              type="button"
              onClick={() => {
                onPick(el.mapsTo);
                onClose();
              }}
              className="rounded-md border border-border px-2 py-2 text-left hover:bg-subtle"
            >
              <p className="font-display text-lg leading-none">{el.symbol}</p>
              <p className="mt-1 text-xs text-muted">{el.name}</p>
              <p className="mt-0.5 font-mono text-xs text-subtle-fg">{mapped.name}</p>
            </button>
          );
        })}
      </div>
      <p className="mb-2 mt-4 text-xs text-muted">Compounds</p>
      <div className="grid grid-cols-3 gap-2">
        {COMPOUNDS.map((el) => (
          <button
            key={el.symbol}
            type="button"
            onClick={() => {
              onPick(el.mapsTo);
              onClose();
            }}
            className="rounded-md border border-border px-2 py-2 text-left hover:bg-subtle"
          >
            <p className="font-mono text-sm">{el.symbol}</p>
            <p className="text-xs text-muted">{el.why}</p>
          </button>
        ))}
      </div>
    </Overlay>
  );
}

export function LoreOverlay({
  open,
  onClose,
  elementId,
}: {
  open: boolean;
  onClose: () => void;
  elementId: number | null;
}) {
  const registry = getRegistry();
  if (!open || elementId == null) return null;
  const el = registry.getElement(elementId);
  const lore = loreFor(elementId);
  return (
    <Overlay open={open} onClose={onClose} title={el.name}>
      <div className="flex items-start gap-3">
        <span className="mt-1 size-4 rounded-[3px]" style={{ backgroundColor: el.color }} />
        <div className="min-w-0 flex-1">
          <p className="text-sm text-muted">{el.description || lore.note}</p>
          <dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
            <div>
              <dt className="text-xs text-muted">Density</dt>
              <dd className="font-mono tabular-nums">{el.density}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">State</dt>
              <dd className="capitalize">{el.state.replace("_", " ")}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Melt</dt>
              <dd className="font-mono">{lore.melt ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted">Boil</dt>
              <dd className="font-mono">{lore.boil ?? "—"}</dd>
            </div>
          </dl>
          <p className="mt-3 text-xs text-muted">Eats</p>
          <p className="text-sm">{lore.eats}</p>
          <p className="mt-3 text-xs text-muted">Note</p>
          <p className="text-sm">{lore.note}</p>
        </div>
      </div>
    </Overlay>
  );
}
