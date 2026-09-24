# Crucible

Particle field + powder world. Switch anytime.

A dual-chamber simulation lab: a cellular-automata **powder world** (50 elements —
sand, water, lava, acid, electricity, recipes, explosions) and a 1,000,000-capacity
**particle field** (swarms, black holes, cloth, flocking, springs), sharing one
canvas and one undo history.

## Repository map

This repo holds two implementations of the same simulation. They are kept
deliberately separate.

| Area                     | What it is                                                                                                                                                       | Status                       |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| [`native/`](native/)     | **The shipping app.** 100% native iOS — Swift + Metal + SwiftUI. No WebKit, no HTML, no JavaScript. Compiles to an `.ipa`.                                        | In development               |
| [`web/`](web/README.md)  | **Reference implementation.** The original TanStack/React/Canvas web app, kept working and fully tested. Not shipped — it is the spec the native port is checked against. | Complete, green, frozen-ish  |

### Why the web version stays

Its test suite (93 tooling tests + 47 simulation tests, deterministic via a
seeded random generator) encodes the real behavior of the sim: gravity,
buoyancy, decay, lava quenching, undo/redo, serialization. Those tests are
translated into the native test suite and act as the behavioral oracle. When the
native engine and the web tests disagree, the native engine is wrong.

## Build the native app

The native app targets iPhone and is built entirely in CI — no Mac required
locally. See [`native/README.md`](native/README.md) for the full pipeline.

```bash
cd native
swift test              # simulation core: runs on Linux and macOS, no Apple hardware needed
```

The iOS app itself (Metal renderer + SwiftUI shell) is compiled by the
[GitHub Actions workflow](.github/workflows), which produces an unsigned `.ipa`
attached to a release for on-device signing.

## Run the web reference

```bash
cd web
npm install
npm run dev             # vite, 0.0.0.0:8080
npm test                # the oracle suite
```

## Design intent

- **Target device:** iPhone 17 Pro Max. Mobile-first, iOS glass look.
- **Performance:** the web version targets ~30 FPS and is capped by a
  single JavaScript thread. The native version targets the display's full
  refresh rate, using multiple CPU cores for the powder grid and the GPU via
  Metal for the particle field.
- **Architecture principle (carried over from the web version):** the engine
  owns only state and orchestration; each physics subsystem is a plain module
  operating on a context interface. The simulation core has no UI dependency at
  all, so it is unit-testable in isolation on any platform.

Further reading: [CRUCIBLE.md](CRUCIBLE.md) (the pitch),
[docs/lab-ideas.md](docs/lab-ideas.md) (shipped / unshipped features),
[web/DEBUG.md](web/DEBUG.md) (deep-dive brief on the reference implementation).
