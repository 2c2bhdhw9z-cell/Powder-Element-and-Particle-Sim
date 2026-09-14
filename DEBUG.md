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

| Path                                   | What                                                                                                                                                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/sim/powder-engine.ts`             | PowderEngine facade (state + tick). Physics lives in `src/sim/powder/*.ts` modules on the `PowderCtx` interface (phase-change, electricity, reactions, explosion, movement, thermals, brush, history, render, diagnostics) |
| `src/sim/particle-engine.ts`           | ParticleEngine facade (state + tick). Physics lives in `src/sim/particle/*.ts` (spawners, step, render, diagnostics) on the `ParticleCtx` interface                                                                        |
| `src/sim/__tests__/`                   | Vitest suite (deterministic, seeded RNG). `npm test` — keep it green when touching sim code                                                                                                                                |
| `src/sim/swarm.ts`                     | CPU SoA pack for huge dumps                                                                                                                                                                                                |
| `src/sim/swarm-gpu.ts`                 | WebGPU collide (linked-list). Draw often falls back to WebGL                                                                                                                                                               |
| `src/sim/particle-gl.ts`               | WebGL points draw                                                                                                                                                                                                          |
| `src/sim/element-registry.ts`          | Element defs                                                                                                                                                                                                               |
| `src/sim/live-pack.ts`                 | Compact Int16 snapshots for P2P                                                                                                                                                                                            |
| `src/lib/multiplayer/p2p.ts`           | WebRTC room                                                                                                                                                                                                                |
| `src/components/lab/lab-app.tsx`       | Shell, mode switch, split, menus                                                                                                                                                                                           |
| `src/components/lab/powder-view.tsx`   | Powder canvas + brushes                                                                                                                                                                                                    |
| `src/components/lab/particle-view.tsx` | Particle canvas + presets                                                                                                                                                                                                  |
| `src/components/lab/glass-sheet.tsx`   | Draggable iOS glass sheets. Must scroll. Title at top. Safe area                                                                                                                                                           |
| `src/components/lab/perf-hud.tsx`      | FPS / graphs. Must not sit _in_ the sim. Must fit under Dynamic Island                                                                                                                                                     |

## Known bugs (user-reported) — status after the full-code-read audit

Full root-cause write-up: [docs/DEBUG-AUDIT.md](docs/DEBUG-AUDIT.md). Status as
of the debug session on the clean, devendored tree:

1. **Water looks glittery / glitchy** — _FIXED (tested)._ Cause: the
   `colorVariation` jitter in `src/sim/powder/render.ts` is keyed to the live
   grid `(x, y)`, so a flowing liquid cell re-samples the noise every tick and
   shimmers (and `organic_flow` adds a `frameCount` term that pulses even still
   cells). Fix: only apply position-hash jitter to solid-grain states
   (`solid_movable` / `solid_fixed`); liquids/gases/plasma/energy render flat
   (gases/plasma still get their alpha blend). Locked in by the vitest suite
   "render texture invariants (bug 1: no liquid glitter)" — liquids render one
   flat color regardless of position/frame, sand keeps its speckle.
2. **Lava vs water never finishes** — _FIXED (tested)._ Cause: `quenchLava`
   flashes touched water straight to rising steam while lava only loses 55-80°C
   per contact and must fall below 700°C to vitrify, so thin water boils away
   before the lava cools; condensing steam rains back and re-quenches → an
   infinite sputter. Fix: pull heat per contact proportional to the lava/water
   gap in `quenchLava`, and raise the residual-steam and obsidian-crust
   heat-bleed coefficients so a skinned-over blob keeps shedding heat. See
   `src/sim/powder/phase-change.ts` + `reactions.ts`. Locked in by the vitest
   test "hot lava surrounded by enough water resolves to obsidian within a tick
   budget" (≤400 steps); the pre-existing threshold test stays green unchanged.
3. **1,000,000 particles ~10 FPS** — _NOT A BUG (real compute cost)._ With
   WebGPU it's on the GPU; without it (likely on the phone) the CPU fallback in
   `src/sim/swarm.ts` rebuilds a 1M spatial hash and runs collide twice per
   step. Levers: drop the 2nd CPU collide pass above ~500k, confirm WebGPU vs CPU
   in the Perf sheet, scale the default dump to sustain ~30 FPS.
4. **Black canvas after dump** — _FIXED (verified)._ GPU canvas is forced
   `opacity 0` every frame; WebGL (`particle-gl.ts`) is the visible layer and
   draws opaque points, so it can't be covered or hidden by alpha-0 colors.
   (Note: the WebGPU **present** path in `swarm-gpu.ts` is therefore dormant —
   WebGPU is used for compute only, WebGL for drawing.)
5. **Perf menu clipped** — _FIXED (verified)._ `glass-sheet.tsx` is
   `max-h-[min(70dvh,calc(100svh-6rem))]`, title pinned, body scrollable, safe-
   area padding. (Bump 70→72dvh if you want to match this note exactly.)
6. **Name covered by chrome** — _FIXED (verified)._ Header uses
   `pt-[max(0.4rem,env(safe-area-inset-top))]`; "Crucible" renders below the
   safe area.
7. **Live room** — _WORKING._ Host broadcasts the powder grid (`serializeLite`)
   and a swarm sample; `psnap` and `px` use the same `cap` so sample sizes match
   and the guest rebuilds to that size. Minor: `applyPos` could resize on
   size-mismatch to self-heal a frame faster (low priority).

## Codebase health (this session)

- ~18.5K LOC you own (17,938 lines TS/TSX/CSS across 95 files; 127 tracked files).
- Zero `any` / `@ts-ignore` / `eslint-disable` / `TODO` / `FIXME` in `src/**`.
- Zero `grok` / `app-builder` vendor traces. One vendor-flavored identifier
  remains: `isRemintPreviewPair` in `src/lib/preview-embedder-origin.ts` — a
  latent preview-bridge trust-widening (inert while unframed / auth off); gate it
  behind `VITE_PREVIEW_EMBEDDER_ORIGINS` or delete it, and rename.
- `npm run lint` / `typecheck` / `test` (93 node + 46 vitest) / `build` all green.

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
