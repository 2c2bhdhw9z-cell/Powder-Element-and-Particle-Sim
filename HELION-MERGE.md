# Merging Helion into the particle field

The owner wants features from **`2c2bhdhw9z-cell/Built-Helion`** brought into this project's
particle chamber. This file is the working record of that job. It exists because Helion is far too
large to hold in one head at once, so nothing about it should live in one — read this first, add to
it as you learn, and never rely on remembering.

Cloned at `/projects/sandbox/Built-Helion`. **Nothing in it has been read yet beyond its two
documents.** The tables below are from `HELION-PLAN.md` and `README.md`, not from the code.

---

## What Helion is

A WebGPU/WebGL2 particle sandbox in the browser — React, Vite, TypeScript. Same author, same house
style as this project (there is a `HELION-PLAN.md` written the way `PORT-STATUS.md` is, and an
honest STATUS key with `SKIPPED` rows).

**49,283 lines across 1,052 files.** Where it lives:

| lines | files | directory | what it is |
| --- | --- | --- | --- |
| 23,425 | 181 | `src/lib/` | platform layer, auth, API, AI, storage, teams, telemetry |
| 10,572 | 44 | `src/components/` | the interface |
| **10,360** | **39** | **`src/engine/`** | **the simulation — the part that matters here** |
| 2,138 | 15 | `src/routes/` | pages and API routes |
| 1,062 | 2 | `src/store/` | state |

Also `noise.wgsl` at the root — a WebGPU compute shader.

**So the read is roughly 10,000 lines, not 49,000.** The engine is the target; most of the rest is
a web SaaS wrapper that has no meaning in a native app.

---

## First pass at what is worth taking

From Helion's own feature list. **Not confirmed against its code**, and the owner has their own
list which takes precedence over this one — this is a starting point so they can point at things
rather than describe them from scratch.

### Fits the native field directly

These are physics and appearance. This is the bulk of the value.

| Helion feature | Where this project stands |
| --- | --- |
| Camera: zoom, pan, orbit with pitch, fill-frame, auto-orbit | **Nothing.** The field is a fixed view. Probably the single biggest gain. |
| 10+ generators: Fire, Smoke, Fireworks, Water, Tornado, Lightning, Black Hole, Supernova, Fibonacci, Sierpinski | ~20 spawners exist; these are additions, not replacements |
| More generators: Crystal snowflakes, Magma, Aurora, Helix DNA, Mandala 8-fold, Molecule ball-and-stick, Confetti | none of these |
| Particle shapes: squares, triangles, sprites, emoji (WebGL SDF + WebGPU quads) | points only |
| Colour: gradients by lifetime / velocity / position, From–To stops, colour maps | 6 fixed colour modes |
| Backgrounds: starfield, gradient, nebula, image, video | plain black |
| Trails: history buffer + velocity streaks, length drives persistence | trails exist via an accumulation texture |
| SPH fluid: pressure, viscosity, cohesion, surface tension, XSPH, packed-pool spawn | a single `fluidEnabled` toggle |
| N-body: pairwise to 1,600 then a 32×24 mass grid with near-field cap; GPU 5×5 neighbourhood | an `nbodyEnabled` toggle, pairwise |
| Molecules: ball-and-stick with real bonds | springs exist (cloth, rope) |
| Custom forces: radial / swirl / sine / arbitrary expression | fixed tool set |
| Audio-reactive: mic or a music file, bass and mids | nothing |
| Image-to-particles | nothing |
| Data import: CSV, OBJ vertices, XYZ | nothing |
| Performance modes tied to real pixel density | a detail setting exists for powder, not the field |
| 1M particles | 1M cap exists — and see `SwarmCost`: collisions are what make it unaffordable, not the count |

### Would need a native equivalent rather than a port

| Helion | This project |
| --- | --- |
| PNG/JPG export, 4K stills, alpha transparency | PNG export exists; 4K and alpha do not |
| GIF recording, canvas video recording, custom FPS | ReplayKit records the screen with sound |
| Preset save/load, URL sharing, embed | scenes, saves, autosave, share sheet |
| Undo/redo, fullscreen, theme | undo/redo exist; the rest is not how a phone works |

### Does not apply, or is a separate decision

Listed so nobody spends time on them by accident. Roughly **two thirds of Helion's file count.**

- **Billing** — tiers, Stripe (already parked in Helion), premium gates, watermarks.
- **Accounts as a product** — admin dashboard, audit view, suspend/reinstate, email allowlists.
- **Social** — global leaderboards, server achievements, XP, badges, daily challenges, likes,
  curation, community library, profiles.
- **Teams and collaboration** — workspaces, roles, permissions, session chat, real-time multiplayer.
  This project already has its own room (phone-to-phone, MultipeerConnectivity) built on different
  foundations; see `ONLINE-PLAN.md`.
- **Developer surface** — REST API, WebSocket control channel, JavaScript and Python SDKs, webhooks,
  rate limiting.
- **Analytics** — usage analytics, opt-in telemetry, feedback board.
- **AI** — preset generation, style transfer, parameter tuning, text-to-particles, image-to-particles.
  Several of these are genuinely good, but they call a hosted model (`grok-4.5`). That is a server,
  a key and a running cost, so it is a decision to be taken rather than code to be moved.
  *Image-to-particles may be the exception: worth checking whether it needs the model at all.*
- **Deployment** — Docker, self-hosting, on-prem.

---

## How to do the read without losing it

The mistake to avoid is reading files one at a time into this conversation. Forty-nine thousand
lines will not fit, and a summarisation part-way through means starting again — which is exactly
what the owner is trying to avoid.

**Use sub-agents.** Each gets its own fresh context, reads a slice of Helion, and returns a focused
account of it. Then write that account into this file **immediately**, before doing anything else.
Repeat. The conversation never has to hold more than one slice, and the file accumulates everything.

A reasonable division of `src/engine/` (39 files, ~10,000 lines):

1. The core loop and particle storage — how particles are held, stepped, and what the data layout is.
2. Generators / spawners — every one, with what shape it makes.
3. Forces — SPH, n-body, flow fields, custom expressions.
4. Rendering — WebGL2 / WebGPU paths, sprites, shapes, trails, backgrounds.
5. Camera and projection.
6. Anything else in `src/engine/` the first five do not cover.

Then, and only if wanted, a pass over the specific `src/lib/` pieces behind a chosen feature
(audio, image import, data import).

### What each slice's notes must capture

Enough to port from, without going back:

- **The maths**, written out. Not "it does SPH" but the actual kernel, the coefficients, the order
  of the passes.
- **Magic numbers**, and where they came from if the code says.
- **What it depends on** — WebGPU compute, a browser API, floating-point texture support.
- **Whether it can be native at all.** Metal can do anything WebGPU can; the browser-only parts
  (video backgrounds, the Web Audio graph, `File` inputs) need an iOS equivalent naming.
- **The honest limits** Helion's own plan admits to, which are unusually well documented — for
  instance n-body is a mass grid rather than Barnes-Hut, and the molecule generator is bonds rather
  than chemistry. Do not port a claim.

---

## Standing constraints this merge must respect

From `PORT-STATUS.md`, and they are not negotiable without asking:

- **`CrucibleCore` imports nothing.** Not Metal, not SwiftUI, not Foundation, not the C maths
  library. Physics goes in the engine; drawing goes in Metal; anything touching a file, a
  microphone or the network goes in the app layer. Helion's own `src/lib/platform` split is the
  same idea and should make the seam easy to find.
- **No dynamic frameworks, no entitlements.** The `.ipa` ships unsigned and is signed on the device.
  Anything needing a third-party framework is off the table unless the delivery method changes.
- **`web/` is reference material only and must not be edited.** It is going to be deleted.
- **The app layer has no test coverage and CI only proves it compiles.** Every interface fault this
  project has had was found by the owner looking at it. Anything ported into the field wants its
  logic in `CrucibleCore` where it can be tested.
- **Measure before offering.** The field had no benchmark at all until collisions turned out to cost
  250× everything else. Anything added here goes in `crucible-bench`.
