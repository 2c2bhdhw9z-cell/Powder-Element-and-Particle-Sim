# Debug brief (for another AI)

Crucible is a dual lab: **powder world** + **particle field**. User switches anytime. iPhone 17 Pro Max, iOS glass UI.

Do **not** restore the old `src/engine/` / `ParticleSandbox` / `PowderSandbox` project. That was deleted on purpose.

## Run

```bash
npm install
npm run dev          # vite, 0.0.0.0:8080
npm run typecheck
npm test             # sim core (vitest) + scripts (node --test)
```

TanStack Start + Vite. Entry: `src/routes/index.tsx` → `LabApp`.

## Map

| Path | What |
|---|---|
| `src/sim/powder-engine.ts` | PowderEngine facade (state + tick). Physics lives in `src/sim/powder/*.ts` modules on the `PowderCtx` interface (phase-change, electricity, reactions, explosion, movement, thermals, brush, history, render, diagnostics) |
| `src/sim/particle-engine.ts` | ParticleEngine facade (state + tick). Physics lives in `src/sim/particle/*.ts` (spawners, step, render, diagnostics) on the `ParticleCtx` interface |
| `src/sim/__tests__/` | Vitest suite (deterministic, seeded RNG). `npm test` — keep it green when touching sim code |
| `src/sim/swarm.ts` | CPU SoA pack for huge dumps |
| `src/sim/swarm-gpu.ts` | WebGPU collide (linked-list). Draw often falls back to WebGL |
| `src/sim/particle-gl.ts` | WebGL points draw |
| `src/sim/element-registry.ts` | Element defs |
| `src/sim/live-pack.ts` | Compact Int16 snapshots for P2P |
| `src/lib/multiplayer/p2p.ts` | WebRTC room |
| `src/components/lab/lab-app.tsx` | Shell, mode switch, split, menus |
| `src/components/lab/powder-view.tsx` | Powder canvas + brushes |
| `src/components/lab/particle-view.tsx` | Particle canvas + presets |
| `src/components/lab/glass-sheet.tsx` | Draggable iOS glass sheets. Must scroll. Title at top. Safe area |
| `src/components/lab/perf-hud.tsx` | FPS / graphs. Must not sit *in* the sim. Must fit under Dynamic Island |

## Known bugs (user-reported)

1. **Water looks glittery / glitchy** — sparkle flicker while flowing.
2. **Lava vs water never finishes** — they stall; neither wins into steam/stone the way it should.
3. **1,000,000 particles ~10 FPS** — Physics ~103ms. Not a fake 10 FPS cap. Need faster collide / less CPU.
4. **Black canvas after dump** — GPU present + alpha-0 colors hid dots. WebGL should be the visible path. GPU canvas must not cover it.
5. **Perf menu clipped** — Dynamic Island / Grok chrome ate the top. Sheets need `max-h` ~72dvh, title visible, scrollable.
6. **Name covered by chrome** — header “Crucible” must sit below safe-area.
7. **Live room** — guest must *see* the host universe (powder grid + a sample of the swarm). Sample sizes must match.

## Rules from the owner

- Mobile first (17 Pro Max). 44px taps. Glass sheets open/close (drag or tap).
- Menus are overlays, **not** painted into the sim.
- Owner does **not** code. Talk in product terms if you comment.
- Do not add screenshots/videos the user sent in chat.
- Do not reintroduce the unfinished original sim.

## What “fixed” looks like

- Pour water: no glitter. Mix lava+water: one side actually wins (obsidian/steam/stone).
- Dump 20k+ particles: you **see** them. Collide on: they shove, they don’t tunnel.
- Million dump: FPS is whatever the phone can do, not stuck at 10 unless physics really costs that.
- Performance sheet: full list + graphs, scrolls, none of it covering the title.
- Two phones, same room code: same powder world, swarm sample follows.
