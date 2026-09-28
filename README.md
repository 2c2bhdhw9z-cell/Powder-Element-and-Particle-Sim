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
implementations and compare every cell and every body. Recorded fixtures cover
38 powder scenarios and 39 particle scenarios. Most match exactly; cases where
the old reference itself was wrong were replaced with tests of what the behaviour
should be. Both kinds also check how many random numbers the engine consumes.

**It is also the server.** The deployed web app is a TanStack Start application
with Postgres, authentication and server routes — which is precisely the backend
the native app will need for accounts, cloud saves and the workshop. The browser
front end is scaffolding and will go; the server behind it is not. There will be no
web or browser version of the app itself.

## Deployment

The repository root holds no `package.json`, because the web app lives in
[`web/`](web/). [`vercel.json`](vercel.json) bridges that: it installs and builds
inside `web/`, then moves the generated `.vercel/output` up to the repository
root, which is where Vercel looks for it.

That file exists so the Vercel project needs no dashboard configuration. If you
would rather set the project's **Root Directory** to `web` in the Vercel
dashboard, that is the more conventional arrangement — delete `vercel.json` at
the same time, or the two will fight over the output location.

One Vercel dashboard setting still matters: **Production Branch** must be the same
as GitHub's current default branch. It is not at the moment, so new commits are
building as previews while the public server remains on an older version.

## Installing it

Every push to the project's main line (whatever GitHub shows as the default branch) builds an unsigned `.ipa`
and attaches it to a release.

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
swift test              # 1,288 tests in 100 suites, Linux or macOS
swift test -c release   # the optimiser is allowed to change floating-point results
```

The iOS app needs a Mac, or the CI that stands in for one:

```bash
cd native
brew install xcodegen
xcodegen generate       # the .xcodeproj is generated, not committed
open Crucible.xcodeproj
```

The checks:

| Workflow | What it proves |
| -------- | -------------- |
| [Engine](.github/workflows/engine.yml) | The simulation behaves identically on Linux and on macOS, in debug and optimised builds. Also prints the benchmark, so performance claims come from measurement. |
| [iOS app](.github/workflows/ipa.yml) | The app compiles, and produces an installable `.ipa`. |
| [App tour](.github/workflows/tour.yml) | The app opens on a simulated iPhone and iPad and is used; fails on a crash, a hang or a blank world. |
| [Server](.github/workflows/server.yml) | Every request the app makes, replayed against the real server code and tables. |
| [Long runs](.github/workflows/long-runs.yml) | Every scene left running for thousands of moments, checking nothing impossible happens. |
| [Quick check](.github/workflows/quick.yml) | Started by hand: one system, unoptimised, optionally one test — a few minutes instead of ten. |
| [The world of the day](.github/workflows/daily.yml) | Draws the day's shared world every day with no phone involved and publishes it as a release. |

Running the engine suite on two operating systems is not redundancy. The engine
carries [its own trigonometry](native/Sources/CrucibleCore/Support/FDLibm.swift)
so that every device computes identical results, and this is the check that the
claim holds on the platform the app actually ships to.

## Run the web reference

```bash
cd web
npm install
npm run dev             # vite, 0.0.0.0:8080
npm test                # the oracle suite: 93 script tests, then 151 engine tests
```

## Design intent

- **Target device:** iPhone 17 Pro Max. Mobile-first, iOS glass look.
- **Performance:** the web reference targets ~30 FPS and is capped by a
  single JavaScript thread. The native app targets the display's full refresh
  rate. Its deterministic physics stays on one CPU core; Metal uses the GPU to
  draw both chambers without copying the finished picture back through the CPU.
- **Architecture principle (carried over from the web version):** the engine
  owns only state and orchestration; each physics subsystem is a plain module
  operating on a context interface. The simulation core has no UI dependency at
  all, so it is unit-testable in isolation on any platform.

Further reading: [CRUCIBLE.md](CRUCIBLE.md) (the pitch),
[METHOD.md](METHOD.md) (how it was built and checked),
[PORT-STATUS.md](PORT-STATUS.md) (what is done and how it was verified),
[docs/IF-THIS-STOPS.md](docs/IF-THIS-STOPS.md) (where everything lives),
[docs/lab-ideas.md](docs/lab-ideas.md) (shipped / unshipped features),
[web/DEBUG.md](web/DEBUG.md) (deep-dive brief on the reference implementation).
