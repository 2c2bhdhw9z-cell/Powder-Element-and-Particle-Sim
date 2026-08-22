# Crucible

Particle field + powder world. Switch anytime.

A dual-chamber simulation lab: a cellular-automata **powder world** (sand, water,
lava, acid, electricity, recipes, explosions) and a 1,000,000-cap **particle
field** (swarms, black holes, cloth, flocking, springs), sharing one canvas,
one undo history, and P2P multiplayer.

## Run

```bash
npm install
npm run dev          # vite, 0.0.0.0:8080 (live-preview contract — don't change)
```

Other scripts:

```bash
npm run typecheck    # tsc --noEmit
npm run lint         # eslint .
npm test             # node --test (scripts) + vitest (simulation core)
npm run build        # vite build + db:migrate (skips DB when DATABASE_URL unset)
```

## Environment

| Var | Meaning |
|---|---|
| `DATABASE_URL` | Real Postgres (Neon). Unset → embedded PGLite fallback (preview/local). |
| `GEMINI_API_KEY` | Gemini AI API (injected at runtime). |
| `APP_URL` | Public app URL (injected at runtime). |
| `GROK_AUTH_*`, `BETTER_AUTH_URL`, `BETTER_AUTH_SECRET` | Federated auth (deploy-injected). |
| `DEBUG=1` / `?debug` | Enables gated `debug.warn`/`debug.log` output (see `src/lib/debug.ts`). |

## Architecture

```
src/
  sim/                    # Simulation core (no UI, fully unit-tested)
    powder-engine.ts      # PowderEngine facade: grid state + tick orchestration
    particle-engine.ts    # ParticleEngine facade: particle state + tick orchestration
    powder/               # Powder physics modules (PowderCtx structural interface)
      phase-change.ts     #   boil / freeze / melt / condense, lava quench
      electricity.ts      #   lightning: seek wet → ride conductors → burn
      reactions.ts        #   chemical reactions & special element behavior
      explosion.ts        #   shockwave / shatter / embers / smoke plume
      movement.ts         #   gravity, buoyancy, viscosity, momentum
      thermals.ts         #   heat diffusion, heat pipes, wind, pressure
      brush.ts            #   painting tools, flood fill, bulk spawn, jostle
      history.ts          #   typed-array undo/redo snapshots
      render.ts           #   canvas renderer + overlay modes
      diagnostics.ts      #   health inspection & repair actions
    particle/             # Particle physics modules (ParticleCtx interface)
      spawners.ts         #   scene presets (galaxy, black hole, cloth, …)
      step.ts             #   forces, integration, boundaries, flock, springs
      render.ts           #   pixel-buffer / vector renderers
      diagnostics.ts      #   health inspection & repair actions
    swarm.ts / swarm-gpu.ts   # SoA swarm + WebGPU collide (CPU fallback)
    particle-gl.ts        # WebGL point renderer
    element-registry.ts   # Element definitions + custom elements
    scene.ts, autosave.ts # Scene export/import, autosave
    multiplayer/          # P2P rooms over WebRTC + /api/rtc signaling
    live-pack.ts          # Binary packing for live multiplayer sync
  components/lab/         # iOS glass UI: chambers, tools, modals, overlays
  lib/
    auth/                 # Self-hosted Better Auth (tri-mode: deploy/preview/off)
    db.ts                 # Neon (pg) or PGLite, with migrations
    multiplayer/          # P2P client + signaling server
    debug.ts              # Gated logger (errors always, warns gated)
  routes/                 # TanStack Start routes (index = lab, /login, /api/*)
server/middleware/        # Nitro middleware (PWA install page, OG identity)
scripts/                  # Build tooling: PWA plugin, migrations, smoke tests
migrations/               # SQL (0001_auth, 0002_lab)
```

The engine facades only own state and orchestration; each physics subsystem is
a plain module operating on a structural context interface (`PowderCtx`,
`ParticleCtx`), so every subsystem is testable in isolation and the sim core
runs in plain Node.

## Testing

- `npm test` runs both suites:
  - `node --test scripts/**` — build/PWA tooling
  - `vitest run src/**` — simulation core (powder, particle, registry)
- The sim tests are deterministic: they seed `Math.random` (`src/sim/__tests__/helpers.ts`).
- The engines must keep passing them — they encode real behavior (gravity,
  buoyancy, decay, quenching, undo/redo, serialization, multiplayer snapshots).

See [docs/lab-ideas.md](docs/lab-ideas.md) for the shipped/unshipped feature
list and [DEBUG.md](DEBUG.md) for the deep-dive brief.
