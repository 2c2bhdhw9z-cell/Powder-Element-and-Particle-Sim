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

---
---

# THE READ

Below is what is actually in Helion's code, slice by slice. Each section was written the moment it
was read. **This, not the tables above, is what to port from.** Where the two disagree, believe this.

---

## Slice A — camera, palettes, colour modes, audio, timeline

Files: `src/engine/camera.ts` (129), `palettes.ts` (173), `palette-stops.ts` (154), `audio.ts` (129),
`audio-modulation.ts` (129), `timeline.ts` (254), driven from `src/components/lab/canvas-stage.tsx`.

### A1. Camera — a perspective orbit of a flat plane

**There is no camera object.** `camera.ts` is stateless maths; the state is five scalars and two
flags in the web store:

| field | meaning | default | clamp |
| --- | --- | --- | --- |
| `viewZoom` | zoom | 1 | `[0.4, 8]` |
| `viewPanX`, `viewPanY` | pan, **in screen pixels, not world units** | 0, 0 | none — unbounded |
| `viewRotate` | **yaw**, degrees | 0 | `[-180, 180]` |
| `viewPitch` | pitch, degrees | 0 | `[0, 72]` |
| `fillFrame` | zoom-out grows the world instead of shrinking the picture | false | — |
| `viewOrbit` | auto-orbit | false | — |

Constants: `ORBIT_CAM = 2.4` (camera distance in normalised units). Reset clears zoom/pan/yaw/pitch
but deliberately **not** `fillFrame`.

**The projection.** Not a 4×4 matrix and not a CSS spin — a hand-rolled yaw-then-pitch rotation of
the z = 0 plane, then a perspective divide, per particle:

```
w = max(worldW, 1e-6); h = max(worldH, 1e-6)
px = (x / w) * 2 - 1              // normalised x
py = 1 - (y / h) * 2              // normalised y, flips y-down to y-up
if |yaw| < 1e-8 && |pitch| < 1e-8 -> return (px, py, scale: 1)    // exact identity early-out
x1 = px * cos(yaw)
z1 = -px * sin(yaw)               // only x feeds z, because input z is 0
y2 = py * cos(pitch) - z1 * sin(pitch)
z2 = py * sin(pitch) + z1 * cos(pitch)
zCam  = 2.4 - z2
persp = 2.4 / max(zCam, 0.2)      // near-plane guard 0.2, so persp <= 12
return (nx: x1 * persp, ny: y2 * persp, scale: persp)
```

`scale` is the per-particle depth factor — bigger when nearer. At the plane centre it is exactly 1
for any angle. Screen: `sx = (nx + 1) * 0.5 * width`, `sy = (1 - ny) * 0.5 * height`, `size *= scale`.

**A real divergence between their own two backends:** the GPU path clamps the size multiplier to
`[0.35, 2.8]`, the CPU path does not. Port the clamped one.

**No depth buffer, no depth sort.** `gl_Position.z` is hard 0. Occlusion is left to the blend mode.
The CPU path also decimates: at more than 12,000 particles it draws every *n*th one.

**The inverse** (`unprojectOrbit`, for hit-testing) round-trips to 1e-9 at identity but only ~1e-5
when tilted — one term (`x1 = x2`) drops a yaw cross-term. Fine for placing a brush, not exact.

**Zoom is two different products on one slider:**
- `fillFrame` off → world stays 1×, the whole canvas is scaled by CSS. Zooming out shrinks the
  picture inside the viewport (letterbox).
- `fillFrame` on **and zoomed out** → picture scale pinned to 1 and the **world grows by 1/zoom**,
  so the freed screen becomes real simulation space.
- Zoomed in is always a magnify/crop.

Their world is normalised: **height = 1 (× worldScale), width = aspect ratio.** Brush radius is
multiplied by worldScale before reaching the engine.

**Auto-orbit:** yaw only, **18°/s**, wrapped into `[-180, 180)`, driven off frame delta clamped to
100ms. Pitch is never animated. It overwrites the manual yaw slider every frame — those two fight.

**Gestures:** scroll wheel = multiplicative `×0.9` / `×1.11` per notch regardless of magnitude.
Pinch = ratio of current to starting finger distance × starting zoom; a second finger cancels
painting. **There is no two-finger pan and no touch gesture for orbit or pitch at all** — pan needs a
middle-click, right-click or Alt-drag, and yaw/pitch are slider-only. That is the biggest gap for a
touch-first port: on a phone the gestures have to be invented, not ported.

**No smoothing, no easing, no inertia, no pan bounds.** Every gesture writes the final value
straight in. Pan can push the world off-screen with no way back except reset.

Also here: `trailFadeAlpha(decay, length) = clamp(decay / max(0.12, length), 0.03, 0.55)` — longer
trails give a smaller per-frame fade alpha. Heuristic, not physical; fade colour hardcoded `#08090c`.

### A2. Palettes

Seven built-ins, RGB 0–255, evenly spaced stops:

- **rainbow** (7): 220,32,64 · 255,128,24 · 255,214,48 · 46,196,92 · 36,156,255 · 92,72,255 · 188,56,210
- **ember** (6): 8,4,6 · 92,14,8 · 188,42,10 · 255,118,24 · 255,198,86 · 255,246,220
- **ice** (5): 4,10,22 · 12,48,92 · 24,128,186 · 120,210,255 · 236,248,255
- **aurora** (5): 4,18,16 · 12,78,68 · 36,168,132 · 140,232,188 · 230,255,242
- **solar** (5): 18,8,2 · 160,62,8 · 240,148,28 · 255,214,110 · 255,248,226
- **mono** (4): 12,13,16 · 90,94,104 · 188,192,200 · 244,246,248
- **plasma** (5): 6,8,28 · 20,64,168 · 48,168,210 · 255,170,70 · 255,244,220

Sampling: `u = clamp01(t) * (n-1)`, `i = min(n-2, floor(u))`, `f = u - i`, linear per channel.
**Plain linear blending in non-linear sRGB** — no gamma correction, no HSL, no OkLab. Reproduce
exactly or the colours drift. Baked to a **256×1 RGBA8 lookup texture** (1024 bytes) for the GPU.
`tint` is a multiplicative per-channel post-multiply; an invalid hex means white (no tint).

Priority: N-stop custom palette → two-stop A/B → named built-in.

### A3. Colour modes — the exact expressions

`ColorMap = life | speed | density | mass | palette | position`, default `palette`:

```
palette  -> per-particle stored phase (0..1)
speed    -> min(1, hypot(vx, vy) / 2.4)
life     -> life < 0 ? 1 : life / max(maxLife, 1e-4)      // life < 0 means immortal
density  -> min(1, density / 40)
mass     -> min(1, mass / 3)
position -> min(1, dist(pos, worldCentre) / max(0.5 * min(worldW, worldH), 1e-4))
```

Alpha `= (life < 0 ? 1 : min(1, life)) * energy`, where
`energy = additive ? 0.55 / (1 + pointSize² × 0.02) : 0.9`. **No depth colour mode.**

### A4. Custom gradient stops

`{ pos: 0..1, color: "#rrggbb" }`. Normalising drops bad hex/positions, clamps, lowercases, sorts
ascending, stable on ties. Sampling **holds at both ends — no extrapolation**; fewer than 2 stops is
not a gradient. Bakes the same 256-entry lookup.

`quantizeColors(pixels, count, bits = 4)` is a self-contained image→palette extractor: bucket by the
top `bits` of each channel (default 4 bits = 16 levels), skip fully transparent pixels, sort buckets
by population, return the top `count` bucket **averages**. `colorsToStops` then spaces them evenly.
**This is the whole of "image to particles" colour-wise and it needs no server and no model.**

### A5. Audio

Capture is Web Audio and must be rebuilt on AVAudioEngine, but it is small: FFT size **256** (128
bins), smoothing **0.7**, then

```
bass   = sum(bins 0..9)   / (10  * 255)
mid    = sum(bins 10..39) / (30  * 255)
energy = sum(all 128)     / (128 * 255)
```

At 48kHz that is bass ≈ 0–1875Hz, mid ≈ 1875–7500Hz. **There is no treble band** — three signals
only. Bin indices are hardcoded, so the real Hz bands drift with the device sample rate.

Modulation is **pure maths, portable verbatim**. Sources `bass | mid | level`; targets
`size | spawn | force | gravity | palette`; `amount` 0–2 where 0 is off. Defaults: bass→size at 1.0,
level→force at 0.6. With `v = signal × amount × sensitivity`:

```
size    -> pointSize     = clamp(base * (1 + v * 0.9), 1, 48)    // multiplicative
force   -> forceStrength = clamp(base + v * 3, 0, 20)            // additive
gravity -> gravityY      = clamp(base + v * 2, -20, 20)          // additive
spawn   -> spawnBurst   accumulates, clamped 0..1
palette -> palettePulse accumulates, clamped 0..1
```

**No envelope at all** — no attack, decay, peak-hold or beat detection. The only smoothing is the
analyser's 0.7. On a phone this will feel limp; add an envelope.

**Their bug, do not port it:** size/force/gravity all read the *base* parameter, not the running
value, so two mappings onto one target do not stack — the last silently wins.

### A6. Timeline

Keyframes over a fixed animatable set: ten tweened (`gravityX, gravityY, drag, pointSize,
forceStrength, trailLength, flowStrength, bloomStrength, nbodyG, centralMass`) and two step-held
(`palette`, `shape`). Nothing else animates — no camera, no counts, no colours.

`{ t: seconds, params: partial }`, sorted, with `EPS = 1e-4`. Re-recording within EPS of an existing
time replaces it. Sampling holds before the first and after the last key, lerps between, and if only
one side defines a value that side holds. Step keys hold the earlier value across the interval.
**Easing: linear only — there are no curves, and keyframes store no curve field, so adding easing
later is a file-format change.**

Playback: `advanceTimeline` returns a new state; an empty or single-key track parks at 0; looping
uses modulo so overshoot is kept; not looping clamps to the end and auto-stops. While playing, the
engine owns the playhead; while paused, the scrub position wins.

### A7. What this slice costs to port

| item | verdict |
| --- | --- |
| Orbit projection + inverse | **Port verbatim.** ~60 lines of maths, no dependencies. Pure `CrucibleCore`. |
| Zoom / pan / fillFrame algebra | **Port the algebra, invent the gestures.** Theirs are mouse-only. |
| Auto-orbit | Port (18°/s), but fix the fight with the manual slider. |
| Palettes + sampling + LUT bake | **Port verbatim.** Pure. Keep the sRGB-linear blend deliberately. |
| Colour modes | **Port verbatim.** Six one-line expressions. |
| Gradient stops + quantiser | **Port verbatim.** Pure, and it unlocks image-to-particles offline. |
| Audio maths + modulation | **Port the maths, rebuild the capture** on AVAudioEngine. Add an envelope. |
| Timeline | **Port verbatim**, and consider adding an easing field while the format is still ours. |
| Depth sorting | Does not exist there. If wanted here, it is new work. |
| Fit-to-content framing | **Does not exist there.** Their "fill frame" never looks at the particles. New work. |


---

## Slice B — particle storage, the frame loop, the integrator, emission, the whole settings surface

Files: `src/engine/soa.ts` (223), `engine.ts` (1075), `types.ts` (489), `frame-clock.ts` (99),
`hash.ts` (63), `point-size.ts` (35), plus `physics.ts` and `emitters.ts` where the above were not
self-contained.

### B1. Storage — 16 parallel arrays, 62 bytes a particle

`ParticleSoA`, pure struct-of-arrays. `count` is the live total; slots `[0, count)` are alive and
everything above is garbage.

| field | type | meaning |
| --- | --- | --- |
| `posX`, `posY` | f32 | position. **World is normalised: height = 1 × worldScale, width = aspect.** |
| `velX`, `velY` | f32 | velocity, world units per second |
| `prevX`, `prevY` | f32 | position at step start. Comment calls it "Verlet prev" but **the integrator never reads it** — it is only the swept wall test's helper. |
| `accX`, `accY` | f32 | acceleration scratch. Written **only** by SPH; zeroed every step otherwise. |
| `life` | f32 | seconds remaining. **`< 0` = immortal, `== 0` = dead, `> 0` = ageing.** |
| `maxLife` | f32 | life at birth, for normalising. Set once. |
| `mass` | f32 | used by collision impulse, n-body, SPH |
| `density`, `pressure` | f32 | SPH; `density` doubles as a colour metric |
| `phase` | f32 | random 0–1 per particle, visual only |
| `flags` | u32 | `PINNED = 1`, `SLEEP = 2`, `CLOTH = 4` |
| `sleep` | u16 | consecutive-slow-step counter; over 18 means asleep. Freeze brush writes 40. |

62 bytes each ⇒ 4.06MB at the 65,536 default, **62MB at the 1,000,000 limit**.

**Growth:** keep the buffers if the request is smaller but at least half of capacity; otherwise
reallocate, growing by at least **1.5×**, hard-capped at 1,000,000. Callers must re-read capacity
afterwards because it can exceed the request.

**Recycling is swap-with-last, no free list.** `spawnSlot()` bump-allocates and zeroes, then
`writeParticle` fills it. **Trap:** `spawnSlot` leaves `life = 0`, which is the *dead* marker — a slot
must be written in the same step or it is compacted away. `killSwap(i)` copies the last particle over
`i`, so **particle order is not stable and anything holding indices (springs) must be remapped.**

`compactDead(soa, springs)` walks from 0; on a dead particle it swaps the last one in, then **deletes**
springs touching `i` and **retargets** springs referencing the old last index to `i` — in that order,
which the code says matters — and does not advance `i`, so the swapped-in particle is re-tested.

`clear()` resets count **without zeroing** — a deliberate fast clear.

Default capacity 65,536, chosen from reported device memory: ≤2GB → 12,288, ≤4GB → 32,768, else
65,536. Clamped to `[1024, 1000000]`.

### B2. The frame loop

Driven from outside the engine by the browser's animation callback, with **delta time clamped to
100ms at the source**, and tilt already multiplied by the tilt scale before it arrives.

`stepFrame(dt, paused, speed, tiltX, tiltY)`:

1. Audio gate — start the mic if reactive and not already running; update the analyser.
2. Publish `t` and `bass` into the force-expression runtime.
3. Advance the timeline (if playing and not paused) using **real** delta time, not the fixed step.
4. **Fixed-timestep accumulator** (skipped entirely when paused):
   ```
   acc += min(dt, 0.1) * speed
   while acc >= 1/60 and steps < 5 { substep(1/60); acc -= 1/60; steps++ }
   if steps == 5 { acc = 0 }          // drop the backlog
   ```
   At most **5 substeps = 83.3ms of sim time per frame**. A frame whose `dt × speed` is under 1/60
   runs **zero** substeps — physics idles, rendering still happens.
5. Render, wrapped in a catch so a GPU failure cannot kill the simulation.
6. Telemetry.
7. Flush a pending screenshot, deliberately at end-of-frame because the GPU surface is only valid
   right after submit.

`substep(dt)` in order: paint-tool emission along the stroke → wall tool → field tool → emitter
cadence → incremental GPU upload of just the new particles → timeline parameter sampling → audio
modulation → physics.

**Resize does world bookkeeping worth copying:** when the aspect changes and particles exist, a
height change over 0.1% **translates** everything by half the difference; otherwise a width change
over 2% **scales x**. Without that, rotating the device throws the contents off.

### B3. The integrator — semi-implicit Euler with exponential drag

Per step, once: `damp = exp(-drag × dt)`; hash cell size = `sphSmoothing` in fluid mode, else
`max(particleRadius × 4, flockRadius, 0.02)`.

Per particle, forces all accumulate into `ax, ay`:

```
ax = accX + gravityX(or tiltX);  ay = accY + gravityY(or tiltY)
central mass: ax += (centralX*worldW - x) * centralMass      // LINEAR Hooke pull, not 1/r²
custom force, painted field (gain = 8 * forceStrength), brushes, flock, n-body
if (inBrush && sph && forceBrush) { ax *= 0.08; ay *= 0.08 }
ax, ay clamped to ±80                                        // MAX_ACCEL
```

then

```
v' = (v + a*dt) * exp(-drag*dt) + kick
|v'| clamped to 12                       // MAX_SPEED; ×1.85 while an SPH force-brush is engaged
prev = (x, y)                            // written BEFORE the move
x' = x + v'.x * dt                       // uses the NEW velocity, so semi-implicit
```

Drag is a true exponential per-second rate, so it is **timestep-independent** — good, copy that.
Default 0.03 is about 0.05% velocity loss per step.

**Brush coefficients** — falloff `1 - d/radius`, `s = strength × falloff`. Non-fluid writes
acceleration, fluid writes a velocity kick:

| mode | non-fluid | fluid kick |
| --- | --- | --- |
| attract | `a += n*s*24` | `+n*s*2.2` |
| repel | `a -= n*s*26` | `-n*s*2.6` |
| repulsor | `-d * (s*32/(d²+4e-4))` | `s*0.9/(d²+4e-4)` |
| vortex | `a += perp(n)*s*28` | `+perp(n)*s*2.4` |
| freeze | `v = 0`, flag asleep, `sleep = 40` | same |

Two brushes run per particle: the local pointer and a remote one (that is how their multiplayer
lets another person push your particles).

**Collision** (after the move, `j > i` only, one pass): on overlap, push apart by mass ratio, then
if closing, `impulse = -(1 + restitution) * v_normal / (1/mi + 1/mj)`, and wake both.

**Walls** are line segments, brute-force per particle per segment, capped at 256 with the oldest
silently dropped. Close test plus a **swept** test using the cross-product sign change, so fast
particles cannot tunnel.

**Boundaries:** `bounce` clamps onto the face and reflects scaled by restitution; `wrap` is modulo;
`destroy` sets life to 0.

**NaN guard:** any non-finite position or velocity is counted, killed, teleported to centre, zeroed.

**Ageing** is unconditional. There is a long comment about a past bug where this was gated on the
lifespan setting, leaving every burst particle immortal on the CPU while the GPU aged them anyway.

**After the loop:** cloth solve (Gauss–Seidel position-based, `max(1, iterations)` passes,
`correction = delta * ((dist - rest)/dist) * k`, 100% to the free end if one is pinned else 50/50,
**positions only, no velocity correction**), then compact the dead.

### B4. Emission cadence

Continuous emitters carry an accumulator: `acc += rate * dt; n = floor(acc); acc -= n`. So rate is
particles per second of **sim** time and the fraction carries over — that is the right way and it is
worth copying exactly.

The four latched emitters: **pour** (rate 420, speed 0.55, from the top centre), **fall** (280, 0.22,
random x across the top), **fire** (360, 0.72, upward from the bottom centre), **smoke** (180, 0.22,
upward with wider spread 0.6). Life falls back per kind when the lifespan setting is 0 — pour and
fall become **immortal**, fire 1.8s, smoke 4.4s.

`emitContinuous` picks angle `base ± spread`, magnitude `speed × random(0.7, 1.2)`, position jittered
±0.006/±0.004, mass `× random(0.7, 1.3)`.

`emitAlongStroke` steps along the drag at a fixed spacing (0.008 for paint), giving a **speed-
independent** stroke — the same number of particles per unit length however fast you move. Velocity
is a random direction at `speed × random(0.1, 0.6)`.

**Per-generator spawn budgets**, verbatim, because these are tuned and not obvious:
cloth 936 (36×26) · n-body `min(max(2800, cap×0.2), cap)` · black hole `min(1800, cap)` ·
molecule `min(max(1400, cap×0.08), 5000)` · crystal/helix/mandala `min(max(3500, cap×0.1), cap)` ·
burst/fireworks/supernova `min(max(2400, cap×0.12), cap)` · flock/tornado `min(max(1800, cap×0.35), cap)` ·
galaxy/fibonacci `min(max(4500, cap×0.08), 9000)` · ring/sierpinski `min(max(3500, cap×0.06), 7000)` ·
pour/fall/fire/smoke `min(600, cap)` · lightning `min(max(1600, cap×0.08), 5000)` ·
water `min(max(2800, cap×0.12), cap)` · default `min(max(4000, cap×0.12), cap)`.

### B5. The full settings surface (with defaults and the slider ranges)

This is the feature list, stated properly. 26 generator kinds; 12 shapes; 6 colour modes.

`gravityX/Y` 0 (−2…2) · `drag` 0.03 (0…2) · `mass` 1 (0.2…4) · `lifespan` 0 (0…12, **0 means "use
the generator fallback", often immortal**) · `pointSize` 2.8 (1…24) ·
`shape` circle — `circle square ring diamond triangle star hex plus heart spark emoji sprite` ·
`blend` alpha | additive · `palette` rainbow · `colorMap` palette · `lifeFadeIn` 0.08 ·
`lifeFadeOut` 0.22 · `trails` off · `trailDecay` 0.22 (0.02…0.5) · `trailLength` 0.72 (0.1…1.4) ·
`collide` off · `restitution` 0.42 (**shared by particle, wall and boundary bounce**) ·
`particleRadius` 0.0045 (0.001…0.02) · `boundary` bounce | wrap | destroy · `textInput` "HELION" ·
`tiltEnabled` off · `tiltScale` 1.6 (0.2…4) ·
`sph` off · `sphRestDensity` 18 (4…40) · `sphPressure` 4.5 (0.2…14) · `sphViscosity` 0.08 (0…0.4) ·
`sphSmoothing` 0.028 (0.012…0.06, **also the hash cell size in fluid mode**) · `sphCohesion` 0.42 (0…1.2) ·
`settle` off · `settleThreshold` 0.035 ·
`flock` off · `flockSep` 1.4 · `flockAli` 1.0 · `flockCoh` 0.85 · `flockRadius` 0.055 ·
`nbody` off · `nbodyG` 0.018 (0…0.08) · `centralMass` 1.35 (0…8) · `centralX/Y` 0.5 ·
`softening` 0.018 · `clothIterations` 6 (1…16) ·
`flow` off · `flowStrength` 1.5 · `flowScale` 3.0 · `flowSpeed` 0.5 ·
`bloom` off · `bloomStrength` 1.5 · `audioReactive` off · `audioSensitivity` 1.0 ·
`background` void | starfield | gradient | nebula | image | video ·
`tint`/`colorA`/`colorB` white · `emoji` ✨ ·
`forceKind` off · `forceStrength` 1 (0…4) · `forceExprX` `sin(t + y * 6) * 0.4` ·
`forceExprY` `cos(t + x * 6) * 0.4` · `paletteStops` optional.

`flow`, `bloom` and `trails` are **renderer-side only** — the physics never reads them. So their
"flow field" is a shader effect, not a force. Worth knowing before promising it as physics.

Constants: `SYSTEM_LIMIT 1,000,000` · `DEFAULT_CAP 65,536` · `HASH_MAX_PER_CELL 32` ·
`FIXED_DT 1/60` · `MAX_SUBSTEPS 5` · `MAX_ACCEL 80` · `MAX_SPEED 12` ·
quality caps `low 12,288 / medium 32,768 / high 65,536` and pixel-density `0.7 / 1.35 / 2.5`.

### B6. The small pure modules, verbatim

**Spatial hash** — uniform grid, fixed bucket width, no allocation in the hot path. `configure`
early-returns when the shape is unchanged. `clear()` only zeroes the counts; stale ids in the buckets
are harmless because the counts gate every read. Out-of-world coordinates clamp into the edge cells.
`insert` **silently drops** anything past 32 per cell. `query` always scans the 3×3 neighbourhood,
which means **the caller's interaction radius must be ≤ the cell size or the result is wrong.**

**Point size:** `pointSize × pixelDensity × (emoji or sprite ? 1.7 : 1)`, in framebuffer pixels.
Non-finite or non-positive density falls back to 1.

**Frame clock:** EMA with α = 0.1, only accepting frame times in `(0, 1000)`ms;
`fps = 1000/ms`; and a 120-frame ring buffer (about 2 seconds) for the min/max window.

### B7. Honest limits — theirs, admitted or plainly visible

1. **The spatial hash silently drops neighbours past 32 per cell.** Collisions, fluid and flocking
   all under-count in dense clumps. This is the single most load-bearing approximation in the engine.
2. **N-body is dimensionally wrong.** `G·mi·mj/(d²+eps)^1.5` is added straight to *acceleration*
   without dividing by `mi`, so mass is counted twice. It looks fine and is wrong.
3. **Cloth corrects positions only** — no velocity reconciliation, so the constraint quietly injects
   and removes energy.
4. **Collision response is order-dependent** (one pass, `j > i` only, pushout written directly into
   the other particle while this one works on locals). Stacking is approximate and jittery.
5. **The substep cap discards the backlog**, so a slow frame or a high speed multiplier silently
   slows the simulation rather than catching up.
6. **Settle buys no CPU at all** — sleeping particles are still iterated end to end; only their
   velocity is zeroed.
7. **The per-subsystem timing display is a fudge** and says so: every active mode is shown the same
   aggregated total.
8. **`lifeFadeIn` is plumbed to the shader and unused**, and the two backends disagree about fading —
   one normalises by max life, the other uses raw seconds remaining.
9. **Painted force fields force the slow path** (the GPU compute never reads the field) and the field
   is only 16×16 with an empirical gain of `8 × forceStrength` "so the field visibly steers".
10. **Walls cap at 256** with the oldest silently discarded, and are collided brute-force.
11. **Module-level mutable state in the physics file** (stats, the n-body grid) — not reentrant. Two
    simulations or a background thread would corrupt each other. In Swift this must become instance
    state or it will not compile under strict concurrency, which is a free improvement.
12. **No seeded random anywhere** — spawning uses the raw generator, so nothing is reproducible.
    This project already has `Mulberry32` and should use it; that makes scenes repeatable, which
    Helion cannot do.
13. The canvas fallback clamps any spawn to 5,000 and draws at most ~12,000 points.
14. The fluid brush is a stack of magic weakenings (`×0.08` on acceleration, `×1.85` on the speed
    cap, a `×0.022` direct position nudge) whose comment concedes they exist only because fluid
    pressure otherwise clamps the brush away.


---

## Slice C — the forces: fluid, gravity, flocking, springs, painted fields, expressions

Files: `src/engine/physics.ts` (856), `force-field.ts` (163), `force-expr.ts` (285), and all four of
their test files. Cross-checked against `shaders.ts`, which is where the GPU version diverges.

### C1. Fluid (SPH)

**One kernel for everything**, with `h = max(sphSmoothing, 0.005)`:

```
norm = 4 / (π h²)
q    = 1 - r/h        (only where r < h)
W(r) = norm * q²
```

There is **no second kernel** — the same `q` is reused with different invented gains.

**Density pass** (O(n × neighbours)):
```
ρᵢ = mᵢ * norm                                  // self term, q = 1
for each neighbour j with r² < h²:
    ρᵢ += mⱼ * norm * q²
pressureᵢ = max(0, sphPressure * (ρᵢ - sphRestDensity))
```

**Force pass**, with `d = pᵢ - pⱼ` (pointing away from j), `di = max(ρᵢ, 0.1)`:
```
pressure  : f += (d/r) * ((pᵢ + pⱼ) / (2 * dⱼ)) * mⱼ * q² * 18
viscosity : f += (vⱼ - vᵢ) * sphViscosity * mⱼ * (q / dⱼ) * 35
cohesion  : surface = max(0, 1 - dᵢ/restDensity)
            f -= (d/r) * sphCohesion * mⱼ * q * (1 + 1.6 * surface)
"XSPH"    : f += (vⱼ - vᵢ) * 0.12 * mⱼ * q / dⱼ
acceleration = f / dᵢ
```

Every magic number: kernel norm `4/(πh²)`, pressure gain **18**, viscosity gain **35**, surface boost
**1.6**, XSPH **0.12**, density floor **0.1**, h floor **0.005**, r² floor **1e-12**.

**Cell size equals the smoothing radius exactly in fluid mode.** But the cell uses the *raw* setting
while the kernel uses the floored one — so dragging smoothing below 0.005 makes the grid finer than
the kernel and **neighbours are silently missed**. A real bug to not copy.

**The fluid is two full neighbour passes, three with collisions.** With the 3×3 query and 32 per cell,
the hard ceiling is 288 candidates per particle per pass.

### C2. Gravity

**Pairwise below 1,600 particles, a 32×24 = 768-cell mass grid at 1,601 and above.** Confirmed.
`eps = softening²` = 3.24e-4 at defaults; `G = nbodyG` = 0.018.

```
pairwise: d2 = |pⱼ - pᵢ|² + eps
          a += d * (G * mᵢ * mⱼ) / (d2 * sqrt(d2))
```

Grid: accumulate mass and centre-of-mass per cell, then per particle sweep **all 768 cells** taking
the monopole for any cell that is not in the 3×3 neighbourhood *or* holds more than **64** members,
and do exact pairwise for near cells at or under 64.

So about 1,335 evaluations per particle versus 1,600 at the threshold — **the switch barely pays at
the crossover**; it only wins at large counts.

**Central mass is a linear spring, not gravity:** `a += (centre - p) * centralMass`. No softening, no
inverse square. Their galaxy generator derives its orbital speed as `sqrt(max(centralMass, 0.2))`,
consistent with the spring. Under a "gravity" heading in the interface, which is misleading.

### C3. Flocking

```
R = flockRadius; separation radius = 0.45 R
over the 3×3 cells, for neighbours within R:
    count++, sum velocity, sum position
    if within the separation radius: sep -= unit vector toward j     // NOT 1/d weighted
alignment = avgVel - v ; cohesion = avgPos - p
a += sep * flockSep * 6  +  alignment * flockAli * 4  +  cohesion * flockCoh * 8
```

Effective gains at defaults: 8.4 / 4.0 / 6.8. **The GPU version is a different simulation** — it
weights separation by `(radius - dist)` and uses the raw gains with no ×6/×4/×8.

### C4. Collision, walls, boundaries, settle

Collision is a **single Gauss–Seidel pass, `j > i` only, no friction, no rotation, no iteration**.
Positional split by mass ratio, then `impulse = -(1 + restitution) * v_normal / (1/mᵢ + 1/mⱼ)`, and
skip if already separating. **Its own gotcha:** `j > i` particles have not been integrated yet, so
this particle's *new* position is tested against the other's *old* one, while the grid was built from
everyone's old positions.

Walls: project onto the segment, static push-out inside the radius, otherwise a swept test on the
cross-product sign change. Only crossings of the **infinite** line are caught, so **grazing an
endpoint can tunnel**.

Settle: below the threshold for **18 consecutive steps**, velocity is zeroed and a flag set. The flag
never short-circuits anything — a sleeping particle costs exactly as much as an awake one.

### C5. Springs

Position-based dynamics, Gauss–Seidel, `clothIterations` (6) passes, **once per step after the whole
integration loop**:

```
diff = (dist - rest) / dist
corr = delta * diff * springK
pinned a -> pⱼ -= corr ; pinned b -> pᵢ += corr ; neither -> ±corr × 0.5
```

`k` acts as a fraction of the full correction per iteration; `k = 1` with 1 iteration is rigid.
**Velocity is never touched**, so cloth silently gains and loses energy and feels sticky rather than
springy. It also runs *after* walls and boundaries, so constraints can shove particles through a wall
and out of the world until the next step.

Construction: cloth 36×26 at `spacing = min(W,H) × 0.026`, top row pinned, structural `k = 0.55`,
both diagonals at `rest × √2` and `k = 0.3025` — about 3,600 springs. Molecules: benzene ring
`k = 0.62`, C–H at `0.55 × spacing` and `k = 0.5`, water O–H `k = 0.7` with the **104.5° angle used
only for initial placement — nothing maintains it**. Chains `rest = 1.05 × spacing`, `k = 0.55`.

### C6. Painted force fields

A `res × res` lattice of 2-D vectors in normalised space, row-major interleaved. Default **16×16**,
max 64, minimum 2, and any nonsense resolution clamps to 2.

Sampling is bilinear over a **node** lattice (not cell centres): `gx = clamp01(nx) × (res-1)`, four
weights, edge-clamped so out-of-range positions return the edge node.

Painting is a **saturating lerp toward** the painted direction:
```
w = (1 - dist/radius) * clamp01(strength)
node += (direction - node) * w
```
It never overshoots, so repeated strokes converge rather than pile up. Good design, copy it.

Composition: `acceleration += sampled * (8 × forceStrength)`. **No temporal decay and no spatial
decay** beyond the ramp into unpainted zeros. CPU only — this is one of the two things that force
their engine off the GPU entirely.

### C7. The custom-force expression language

This is small, self-contained and genuinely worth having. Full specification:

- **Kinds:** `off | radial | swirl | sine | expr`.
- **Tokens:** numbers, identifiers, and the single characters `+ - * / ( ) ,`. Skips **only** space
  and tab — a newline fails the whole expression. No exponent notation (`1e3` fails). `1.2.3` fails.
  Identifiers are lowercased.
- **Grammar** (recursive descent, standard precedence):
  ```
  expr  := term (('+'|'-') term)*
  term  := unary (('*'|'/') unary)*
  unary := '-' unary | '+' unary | call
  call  := number | '(' expr ')' | id '(' args ')' | id
  ```
  No power operator, no modulo, no comparisons, no ternary, no property access, no strings.
- **Variables:** `x, y, vx, vy, t, r, bass, pi`. `x`/`y` are **normalised 0–1**, `r` is distance from
  centre (0…~0.707), `vx`/`vy` are raw world units per second.
- **Functions:** `sin, cos, abs, sqrt, exp, min, max, atan2`. Arity strictly enforced.
- **Limits:** 96 characters, 80 nodes. Parse results are cached by source, **including failures**.
- **Safety:** division by zero returns 0; `sqrt` clamps the argument at 0; `exp` clamps at 20; any
  non-finite result becomes 0; an unknown identifier is rejected at parse time (so `alert(1)` and
  `constructor` both fail). Every error is silent — a typo simply produces no force.
- **The built-ins:** `radial = (dx, dy) × s × 8` outward · `swirl = (-dy, dx) × s × 8` ·
  `sine = (sin(t×2.2 + y×10) × s×4, cos(t×1.7 + x×10) × s×4)`.
- **Their bug:** for `expr`, `multiplier = (s == 0 ? 1 : s)` — so **strength 0 does not disable it**.

**Performance, and this matters:** it is a tree walk, per particle, per axis. Two string trims, two
dictionary lookups and two recursive walks with an array allocation per function call node. At 65k
particles that is millions of tiny allocations a second. **In Swift this must compile once to a flat
postfix array or a closure, with the lookup hoisted out of the loop.** Otherwise it will be the
slowest thing in the app by a wide margin.

### C8. The authoritative pass order

1. Reset stats. 2. Pick gravity (tilt or settings), read drag. 3. Build the grid if collisions,
flocking, fluid or gravity is on. 4. Fluid density then fluid forces, which **overwrite**
acceleration; otherwise zero it. 5. Precompute brush modes, field activity, damping, radii,
softening, and choose pairwise or grid gravity. 6. **One per-particle loop**: pinned skip → seed from
fluid + gravity → central spring → custom force → painted field → brushes → flocking → gravity →
fluid-brush attenuation → clamp acceleration **componentwise** to ±80 → integrate velocity → clamp
speed magnitude to 12 → fluid nudge → settle → save prev, move → collide → walls → boundary → NaN
guard → age. 7. Springs. 8. Compact the dead.

**Hard ordering:** grid before any query; density before forces; the gravity grid before sampling it;
fluid before the loop (it seeds acceleration); springs after integration; compaction last (spring
indices must be remapped after all kills).

**Note the acceleration clamp is componentwise, not by magnitude** — so it distorts the direction of
diagonal forces. Their choice; ours to make deliberately.

### C9. Cost cliffs

- **32 per cell is a silent correctness cliff, not just a speed one.** Past 32 in a cell, particles
  are not inserted at all: still simulated, invisible to every neighbour query. In a dense fluid the
  density under-reads, pressure clamps to zero and **the fluid collapses**. With cell = h this
  saturates in any genuinely dense fluid. This is the most important thing in the whole read.
- 1,600 particles is both a speed and a **behaviour** change (exact → monopole), visible as a jump in
  accuracy.
- Default cloth is ~3,600 springs × 6 iterations × 5 substeps = 108,000 constraint solves a frame.
- Walls are O(particles × walls), and the field-has-data check walks the entire field every step.
- Callback churn: flocking, the gravity grid and every grid query take a closure allocated **per
  particle per step**. In Swift, inline them.
- No early-out for sleeping particles.

### C10. Honest limits — and these are severe

**Fluid:**
1. **The kernel is not normalised.** `∫ (4/πh²)(1-r/h)² dA = 2/3`, not 1 — the correct 2-D constant
   for that shape is `6/(πh²)`. Densities read two-thirds of their true value, so `sphRestDensity =
   18` is a tuned number with no physical meaning.
2. Pressure, viscosity, cohesion and XSPH use **invented gains instead of actual kernel gradients**.
   The comment calls the pressure term "Spiky" but it is `q²` with a magic constant.
3. The pressure term divides by the neighbour's density only, so it is **asymmetric and does not
   conserve momentum** — i and j exchange unequal impulses.
4. What it calls XSPH is **not XSPH** — it is added into acceleration and divided by density, making
   it a second viscosity with a different coefficient.
5. No boundary or ghost particles, so the fluid leaks pressure at walls.
6. Pressure clamped at zero → no tension; the free surface is faked by `1 - ρ/restDensity`.

**Gravity:**
7. **Acceleration includes the particle's own mass** (`G·mᵢ·mⱼ/r³` used as acceleration), so **heavy
   particles accelerate faster.** Not Newtonian. A real error, and a decision for us: replicate for
   visual parity, or fix and lose their look.
8. The mass grid is monopole-only on a **fixed, non-adaptive, non-square** grid — no Barnes-Hut, no
   opening angle, no multipole correction. Force error **jumps discontinuously** as a particle
   crosses a cell line, which reads as jitter and heating.
9. A crowded cell is replaced by its centre of mass **including the querying particle's own mass** —
   a genuine self-force.
10. The GPU gravity has **no far field at all** — truncated at ±2 cells ≈ 0.14 world units, about 9%
    of the width. Their own shader comment admits it. Galaxies cannot self-bind on the GPU path.

**Everything else:**
11. Molecule bonds are distance-only; the water angle is initial geometry and nothing maintains it.
12. `params.flow` — the curl-noise flow field — **has no CPU implementation at all**. It is WGSL
    only, and it discards the noise magnitude (normalises twice), so it is a direction-only push. And
    since cloth or a painted field forces the CPU path, **those scenes lose the flow field entirely**.
13. **The CPU and GPU are not two implementations of one simulation, they are two simulations.**
    Flocking gains differ; the GPU fluid density starts at 1.0, omits mass, adds `q²×4`, and computes
    the surface term from a running partial density **inside** the neighbour loop so the result
    depends on iteration order; GPU collision is a naive symmetric half-push with no impulse; cell
    sizes differ; the GPU allows hover-attract where the CPU requires a press.

**What this means for us.** Helion is a good source of *shapes, ideas and tuned numbers*, and an
unreliable source of *physics*. The fluid kernel and the gravity both have genuine errors. Port the
structure and the feel, fix the maths where fixing it does not change the look, and where it does,
write down which we chose and why. Do not carry over the claim that any of it is physically correct.
