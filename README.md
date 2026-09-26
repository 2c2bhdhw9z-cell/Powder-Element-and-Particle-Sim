# Crucible

Particle field + powder world. Switch anytime.

A dual-chamber simulation lab: a cellular-automata **powder world** (50 elements —
sand, water, lava, acid, electricity, recipes, explosions) and a 1,000,000-capacity
**particle field** (swarms, black holes, cloth, flocking, springs), sharing one
canvas and one undo history. The particle field also runs in 3D: a box of bodies
with the physics working in depth, a finger that reaches through it, and a view
that goes round it.

## Repository map

This repo holds two implementations of the same simulation. They are kept
deliberately separate.

| Area                     | What it is                                                                                                                                                       | Status                       |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| [`native/`](native/)     | **The shipping app.** 100% native iOS — Swift + Metal + SwiftUI. No WebKit, no HTML, no JavaScript. Compiles to an `.ipa`.                                        | In development               |
| [`web/`](web/README.md)  | **Reference implementation.** The original TanStack/React/Canvas web app, kept working and fully tested. Not shipped — it is the spec the native port is checked against. | Complete, green, frozen-ish  |

### Why the web version stays

Two reasons, and the second one outlives the first.

**It is the specification.** Nobody ever wrote down how this simulation behaves —
how sand piles, when lava crusts over, how an orbit decays. That behaviour only
exists as the accumulated result of a long series of small tuning decisions, and
the only way to carry it across to Swift intact is to run the same world in both
implementations and compare every cell and every body. Two golden fixtures do
exactly that: 38 powder scenarios and 39 particle scenarios, matched exactly,
down to the number of random numbers each engine consumes.

**It is also the server.** The deployed web app is a TanStack Start application
with Postgres, authentication and server routes — which is precisely the backend
the native app will need for accounts, cloud saves and the workshop. The browser
front end is scaffolding and will go; the server behind it is not.

## Deployment

The repository root holds no `package.json`, because the web app lives in
[`web/`](web/). [`vercel.json`](vercel.json) bridges that: it installs and builds
inside `web/`, then moves the generated `.vercel/output` up to the repository
root, which is where Vercel looks for it.

That file exists so the Vercel project needs no dashboard configuration. If you
would rather set the project's **Root Directory** to `web` in the Vercel
dashboard, that is the more conventional arrangement — delete `vercel.json` at
the same time, or the two will fight over the output location.

## Installing it

Every push to `main` builds an unsigned `.ipa` and attaches it to a release.

**[Latest build →](https://github.com/2c2bhdhw9z-cell/Powder-Element-and-Particle-Sim/releases/latest)**

Download `Crucible.ipa` from there on the device, sign it with your own
certificate, and install. The link is permanent and each build gets its own, so an
older one keeps working.

It is deliberately unsigned, and the app deliberately has no entitlements, no app
extensions and no dynamic frameworks — each of those needs a provisioning profile
that matches it, and each is a way for signing on the device to fail.

## Build it yourself

The simulation engine builds and tests anywhere, with no Apple hardware:

```bash
cd native
swift test              # 936 tests, Linux or macOS
swift test -c release   # the optimiser is allowed to change floating-point results
```

The iOS app needs a Mac, or the CI that stands in for one:

```bash
cd native
brew install xcodegen
xcodegen generate       # the .xcodeproj is generated, not committed
open Crucible.xcodeproj
```

Two workflows do this on every push:

| Workflow | What it proves |
| -------- | -------------- |
| [Engine](.github/workflows/engine.yml) | The simulation behaves identically on Linux and on macOS, in debug and optimised builds. Also prints the benchmark, so performance claims come from measurement. |
| [iOS app](.github/workflows/ipa.yml) | The app compiles, and produces an installable `.ipa`. |

Running the engine suite on two operating systems is not redundancy. The engine
carries [its own trigonometry](native/Sources/CrucibleCore/Support/FDLibm.swift)
so that every device computes identical results, and this is the check that the
claim holds on the platform the app actually ships to.

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
