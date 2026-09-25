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

---

## Slice D — the generators and the scene presets

Reference material for the native Swift port. Everything below is derived from
`src/engine/emitters.ts` (1066 lines, 26 generators plus two streaming helpers),
`src/engine/generator-presets.ts` (456), `src/engine/scenes.ts` (239),
`src/engine/scenes.test.ts` (192) and `src/engine/emitters.test.ts` (142), with
supporting facts pulled from `src/engine/types.ts`, `src/engine/soa.ts`,
`src/engine/engine.ts`, `src/store/lab-store.ts` and `src/lib/import/*`.

### World model and coordinate conventions

All generators write into world space, not pixels or normalised device
coordinates. The engine keeps `worldH = 1` permanently and sets
`worldW = aspect` (the default is `1.6`; the unit tests use `worldW = 1.6`,
`worldH = 1`). **The y axis points down**: y = 0 is the top of the stage, y =
`worldH` the bottom. Consequences that matter for the port:

- "Up" is negative y, so fire, smoke and magma use **negative** `vy`, and their
  presets use **negative** `gravityY`.
- Lengths that should be isotropic are scaled by `span = min(worldW, worldH)`
  (which equals `worldH`, i.e. 1, in practice) so that a circle stays a circle
  on a wide stage. Many generators use `span` for radii but plain normalised
  constants for y — see *Honest limits*.
- The stage centre is `(cx, cy) = (worldW × 0.5, worldH × 0.5)`.

Uniform random helpers: `rand()` is `Math.random()` in [0,1); `randRange(a,b)`
is `a + (b − a)·rand()`. Both are **unseeded** (see *Unseeded randomness*).
Throughout this document `U(a,b)` means `randRange(a,b)` and `U` alone means
`rand()`.

### The particle record and the two shared primitives

Particles live in a struct-of-arrays (`ParticleSoA`): `posX/posY`,
`velX/velY`, `prevX/prevY` (Verlet history), `accX/accY`, `life`, `maxLife`,
`mass`, `density`, `pressure`, `phase`, `flags` (Uint32), `sleep` (Uint16).

Every generator goes through one local helper:

```ts
add(soa, x, y, vx, vy, life, mass, flags = 0, phase?) -> index | -1
```

which calls `soa.spawnSlot()` (returns −1 when `count >= capacity`) and then
`soa.writeParticle(...)`. The semantics that the port must copy exactly:

- `prevX = posX`, `prevY = posY` on spawn, so a freshly spawned particle has
  zero Verlet displacement regardless of `vel`.
- `life = −1` means **immortal**; `maxLife` is then forced to `1` (so any
  life-based colour map on an immortal particle reads a constant). For a finite
  life, `maxLife = max(life, 1e-4)`.
- `phase` is a free 0..1 scalar used by the renderers as a per-particle hue /
  palette coordinate. When a generator omits it, both `spawnSlot()` and
  `writeParticle()` fall back to `Math.random()` — so "no phase" means
  "random hue", never zero.
- `flags` is 0 unless stated. `FLAG_PINNED = 1`, `FLAG_SLEEP = 2`,
  `FLAG_CLOTH = 4`. Only the cloth generator sets flags.
- When the buffer is full `add` returns −1 and **every generator stops**: most
  `break` out of their loop, while `spawnNbody`, `spawnWater`, `spawnFireworks`,
  `spawnCrystal` and `spawnMandala` `return` early (discarding the springs they
  had accumulated, which only matters for crystal/mandala, both spring-free).

Springs use one helper:

```ts
bond(springs, a, b, rest, k = 0.48)   // silently skips if a < 0 or b < 0
```

`Spring = { a, b, rest, k }`. The default `k = 0.48` is never actually used —
every caller passes an explicit stiffness.

`spawnGenerator(kind, soa, opts)` is a plain switch over the 26 kinds and
**falls back to `spawnGalaxy` for an unknown kind**.

### The 26 generators at a glance

"Budget" is `spawnBudget(kind, cap)` from `engine.ts` — the default requested
count when the UI does not pass one — followed by any hard ceiling inside the
emitter itself. `cap` is the particle-buffer capacity (default 65 536; quality
presets 12 288 / 32 768 / 65 536). The engine additionally clamps the budget to
`min(remaining capacity, …)` and to **5000 on the Canvas2D backend**.

| Generator | Shape it makes | Budget (default request → emitter ceiling) | Springs |
|---|---|---|---|
| `galaxy` | Two-armed logarithmic-ish spiral with a tiny bulge, rigid-rotating | `min(max(4500, cap·0.08), 9000)` → none | no |
| `ring` | Single squashed annulus (ellipse, y × 0.86) | `min(max(3500, cap·0.06), 7000)` → none | no |
| `burst` | Point-source radial explosion from the cursor | `min(max(2400, cap·0.12), cap)` → none | no |
| `pour` | Narrow vertical jet from the top edge | `min(600, cap)` → **400** | no |
| `fall` | Full-width rain sheet across the top 8 % | `min(600, cap)` → **800** | no |
| `flock` | Uniform random scatter with random headings (boids seed) | `min(max(1800, cap·0.35), cap)` → none | no |
| `cloth` | 36 × 26 pinned spring mesh hanging from the top | `936` (36 × 26) → **936** | **yes, 3560** |
| `nbody` | Three Plummer-ish disc clumps orbiting a common centre | `min(max(2800, cap·0.2), cap)` → none | no |
| `text` | Glyph point-cloud rasterised from a 2-D canvas | `min(max(4000, cap·0.12), cap)` | no |
| `fire` | Rising flame column from the bottom 20 % | `min(600, cap)` → none | no |
| `smoke` | Slow wide plume from the bottom quarter | `min(600, cap)` → none | no |
| `fireworks` | 4–14 separate radial shells, one hue each | `min(max(2400, cap·0.12), cap)` → none | no |
| `water` | Hex-packed standing pool plus a falling inlet stream | `min(max(2800, cap·0.12), cap)` → none | no |
| `tornado` | Vertical funnel, radius growing with height | `min(max(1800, cap·0.35), cap)` → none | no |
| `lightning` | Recursive branching bolt, particles resampled along it | `min(max(1600, cap·0.08), 5000)` → none | no |
| `blackhole` | Squashed accretion disc, flat rotation curve | `min(1800, cap)` → **3200** | no |
| `supernova` | Fast outer shell (70 %) plus slow core (30 %) | `min(max(4000, cap·0.12), cap)` → none | no |
| `fibonacci` | Sunflower phyllotaxis disc (golden-angle spiral) | `min(max(4500, cap·0.08), 9000)` → none | no |
| `sierpinski` | Sierpiński triangle via the chaos game | `min(max(3500, cap·0.06), 7000)` → none | no |
| `crystal` | 5–8 six-armed snowflakes plus 4–10 hex shards | `min(max(3500, cap·0.1), cap)` → none | no |
| `magma` | Random upward embers from the bottom 38 % | `min(max(4000, cap·0.12), cap)` → none | no |
| `aurora` | Five wavy vertical curtains | `min(max(4000, cap·0.12), cap)` → none | no |
| `helix` | DNA double helix with beaded rungs | `min(max(3500, cap·0.1), cap)` → none | **yes, ~110** |
| `mandala` | 8-petal rose + 3 concentric rings + 8 chevron spikes + hub | `min(max(3500, cap·0.1), cap)` → none | no |
| `confetti` | Random scatter in the upper third with wild velocities | `min(max(4000, cap·0.12), cap)` → none | no |
| `molecule` | Discrete ball-and-stick benzene / water / alkane clusters | `min(max(1400, cap·0.08), 5000)` → none | **yes, ≤ ~2400** |

Only three of the 26 build springs: `cloth`, `helix`, `molecule`.

Six kinds are gated as Pro (`PRO_GENERATORS`): `crystal`, `magma`, `aurora`,
`helix`, `mandala`, `confetti`.

### How the spawn options are filled in

`Engine.spawn(kind, replace, origin?, count?)` builds the `SpawnOpts`. When
`replace` is true it clears the SoA **and** the spring list first. Then:

| Field | Value |
|---|---|
| `worldW`, `worldH` | engine world size (`1.6 × 1` by default) |
| `count` | `min(capacity − count, count ?? spawnBudget(kind, capacity))`, then `min(…, 5000)` on Canvas2D |
| `mass` | `params.mass` (default 1) |
| `lifespan` | for `burst`, `fireworks`, `lightning`, `fire`, `smoke`, `supernova`: `params.lifespan \|\| fallback` where fallback = 4.2 (smoke), 0.55 (lightning), 3.4 (supernova), else 2.2. Every other kind gets `params.lifespan` raw (default **0**, i.e. "no lifespan") |
| `spread` | always `0.85` |
| `speed` | `0.35` flock · `0.42` burst/fireworks · `1.15` supernova · `0.85` fire · `0.9` tornado · `0.7` everything else |
| `originX/originY` | `origin ?? (worldW·0.5, worldH·0.5)` — only `burst`, `pour` and `supernova` read it |
| `centralMass` | `params.centralMass` (default 1.35) — only `galaxy`, `ring`, `blackhole` read it |
| `textInput` | `params.textInput` (default `"HELION"`) — only `text` reads it |

The UI always passes an explicit `count` (`store.spawnCount`, clamped to
50..1 000 000 by the store), so `spawnBudget` is the fallback rather than the
normal path. `engine.spawn` adopts the returned springs only when the array is
non-empty (`if (result.springs.length) this.springs = result.springs`), so
spawning a spring-free generator **without** `replace` leaves an old cloth's
springs attached to whatever particle indices now occupy those slots.

### Generator geometry, one by one

#### galaxy

Centre `(cx, cy)`, `span = min(worldW, worldH)`, `inner = 0.018·span`,
`outer = 0.46·span`. Two arms (`arms = 2`), `turns = 1.15`, angular velocity
`ω = √(max(centralMass, 0.2))` (≈ 1.162 at the default 1.35).

Loop `i = 0 … n−1`. With probability **0.07** the particle is a *bulge* star:
radius `r = inner·(0.2 + 0.9·U^0.6)` (so `r ∈ [0.2·inner, 1.1·inner]`, a
disc barely 2 % of the span across), angle `θ = 2π·U`, `phase = 0.08` fixed.

Otherwise it is a *disc* star:

- `arm = i mod 2` — arms alternate strictly per index, not randomly.
- `t = U^0.5` (square-rooted uniform, biasing outward so areal density is
  roughly flat), `r = inner + (outer − inner)·t`.
- `twist = t·turns·2π = 2.3π·t`, `θ = twist + arm·π` (the second arm is the
  first rotated 180°).
- Cross-arm scatter `σ = span·(0.0035 + 0.01·t)·U(−1,1)` — thickness grows
  linearly from 0.35 % to 1.35 % of the span — applied **perpendicular** via a
  rotation by θ: `x = cx + cos θ·r − sin θ·σ`, `y = cy + sin θ·r + cos θ·σ`.
- `phase = frac(θ / 2π)` (written as `((θ/2π mod 1) + 1) mod 1` so it is
  positive), i.e. hue follows the winding angle and therefore stripes the arms.

Velocity for **both** branches is rigid-body rotation about the centre:
`vx = −(y − cy)·ω`, `vy = (x − cx)·ω`. Speed grows linearly with radius; this
is not Keplerian. `life = −1`, `mass = opts.mass` exactly.

#### ring

`R = 0.32·min(worldW, worldH)`, `width = 0.07·R`.

For `i = 0 … n−1`: `t = (i + U)/n` (stratified — one particle per angular bin
with sub-bin jitter), `θ = 2π·t`, `r = R + U(−width, width)`.
Position `x = cx + cos θ·r`, `y = cy + sin θ·r·0.86` — the ellipse reads as a
disc seen at a slight tilt.

`orbital = √(max(centralMass, 0.2))·r`, `vx = −sin θ·orbital`,
`vy = cos θ·orbital·0.86` (velocity squashed by the same 0.86 as the position,
so the ellipse is traced consistently). `life = −1`, mass unmodified, phase
left random.

#### burst

Every particle starts at *exactly* `(originX, originY)` — no positional
jitter, so frame 0 is a single bright dot.

`a = 2π·U`, magnitude `mag = speed·(0.35 + 0.85·U)·(0.4 + spread)`. With the
engine's fixed `spread = 0.85` the last factor is 1.25, giving
`mag ∈ [0.4375·speed, 1.5·speed]`; at `speed = 0.42` that is 0.18..0.63
world-units/s. `vx = cos a·mag`, `vy = sin a·mag`.

`life = lifespan > 0 ? U(0.5·lifespan, lifespan) : U(1.8, 3.6)`.
`mass = opts.mass·U(0.6, 1.4)`. Phase random.

#### pour

Origin `ox = originX`, `oy = min(originY, 0.12)` — note this clamps against the
raw constant 0.12, i.e. it assumes `worldH = 1`. Hard cap `n = min(count, 400)`.

Per particle: `x = ox + U(−0.01, 0.01)`, `y = oy`,
`vx = U(−0.4·spread, 0.4·spread)` (±0.34 at `spread = 0.85`),
`vy = speed·U(0.6, 1.1)`. `life = lifespan || −1`, mass unmodified, phase
random. Gravity in the preset (0.85) does the rest.

#### fall

Hard cap `n = min(count, 800)`. `x = U·worldW` (full width),
`y = U·0.08` (top 8 %, again assuming `worldH = 1`),
`vx = U(−0.04, 0.04)`, `vy = speed·U(0.15, 0.5)`, `life = lifespan || −1`,
`mass = opts.mass·U(0.5, 1.2)`, phase random.

#### flock

Pure seed for the boids solver: `x = U·worldW`, `y = U·worldH`,
heading `a = 2π·U`, `s = speed·U(0.4, 1)`, `v = (cos a·s, sin a·s)`,
`life = −1`, mass unmodified, phase random. The flocking behaviour itself is
in the physics step, not here.

#### cloth

Fixed lattice: `cols = 36`, `rows = 26` → 936 particles.
`spacing = 0.026·min(worldW, worldH)`,
`startX = (worldW − 35·spacing)·0.5` (horizontally centred),
`startY = 0.06` (a raw constant again).

Particle `(x, y)` sits at `(startX + x·spacing, startY + y·spacing)` with zero
velocity, `life = −1`, `mass = opts.mass`, phase random. Row 0 gets
`flags = FLAG_PINNED | FLAG_CLOTH = 5`; every other row gets `FLAG_CLOTH = 4`.
Springs are described in *Springs*, below.

#### nbody

Three hand-placed clumps, in normalised stage coordinates:

| # | centre (nx, ny) | `spread` | `heavy` | `share` of n |
|---|---|---|---|---|
| 0 | 0.28, 0.46 | 0.09 | 3.4 | 0.38 |
| 1 | 0.72, 0.54 | 0.09 | 3.0 | 0.38 |
| 2 | 0.50, 0.24 | 0.07 | 2.2 | 0.24 |

The shared barycentre is `(0.5·worldW, 0.48·worldH)` — note **0.48**, not 0.5.
For each clump, `d = (cx − comX, cy − comY)`, `dist = |d| + 1e-6`, and the
whole clump is given the same bulk tangential velocity of fixed magnitude
`orbit = 0.42`: `bulkV = (−dy/dist·0.42, dx/dist·0.42)`. The bulk speed is a
constant — it is *not* derived from the masses.

Per clump: `nClump = max(8, round(n·share))`, and members are placed with a
uniform-area disc sample: `r = √U · spread · span`, `θ = 2π·U`,
`x = cx + cos θ·r`, `y = cy + sin θ·r`.

The **first three** particles of each clump are "heavy":
`mass = opts.mass · clump.heavy · U(1.6, 2.8)` (so up to 3.4 × 2.8 ≈ 9.5 ×
base mass) and `phase = 0.95`. All others get `mass = opts.mass·U(0.45, 1.4)`
and `phase = r / (spread·span)` — normalised radius, so colour reads as a
radial gradient inside each clump. Velocity is `bulkV + U(−0.04, 0.04)` on
each axis. `life = −1`. There is **no internal count cap** (see *Honest limits*
— the scene test believes there is one).

#### text

See *Text and image spawning* for the rasterisation. Geometrically:
`scale = 0.45·min(worldW, worldH)`; a sampled glyph pixel at normalised
`(px, py) ∈ [−1,1]²` lands at `x = cx + px·scale + U(−0.002, 0.002)`,
`y = cy + py·scale + U(−0.002, 0.002)`. Velocity **zero**, `life = −1`,
`mass = opts.mass·U(0.8, 1.2)`, phase random.

#### fire

`x = cx + U(−0.18, 0.18)·worldW` (a column 36 % of the stage wide),
`y = 0.78 + 0.2·U` (bottom fifth, assumes `worldH = 1`),
`vx = U(−0.12, 0.12)`, `vy = −speed·U(0.45, 1.15)` (negative = upward).

`life = lifespan > 0 ? U(0.45·lifespan, lifespan) : U(0.9, 2.1)`.
`mass = opts.mass·U(0.4, 1.1)`.
`phase = min(1, (0.92 − y)·1.4 + 0.15·U)` — height-keyed hue, hottest at the
base. With `y` up to 0.98 the first term reaches −0.084, so **phase can go
slightly negative**; there is no lower clamp.

#### smoke

`x = cx + U(−0.1, 0.1)·worldW`, `y = 0.72 + 0.22·U`,
`vx = U(−0.06, 0.06)`, `vy = −speed·U(0.12, 0.4)` (slower rise than fire).
`life = lifespan > 0 ? U(0.6·lifespan, lifespan) : U(2.8, 5.4)`.
`mass = opts.mass·U(0.3, 0.8)` (light), `phase = 0.4·U` (a narrow band at the
dark end of the palette).

#### fireworks

`bursts = clamp(round(count / 350), 4, 14)`, `per = max(20, ⌊count/bursts⌋)`.
Each burst picks `ox = U(0.12, 0.88)·worldW` and `oy = U(0.12, 0.55)` — `oy`
is **not** multiplied by `worldH` — plus one shared `hue = U` that becomes the
`phase` of every particle in that shell, which is what makes each shell a
single colour.

Within a shell: `a = 2π·U`, `mag = speed·U(0.25, 1.15)`,
`life = lifespan > 0 ? U(0.4·lifespan, lifespan) : U(1.4, 3.2)`,
`mass = opts.mass·U(0.5, 1.3)`. All particles of a shell start at the same
point. Note `bursts·per` can exceed `count` slightly; the loop returns as soon
as the buffer refuses a particle but does not otherwise re-check `count`.

#### water

Two populations. `pool = ⌊0.78·n⌋` particles form a settled body of fluid;
the remaining 22 % form an inlet stream.

Pool: spacing `h = max(0.007, 0.012·min(worldW, worldH))`, bounds
`x ∈ [0.1·worldW, 0.9·worldW]`, `y ∈ [0.58·worldH, 0.96·worldH]`. Rows step by
`h·0.866` (= `h·√3/2`, hexagonal close packing) and odd rows are offset by
`h/2` in x. Each site is jittered by `U(−0.12h, 0.12h)` on both axes. Velocity
`(U(−0.015, 0.015), U(−0.01, 0.02))`, `mass = opts.mass·U(0.9, 1.2)`,
`phase = 0.35`, `life = −1`.

Stream: `x = 0.5·worldW + U(−0.045, 0.045)·worldW`,
`y = U(0.02, 0.16)·worldH`, `vx = U(−0.03, 0.03)`,
`vy = speed·U(0.35, 0.9)` (downward), `mass = opts.mass`, `phase = 0.7`,
`life = −1`. The two phases (0.35 vs 0.7) exist so the inlet reads as a
different shade from the pool under `colorMap: "density"`.

#### tornado

Parametrised by `t = i / max(n−1, 1)` sweeping 0 → 1 up the funnel:

- height `y = 0.08 + 0.86·t` (normalised), final
  `yy = y·worldH + U(−0.01, 0.01)`.
- radius `r = (0.018 + 0.22·t)·min(worldW, worldH)` — a straight cone, 1.8 % of
  the span at the tip widening to 23.8 % at the top.
- angle `θ = 14·t + 0.4·U`, i.e. **14 radians ≈ 2.23 full turns** from bottom
  to top, plus per-particle angular noise.
- `x = cx + cos θ·r + U(−0.008, 0.008)`.
- angular rate `ω = 2.4 − 1.1·t` (spinning faster at the narrow bottom),
  `vx = −sin θ·ω·r`, and `vy = −0.18·(1 − t) + U(−0.04, 0.02)` — an updraught
  strongest at the base. Note there is **no `cos θ·ω·r` term in `vy`**: only
  the x component of the circular motion is seeded, which is deliberate for the
  2-D side-on look but is not a real orbit.
- `phase = (θ/2π + t) mod 1`, `mass = opts.mass·U(0.5, 1.2)`, `life = −1`.

#### lightning

A recursive random walk collects *points*, then particles are sampled onto
them.

`bolt(x, y, angle, segLen, depth)` walks `segs = 7 + (3 − depth)·3` segments
(16, 13, 10, 7 for depth 0..3). Each step: `angle += U(−0.55, 0.55)`,
`p += (cos angle, sin angle)·segLen`. It **breaks** if `py > 0.98` or
`px < 0.02` or `px > worldW − 0.02`. Otherwise it records
`{x, y, phase: 1 − 0.22·depth}` (so the trunk is phase 1 and third-order twigs
0.34). With probability **0.22**, and only while `depth < 3`, it recurses:
`bolt(px, py, angle + U(−0.9, 0.9), segLen·0.62, depth + 1)`.

Seeds: `seeds = clamp(round(count / 1800), 1, 4)`, each started at
`x = U(0.22, 0.78)·worldW`, `y = 0.02`, `angle = π/2 + U(−0.15, 0.15)`
(downward, because y grows downward), `segLen = 0.045`.

Particle pass, `i = 0 … count−1`: `mix = points[i]` while
`i < points.length`, otherwise a uniformly random point. So every point is
covered once and the remaining budget is scattered over the same handful of
points. Then `x = mix.x + U(−0.006, 0.006)`, `y = mix.y + U(−0.006, 0.006)`,
`v = (U(−0.04, 0.04), U(−0.02, 0.12))`,
`life = lifespan > 0 ? U(0.4·lifespan, lifespan) : U(0.28, 0.7)`,
`mass = opts.mass·0.6`, `phase = mix.phase`. If no point survived the bounds
check the generator returns 0 spawned.

#### blackhole

`n = min(count, 3200)`, `span = min(worldW, worldH)`. With probability **0.08**
a particle is an *inner* one: `r = span·U(0.01, 0.05)`; otherwise
`r = span·(0.06 + U^0.45·0.38)` — the `U^0.45` exponent crowds particles toward
the outer edge, giving a bright rim. `θ = 2π·U`.

`x = cx + cos θ·r`, `y = cy + sin θ·r·0.62` (a strongly inclined disc).

`ω = √(max(centralMass, 1)) / max(r, 0.02)`,
`vx = −sin θ·ω·r·0.55`, `vy = cos θ·ω·r·0.38`. Because `ω·r` collapses to
`√M` for any `r > 0.02`, the tangential speed is **constant with radius** (a
flat rotation curve), scaled 0.55 in x and 0.38 in y. The 0.38/0.55 ratio
(0.69) does not exactly match the 0.62 positional squash, so the seeded orbits
are slightly non-elliptical from frame 0.

`mass = opts.mass · (inner ? 2.4 : U(0.5, 1.6))`,
`phase = inner ? 0.95 : min(1, r/(0.4·span))`, `life = −1`.

#### supernova

All particles start within `U(−0.008, 0.008)` of the origin. With probability
**0.7** a particle belongs to the *shell*: `mag = speed·U(0.85, 1.35)` and
`phase = U(0.55, 1)`. Otherwise it is *core* debris: `mag = speed·U(0.05, 0.45)`
and `phase = U(0, 0.35)`. Direction `a = 2π·U`.

`life = lifespan > 0 ? U(0.5·lifespan, lifespan) : U(2.2, 4.4)`,
`mass = opts.mass·U(0.5, 1.6)`. The bimodal speed plus bimodal phase is what
produces a bright expanding ring around a lingering dull core.

#### fibonacci

`outer = 0.44·min(worldW, worldH)`, and the golden angle is written exactly as

`golden = π·(3 − √5) ≈ 2.399963229728653 rad ≈ 137.50776°`

For `i = 0 … n−1`: `t = i / max(n−1, 1)`, `r = √t · outer`,
`θ = i · golden` (indexed by `i`, **not** by `t`). `x = cx + cos θ·r`,
`y = cy + sin θ·r`. The `√t` radius gives constant areal density, which is what
makes the phyllotaxis pattern read as a sunflower rather than a spiral.

Velocity: `ω = 0.55`, `vx = −sin θ·ω·r·0.15`, `vy = cos θ·ω·r·0.15` — i.e.
rigid rotation at an effective rate of `0.0825·r`. `phase = (t + θ/2π) mod 1`,
`mass = opts.mass`, `life = −1`.

#### sierpinski

Chaos game. `span = 0.42·min(worldW, worldH)`; the three vertices are

- apex `(cx, 0.12)`
- left `(cx − span, 0.12 + 1.62·span)`
- right `(cx + span, 0.12 + 1.62·span)`

so the base is `2·span` wide and `1.62·span` tall. (A true equilateral triangle
needs `√3·span ≈ 1.732·span`, so the figure is squat by ~6 %.) The y values mix
a raw 0.12 with span-derived heights, i.e. they assume `worldH = 1`.

Start at `(cx, 0.5)`. **24 warm-up iterations are run and discarded** — the
comment says this is so "the first particles aren't a smear from the seed".
Then for each of `count` particles: pick a vertex with `(Math.random()·3)|0`,
move to the midpoint `p = (p + v)·0.5`, and emit at `p` with zero velocity,
`life = −1`, `mass = opts.mass`, and `phase = (i mod 3)/3` — a fixed
0, ⅓, ⅔ colour cycle by **index**, not by which vertex was chosen, so the
colouring carries no geometric meaning.

#### crystal

The most involved generator: 5–8 snowflakes plus 4–10 loose shards, both built
from a shared hex-lattice helper. `span = min(worldW, worldH)`.

**`addHex(cx, cy, R, rot, phase, filled)`** walks axial hex coordinates
`q, r ∈ [−rings, rings]` keeping only cells with `|s| ≤ rings` where
`s = −q − r` (a hexagonal patch). `rings = filled ? max(2, round(R/(0.012·span))) : 1`.
Lattice → plane: `px = 1.5·q`, `py = √3·(r + q/2)`. When `filled` is false the
cell is skipped if `hypot(px, py) < 0.55·rings`, which hollows out the middle.
The patch is rotated by `rot` and scaled by `R / maxD` with
`maxD = 1.05·rings + 1e-6`, then offset to `(cx, cy)`. Velocity zero,
`life = −1`, `mass = opts.mass·U(0.85, 1.2)`, phase as passed.

**`addSnowflake(cx, cy, R, rot, phase)`** — six arms at
`ang = rot + arm·π/3`, `perArm = max(10, round(0.08·n/6))` beads each. Bead
`k` sits at radius `r = t·R` with `t = k/(perArm − 1)` and
`phase = (phase + 0.2·t) mod 1`. Side branches: when `k > 2` and `k` is even,
two barbs are grown at `ang ± π/3` with length `br = 0.28·R·(1 − t)` (shorter
further out), each barb being 3 beads at `u = 1/3, 2/3, 1` of `br`, with
`mass = opts.mass·0.85` and `phase = (phase + 0.15) mod 1`. Finally a filled
hex core of radius `0.18·R` is stamped at the centre.

**Layout.** `flakes = clamp(round(n/700), 5, 8)` placed at normalised sites
(0.22,0.28), (0.5,0.22), (0.78,0.3), (0.28,0.68), (0.72,0.66), (0.5,0.52),
(0.18,0.5), (0.84,0.5) — taken in order, cycling if needed — each jittered by
`U(−0.02, 0.02)` of the corresponding axis, with `R = span·U(0.1, 0.16)`,
`rot = 0.35·f` rad and `phase = (f mod 6)/6`.

**Shards.** `shards = clamp(round(n/900), 4, 10)`, each a *filled* hex at
`(U(0.12, 0.88)·worldW, U(0.12, 0.88)·worldH)` with `R = span·U(0.035, 0.06)`,
`rot = π·U` and `phase = (s mod 5)/5`.

Every `addHex`/`addSnowflake` call checks `spawned >= n` and bails, so the
budget is respected but a flake can be truncated mid-arm.

#### magma

`x = U(0.08, 0.92)·worldW`, `y = U(0.62, 0.98)·worldH`,
`vx = U(−0.08, 0.08)`, `vy = −speed·U(0.2, 1.1)` (upward),
`life = −1` (immortal — the preset relies on negative gravity plus drag, not on
lifespan), `mass = opts.mass·U(0.7, 1.4)`, `phase = U` (fully random hue).

#### aurora

`bands = 5`. For particle `i`: `band = i mod 5` and
`t = (i/bands) / max(count/bands, 1)`, which simplifies to `t = i/count` for
any `count ≥ 5` — so `t` sweeps 0 → 1 across the whole population while the
band index cycles, giving five interleaved curtains each spanning the full
height.

- `x = worldW·(0.12 + 0.18·band + 0.04·sin(9t)) + U(−0.01, 0.01)`. The five
  curtains sit at 0.12, 0.30, 0.48, 0.66, 0.84 of the width, each waving with
  amplitude `0.04·worldW` and period `2π/9 ≈ 0.698` in `t` (≈ 1.43 wavelengths
  top to bottom).
- `y = t·worldH·0.92 + 0.04 + U(−0.012, 0.012)`.
- `vx = 0.08·sin(6t + band)` (each band phase-shifted by 1 rad),
  `vy = U(−0.04, 0.04)`.
- `phase = (band/5 + t) mod 1`, `mass = opts.mass`, `life = −1`.

#### helix

`R = 0.2·min(worldW, worldH)`, `turns = 3.6`. 82 % of the budget goes to the
two strands: `strandBudget = ⌊0.82·n⌋`.

For `i < strandBudget`: `strand = i & 1` (strict alternation),
`t = (i >> 1) / max((strandBudget >> 1) − 1, 1)`,
`θ = t·turns·2π + strand·π` (the second strand is the first offset by half a
turn). Then `x = cx + cos θ·R`, `y = (0.07 + 0.86·t)·worldH`,
`vx = −sin θ·0.035`, `vy = 0.018` (a slow uniform drift downward),
`phase = 0.55·strand + 0.4·t`, `mass = opts.mass`, `life = −1`. Indices are
collected into `strandA` (strand 0) and `strandB` (strand 1).

Rungs: `rungs = min(22, min(|A|, |B|))`,
`step = max(1, ⌊min(|A|,|B|)/rungs⌋)`. Rung `r` joins
`A[min(|A|−1, r·step)]` to `B[min(|B|−1, r·step)]`. `beads = 4` particles are
placed by linear interpolation at `u = b/5, b = 1..4`, each with velocity
`(0, 0.018)`, `mass = opts.mass·0.55`, `phase = 0.28`, `life = −1`. Springs are
described below.

The emitter test asserts the result is a tall vertical object: height > 0.55,
width between 0.2 and 1.1, mean x within 0.25 of the stage centre, and more
than 8 springs.

#### mandala

`outer = 0.42·min(worldW, worldH)`. A small `place(r, θ, phase, m)` helper
converts polar to Cartesian about the centre and emits with zero velocity and
`life = −1`. Four layers are drawn in order:

1. **Rose petals** — `petalN = ⌊0.55·n⌋` angular samples.
   `θ = (i/petalN)·2π`, `rose = |cos 4θ|` (hence **8 petals**),
   `rMax = outer·(0.22 + 0.78·rose^0.55)`. Each spoke is filled radially with
   `fill = 5 + (i mod 3)` steps (5, 6 or 7): particles at
   `r = rMax·s/fill` for `s = 2 … fill`, i.e. 4–6 particles from
   `2/fill·rMax` out to `rMax`. `phase = 0.7·rose + 0.1`, mass unmodified.
2. **Three concentric rings** — `ring = 0,1,2`, radius
   `r = outer·(0.18 + 0.14·ring)`, populated with `8·(6 + 4·ring)` = 48, 80,
   112 particles at `θ = (k/count)·2π + 0.08·ring`,
   `phase = 0.15 + 0.12·ring`, `mass = opts.mass·0.9`.
3. **Eight chevron spikes** — for `star = 0..7`,
   `a0 = star·π/4 − π/2`, `a1 = a0 + π/8`, `r0 = 0.12·outer`,
   `r1 = 0.95·outer`, 19 samples `u = s/18`. For `u < 0.5` the particle runs
   outward along `a0` at `r = r0 + (r1 − r0)·2u`; for `u ≥ 0.5` it runs back
   inward along `a1` at `r = r1 + (r0 − r1)·(2u − 1)`. `phase = 0.85`.
4. **Hub** — a square-lattice diamond: `q, r ∈ [−8, 8]` with
   `|q| + |r| ≤ 8` (145 cells), at
   `(cx + q·outer·0.018, cy + r·outer·0.018)`, `mass = opts.mass·1.1`,
   `phase = 0.05`.

The emitter test verifies the 8-fold symmetry statistically: binning particles
by `|cos 4θ|`, the mean radius of the `> 0.7` bin must exceed that of the
`< 0.3` bin.

#### confetti

`life = lifespan > 0 ? lifespan : 3.2`. Then
`x = U(0.15, 0.85)·worldW`, `y = U(0.05, 0.35)·worldH`,
`vx = U(−0.7, 0.7)`, `vy = U(−0.15, 0.85)` (mostly downward but some tossed
up), `lifetime = U(0.4·life, life)`, `mass = opts.mass·U(0.5, 1.2)`,
`phase = U`. The preset's `shape: "spark"` plus random phase is what sells it.

#### molecule

Commented in the source as "Discrete ball-and-stick molecules — not a
self-gravitating lattice". `span = min(worldW, worldH)`,
`sBen = 0.055·span`, `sWat = 0.04·span`. Every atom is emitted with
`v = (U(−0.01, 0.01), U(−0.01, 0.01))`, `life = −1`, and `phase = species`
(the species id doubles as the colour key). `atom()` returns −1 once
`spawned >= n`, and `bond()` skips any pair containing −1, so a molecule can be
truncated with dangling half-bonds.

**`benzene(cx, cy, s)`** — 6 carbons at `θ_k = (k/6)·2π − π/2`, radius `s`,
`mass = 1.6·opts.mass`, `phase = 0.15`. Ring bonds `k → (k+1) mod 6` with
`rest = s` (exactly right: the chord of a regular hexagon equals its
circumradius) and `k = 0.62`. Each carbon also gets a hydrogen at radius
`1.55·s` along the same `θ_k`, `mass = 0.45·opts.mass`, `phase = 0.8`, bonded
with `rest = 0.55·s` (also exact) and `k = 0.5`. 12 atoms, 12 bonds.

**`water(cx, cy, s)`** — oxygen at the centre, `mass = 1.8·opts.mass`,
`phase = 0.05`. With `a = (104.5° / 2)` in radians = 0.9119 rad, the hydrogens
go at angles `π − a` and `a`, radius `s`, `mass = 0.4·opts.mass`,
`phase = 0.85`, bonds `rest = s`, `k = 0.7`. 3 atoms, 2 bonds. (The realised
H–O–H angle is `π − 2a` = 75.5°, not 104.5° — see *Honest limits*.)

**`chain(x0, y0, len, s, ang)`** — a zig-zag alkane. Atom `i` sits at
`(x0, y0) + (cos ang, sin ang)·s·i`, plus, for odd `i`, a perpendicular kick of
`0.35·s` along `ang + π/2`. `mass = opts.mass·(i mod 3 === 0 ? 1.5 : 1)`,
`phase = (i mod 5)/5`. Consecutive atoms bond with `rest = 1.05·s`,
`k = 0.55` (the true zig-zag spacing is `s·√(1 + 0.35²) ≈ 1.0595·s`, so the
chain is under slight tension by design). Called with `len = 9`,
`s = 0.032·span`, `ang = 0.15` rad, starting at `x − 0.16·span`.

**Sites** (normalised, in order): benzene at (0.22,0.32), (0.5,0.28),
(0.78,0.34), (0.3,0.68), (0.7,0.7); chain at (0.5,0.55); water at (0.18,0.52),
(0.86,0.55), (0.42,0.82), (0.62,0.18).

**Filler.** While `spawned < n` (with a `guard < n + 8` safety counter) it
drops extra molecules at `(U(0.1,0.9)·worldW, U(0.1,0.9)·worldH)`: 55 %
benzene with `s = sBen·U(0.7, 1.05)`, else water with `s = sWat·U(0.8, 1.2)`.
The loop also breaks once `springs.length > 2400`. The source comment is
explicit about the intent: "Tile extra discrete rings with gaps — never a
packed lattice or a disk."

The emitter test only requires `spawned > 30` and `springs.length >= 12`.

### Springs

Only three generators emit springs, and the engine keeps exactly one spring
list at a time (`this.springs = result.springs` when non-empty).

**cloth** — 36 × 26 grid, `spacing = 0.026·min(worldW, worldH)`, base
stiffness `k = 0.55`:

| Spring type | Condition | Rest length | Stiffness | Count |
|---|---|---|---|---|
| structural, horizontal | `x + 1 < cols` | `spacing` | 0.55 | 910 |
| structural, vertical | `y + 1 < rows` | `spacing` | 0.55 | 900 |
| shear, down-right | `x+1 < cols && y+1 < rows` | `spacing·√2` | `0.55·0.55 = 0.3025` | 875 |
| shear, down-left | `x > 0 && y+1 < rows` | `spacing·√2` | 0.3025 | 875 |

3560 springs total. There are no bending (skip-one) springs. **Pinned:** the
entire top row (`y = 0`, 36 particles) carries `FLAG_PINNED`; the solver is
expected to skip integrating those. Cloth's preset also sets `settle: true`,
`collide: false` and `clothIterations` comes from params (default 6, the cloth
*scene* raises it to 8).

**helix** — rungs only; the strands themselves are unbonded. Each of the ≤ 22
rungs is a 5-link chain: `strandA[i] → bead1 → bead2 → bead3 → bead4 →
strandB[i]`, every link with `rest = dist(A,B)/5` and `k = 0.55`, where
`dist` is measured from the *actual spawned positions*. That is ~110 springs
and up to 88 bead particles.

**molecule** — per-molecule bonds only, never between molecules: benzene ring
`rest = s, k = 0.62` and C–H `rest = 0.55·s, k = 0.5`; water O–H
`rest = s, k = 0.7`; chain C–C `rest = 1.05·s, k = 0.55`. Capped by the
`springs.length > 2400` break in the filler loop. No particle is pinned.

### The two streaming helpers (not part of the 26)

`emitAlongStroke(soa, x0, y0, x1, y1, spacing, speed, spread, life, mass)`
walks a line segment in `steps = max(1, ⌈dist / max(spacing, 0.002)⌉)` and
emits `steps + 1` particles at `t = s/steps`, each offset by
`U(−0.15·spread, 0.15·spread)` on both axes, with a random direction and
`mag = speed·U(0.1, 0.6)`. The paint tool calls it with `spacing = 0.008`,
`speed = 0.12`, `spread = 0.25·brushRadius`, `life = params.lifespan || 3.2`.

`emitContinuous(soa, x, y, dirX, dirY, n, spread, speed, life, mass)` emits `n`
particles around a base heading `atan2(dirY, dirX)`: angle
`base + U(−spread, spread)`, `mag = speed·U(0.7, 1.2)`, position jittered by
`U(−0.006, 0.006)` in x and `U(−0.004, 0.004)` in y,
`mass·U(0.7, 1.3)`. The engine drives it from an accumulator
(`acc += rate·dt; n = ⌊acc⌋; acc −= n`) with these specs:

| Stream | position | direction | rate/s | spread | speed | life fallback |
|---|---|---|---|---|---|---|
| `pour` | `(0.5·worldW, 0.06)` | (0, 1) | 420 | 0.35 | 0.55 | `lifespan \|\| −1` |
| `fall` | `(U·worldW, 0.02)` per particle | (0, 1) | 280 | 0.4 (overridden) | 0.22 | `lifespan \|\| −1` |
| `fire` | `(0.5·worldW ± 0.11, 0.92)` | (0, −1) | 360 | 0.45 (overridden) | 0.72 | `lifespan \|\| 1.8` |
| `smoke` | `(0.5·worldW ± 0.06, 0.9)` | (0, −1) | 180 | 0.6 (overridden) | 0.22 | `lifespan \|\| 4.4` |

`fall` is special-cased to call `emitContinuous` once *per particle* with a
fresh random x, which is how the rain covers the full width.

### `generator-presets.ts` — what a preset is

`GENERATOR_PRESETS: Record<GeneratorKind, Partial<LabParams>>` — a visual and
physics patch applied when the user taps a generator chip. It is **not**
geometry: the patch never touches particle count, and the geometry never reads
the patch (except indirectly via `mass`, `lifespan`, `centralMass` and
`textInput`, which are the four params the emitter actually sees).

The store's `runGenerator(kind)` applies it as `{ ...currentParams, ...patch }`
— layered over whatever is currently set, **not** over `DEFAULT_PARAMS`. This
is the crucial difference from scenes: any param a preset omits keeps its
current value, so presets *can* inherit stale state from a previous preset.
`runGenerator` also gates the six Pro kinds behind `entitled`, toggles the
`pouring`/`falling`/`firing`/`smoking` stream flags (a *toggle*, so tapping
`pour` twice turns the stream off), sets `replaceMode: true` and clears
`activeSceneId`.

Every one of the 26 presets explicitly sets the four mode flags
(`flock`, `nbody`, `sph`, `settle`) and the three force fields
(`gravityX`, `gravityY`, `centralMass`), which is how a preset undoes the
previous one's mode. Deviations from "all four flags false": `flock` sets
`flock: true`; `nbody` and `blackhole` set `nbody: true`; `water` sets
`sph: true`; `cloth`, `crystal` and `mandala` set `settle: true`.
`gravityX` is 0 in all 26. Relevant defaults for comparison: `drag 0.03`,
`blend "alpha"`, `palette "rainbow"`, `colorMap "palette"`, `pointSize 2.8`,
`shape "circle"`, `trails false`, `trailDecay 0.22`, `trailLength 0.72`,
`lifespan 0`, `centralMass 1.35`, `background "void"`, `boundary "bounce"`,
`bloom false`, `bloomStrength 1.5`, `softening 0.018`, `nbodyG 0.018`,
`collide false`, `restitution 0.42`, `particleRadius 0.0045`,
`lifeFadeOut 0.22`.

| Preset | Overrides (beyond the flags/gravity block described above) |
|---|---|
| `galaxy` | `gravityY 0`, `centralMass 1.35`, `blend alpha`, `colorMap palette`, `palette rainbow`, `drag 0.03`, `background void` |
| `ring` | `gravityY 0`, `centralMass 1.35`, `blend alpha`, `colorMap palette`, `palette rainbow`, `drag 0.03` |
| `burst` | `gravityY 0`, `centralMass 0`, `blend additive`, `colorMap speed`, `palette solar`, `trails true`, `drag 0.12` |
| `pour` | `gravityY 0.85`, `centralMass 0`, `colorMap palette`, `palette rainbow`, `drag 0.12` (no blend override) |
| `fall` | identical to `pour`: `gravityY 0.85`, `centralMass 0`, `colorMap palette`, `palette rainbow`, `drag 0.12` |
| `flock` | `gravityY 0`, `centralMass 0`, `blend alpha`, `colorMap palette`, `palette aurora`, `drag 0.04` |
| `cloth` | `settle true`, `gravityY 0.85`, `centralMass 0`, `collide false`, `blend alpha`, `colorMap mass`, `palette mono`, `trails false`, `drag 0.22` |
| `nbody` | `nbody true`, `gravityY 0`, `centralMass 0`, `colorMap mass`, `palette ice`, `drag 0.02`, `softening 0.028`, `nbodyG 0.028`, `bloom true`, `pointSize 3.2`, `background void` |
| `text` | `gravityY 0`, `centralMass 0`, `colorMap palette`, `palette aurora`, `drag 0.08` |
| `fire` | `gravityY −0.55`, `centralMass 0`, `lifespan 1.8`, `blend additive`, `colorMap life`, `palette ember`, `trails true`, `trailDecay 0.14`, `trailLength 0.85`, `bloom true`, `bloomStrength 2.1`, `drag 0.08`, `pointSize 3.6`, `background void` |
| `smoke` | `gravityY −0.22`, `centralMass 0`, `lifespan 4.4`, `blend alpha`, `colorMap life`, `palette mono`, `trails true`, `trailDecay 0.08`, `drag 0.28`, `pointSize 5.5`, `shape circle` |
| `fireworks` | `gravityY 0.55`, `centralMass 0`, `lifespan 3.2`, `blend additive`, `colorMap life`, `palette solar`, `trails true`, `trailDecay 0.12`, `trailLength 0.9`, `bloom true`, `bloomStrength 2.4`, `drag 0.02`, `pointSize 3.2`, `lifeFadeOut 0.4` |
| `water` | `sph true`, `gravityY 0.9`, `centralMass 0`, `blend alpha`, `colorMap density`, `palette ice`, `boundary bounce`, `restitution 0.28`, `drag 0.04`, `pointSize 3.2`, `sphRestDensity 22`, `sphPressure 5.6`, `sphViscosity 0.12`, `sphCohesion 0.62`, `sphSmoothing 0.032` |
| `tornado` | `flow true`, `flowStrength 1.8`, `flowScale 3.4`, `flowSpeed 0.7`, `gravityY −0.18`, `centralMass 2.8`, `blend additive`, `colorMap speed`, `palette plasma`, `trails true`, `trailDecay 0.12`, `drag 0.05`, `pointSize 2.4`, `background void` |
| `lightning` | `gravityY 0`, `centralMass 0`, `lifespan 0.55`, `blend additive`, `colorMap life`, `palette ice`, `trails true`, `trailDecay 0.22`, `bloom true`, `bloomStrength 2.8`, `drag 0.01`, `pointSize 2.2`, `shape diamond` |
| `blackhole` | `nbody true`, `nbodyG 0.055`, `gravityY 0`, `centralMass 6.2`, `softening 0.007`, `blend additive`, `colorMap speed`, `palette plasma`, `trails true`, `trailDecay 0.08`, `trailLength 1.1`, `boundary wrap`, `drag 0.004`, `pointSize 2.2` |
| `supernova` | `gravityY 0`, `centralMass 0`, `lifespan 3.4`, `blend additive`, `colorMap life`, `palette solar`, `trails true`, `trailDecay 0.1`, `bloom true`, `bloomStrength 3.0`, `drag 0.015`, `pointSize 3.4` |
| `fibonacci` | `gravityY 0`, `centralMass 0.4`, `blend additive`, `colorMap palette`, `palette aurora`, `trails true`, `trailDecay 0.16`, `drag 0.04`, `pointSize 2.6`, `background void` |
| `sierpinski` | `gravityY 0`, `centralMass 0`, `blend alpha`, `colorMap palette`, `palette rainbow`, `trails false`, `drag 0.2`, `pointSize 2.4`, `shape triangle` |
| `crystal` | `settle true`, `gravityY 0`, `centralMass 0`, `blend additive`, `colorMap position`, `palette ice`, `shape hex`, `trails false`, `drag 0.42`, `pointSize 4.2`, `bloom true`, `bloomStrength 1.4`, `collide false`, `background void` |
| `magma` | `gravityY −0.55`, `centralMass 0`, `blend additive`, `colorMap speed`, `palette ember`, `trails true`, `trailDecay 0.14`, `drag 0.04`, `pointSize 3.4`, `bloom true`, `bloomStrength 1.8`, `background gradient` |
| `aurora` | `gravityY 0`, `centralMass 0`, `blend additive`, `colorMap palette`, `palette aurora`, `flow true`, `flowStrength 1.1`, `flowScale 2.4`, `flowSpeed 0.35`, `trails true`, `drag 0.06`, `pointSize 2.8`, `background nebula` |
| `helix` | `gravityY 0`, `centralMass 0`, `blend additive`, `colorMap life`, `palette plasma`, `trails true`, `trailDecay 0.1`, `trailLength 0.92`, `drag 0.06`, `pointSize 3.2`, `bloom true`, `bloomStrength 1.6`, `background void` |
| `mandala` | `settle true`, `gravityY 0`, `centralMass 0`, `blend alpha`, `colorMap position`, `palette solar`, `shape diamond`, `trails false`, `drag 0.48`, `pointSize 2.8`, `background void` |
| `confetti` | `gravityY 0.55`, `centralMass 0`, `blend alpha`, `colorMap palette`, `palette rainbow`, `shape spark`, `lifespan 3.2`, `trails false`, `drag 0.08`, `pointSize 4`, `background void` |
| `molecule` | `gravityY 0`, `centralMass 0`, `blend alpha`, `colorMap mass`, `palette ice`, `shape circle`, `trails false`, `drag 0.16`, `pointSize 4.6`, `collide true`, `particleRadius 0.006`, `restitution 0.35`, `softening 0.03`, `background void` |

`emitters.test.ts` asserts two things about this file: every `GeneratorKind`
has a preset, and `crystal`, `helix`, `mandala`, `molecule` must have
`nbody !== true` and `centralMass` 0 (they must not secretly be galaxies).


### `scenes.ts` — what a scene is and how it differs from a preset

A scene is a **curated one-tap composition**: a generator kind + a
`Partial<LabParams>` patch + a declared particle count, and optionally a
simulation speed multiplier, a buffer-cap override and a "this drives the
continuous emitter" flag.

```ts
type Scene = { id, label, description?, kind, params, spawnCount, speed?, cap?, falling? }
type SceneId = "black-hole" | "galaxy-collision" | "fireworks" | "murmuration"
             | "whirlpool" | "flow-field" | "waterfall" | "cloth" | "nebula";
type SceneSpeed = 0.25 | 0.5 | 1 | 2 | 4;
```

Three differences from a generator preset:

1. **A scene is applied over a clean baseline.** `applyScene` computes
   `{ ...DEFAULT_PARAMS, ...scene.params }`, so any toggle the scene omits is
   *reset to its default*; a previous scene's distinctive flag can never leak.
   `runGenerator` merges a preset over the *current* params instead.
2. **A scene owns the particle count** (`spawnCount`) and may own the speed and
   the buffer cap; a preset never touches any of them.
3. **A scene is deliberately not a new generator.** The file's header comment is
   explicit: there is no dedicated black-hole or collision *generator*; those
   looks are produced by tuning physics on top of `nbody` / `galaxy` / `ring`.
   Consequently only 5 of the 26 kinds are used as scene bases: `nbody`,
   `galaxy` (×2), `burst`, `flock` (×2), `ring`, `fall`, `cloth`.

Display order is array order. Because each `params` block only lists fields
that differ from `DEFAULT_PARAMS`, the table below is the complete override set.

| Scene | Base kind | `spawnCount` | `speed` | Params it overrides |
|---|---|---|---|---|
| `black-hole` "Black Hole" | `nbody` | 2400 | — | `nbody true`, `nbodyG 0.06`, `centralMass 6.5`, `softening 0.006`, `drag 0.004`, `trails true`, `trailDecay 0.08`, `trailLength 1.1`, `blend additive`, `palette plasma`, `colorMap speed`, `boundary wrap`, `pointSize 2.2` |
| `galaxy-collision` "Galaxy Collision" | `galaxy` | 9000 | 2 | `nbody false`, `centralMass 3.2`, `drag 0.02`, `trails true`, `trailDecay 0.1`, `trailLength 0.95`, `blend additive`, `palette aurora`, `colorMap palette`, `boundary wrap`, `pointSize 2.4` |
| `fireworks` "Fireworks" | `burst` | 4000 | — | `trails true`, `trailDecay 0.12`, `trailLength 0.9`, `lifespan 3.4`, `gravityY 0.55`, `drag 0.02`, `blend additive`, `palette solar`, `colorMap life`, `pointSize 3.4`, `lifeFadeOut 0.4` |
| `murmuration` "Murmuration" | `flock` | 4000 | — | `flock true`, `flockSep 1.2`, `flockAli 1.6`, `flockCoh 1.3`, `flockRadius 0.07`, `drag 0.015`, `palette aurora`, `colorMap speed`, `blend alpha`, `pointSize 2.6` |
| `whirlpool` "Whirlpool" | `ring` | 5000 | — | `sph true`, `sphRestDensity 20`, `sphPressure 5.5`, `sphViscosity 0.12`, `sphSmoothing 0.03`, `centralMass 2.2`, `drag 0.03`, `boundary bounce`, `palette ice`, `colorMap density`, `blend alpha`, `pointSize 3.0` |
| `flow-field` "Flow Field" | `flock` | 8000 | — | `flow true`, `flowStrength 2.6`, `flowScale 4.0`, `flowSpeed 0.6`, `drag 0.06`, `palette plasma`, `colorMap speed`, `blend additive`, `trails true`, `trailDecay 0.16`, `pointSize 2.2` |
| `waterfall` "Waterfall" | `fall` | 600 | 1 | `gravityY 0.9`, `drag 0.02`, `palette ice`, `colorMap speed`, `boundary bounce`, `restitution 0.25`, `blend alpha`, `pointSize 2.8` — plus **`falling: true`** |
| `cloth` "Cloth" | `cloth` | 936 | — | `settle true`, `gravityY 0.85`, `clothIterations 8`, `collide false`, `drag 0.22`, `palette mono`, `colorMap mass`, `blend alpha`, `pointSize 3.2` |
| `nebula` "Nebula" | `galaxy` | 7000 | — | `centralMass 0.9`, `drag 0.05`, `bloom true`, `bloomStrength 2.6`, `blend additive`, `palette aurora`, `colorMap palette`, `trails true`, `trailDecay 0.14`, `trailLength 0.85`, `pointSize 3.0` |

No scene sets `cap`. Only `galaxy-collision` (2) and `waterfall` (1) set
`speed`; every other scene inherits the current speed.

**How a scene is applied** (`lab-store.applyScene(id)`):

1. Refuse in read-only/view mode; look the scene up by id (silently no-op if
   unknown); push the current state onto the undo stack.
2. `params = { ...DEFAULT_PARAMS, ...scene.params }`.
3. `spawnCount = clamp(round(scene.spawnCount), 50, SYSTEM_LIMIT)` where
   `SYSTEM_LIMIT = 1_000_000`.
4. `speed = scene.speed ?? current`, `cap = scene.cap ?? current`.
5. `pouring = false`, `firing = false`, `smoking = false`, and
   `falling = (scene.falling === true)` — a **definite assignment, never a
   toggle**, which is the documented reason scenes stay deterministic where
   `runGenerator` does not.
6. `replaceMode = true`, `spawnKind = scene.kind`, `spawnId++`, `clearId++`,
   `activeSceneId = scene.id`.

The canvas layer watches `spawnId` and calls
`engine.spawn(spawnKind, replaceMode, undefined, spawnCount)`, so the scene's
`spawnCount` **bypasses `spawnBudget`** entirely and is bounded only by the
buffer capacity (and by 5000 on the Canvas2D backend).

`waterfall` is the only scene using the continuous-stream path: its
`spawnCount: 600` merely seeds the initial sheet (deliberately under
`spawnFallBurst`'s 800 cap "so the number is honest"), after which the 280/s
`fall` emitter sustains it.

### What `scenes.test.ts` pins down about untrusted scene data

The test file is the de-facto validation contract for scene data — worth
mirroring in the Swift port because it encodes several non-obvious invariants:

- **Catalogue size** must be 8..10 (currently 9), all nine required ids must be
  present, and ids must be unique.
- **No invented generators**: every `scene.kind` must be a member of
  `GENERATOR_KINDS`.
- **Every scene needs a non-empty string label.**
- **Key-set exactness**: `{ ...DEFAULT_PARAMS, ...scene.params }` must have
  *exactly* the `DEFAULT_PARAMS` key set, and every key in `scene.params` must
  already exist in `DEFAULT_PARAMS`. This is how a typo'd param name is caught —
  a misspelling would introduce an extra key.
- **`spawnCount` finite and inside 50..200 000**, and `speed`, when present,
  must be one of 0.25 / 0.5 / 1 / 2 / 4.
- **`spawnCount` must not exceed the base emitter's real ceiling**, using a
  hand-maintained `EMITTER_CAP` table (nbody 2400, fall 800, pour 400,
  cloth 936, blackhole 3200, everything else `Infinity`), and at least 90 % of
  the declared count must actually survive the cap. The comment names the bug
  this guards: "the Black Hole 6000-vs-2400 mismatch", i.e. a scene silently
  dropping particles.
- **Baseline reset**: three explicit tests prove that layering a scene over
  `DEFAULT_PARAMS` clears a prior scene's flags — cloth must not inherit
  black-hole's `nbody`, black-hole must not inherit cloth's `settle`, and
  non-flock scenes must reset `flock`.

Two of those numbers are stale and should not be trusted in the port: the
`EMITTER_CAP` entry `nbody: 2400 // spawnNbody: Math.min(count, 2400)` is
fiction — `spawnNbody` has **no count cap at all** (the only `Math.min(count, …)`
ceilings in `emitters.ts` are pour 400, fall 800, blackhole 3200) — and
`CLAMP_MAX = 200_000` does not match the store, which clamps to
`SYSTEM_LIMIT = 1_000_000`. The `scenes.ts` doc comments repeat both errors.

`emitters.test.ts` adds the geometric contracts: every kind except `text` must
spawn > 0 (with `count = 400`, or 200 for `pour`); `fibonacci` and `sierpinski`
must fill ≥ 90 % of an 800 budget; `lightning` must span > 0.2 vertically;
`helix` must be tall (> 0.55), of bounded width (0.2..1.1), centred on the
vertical axis and produce > 8 springs; `mandala` must show radially longer
petals in the `|cos 4θ| > 0.7` bins than in the `< 0.3` bins; `molecule` must
produce ≥ 12 bonds; and `crystal`, binned onto a 16 × 10 occupancy grid, must
fill more than 8 but fewer than 72 % of the cells — i.e. it must be faceted
shards, not a filled sheet.

### Text and image spawning

**`spawnText`** rasterises through a 2-D canvas:

1. Try `new OffscreenCanvas(600, 300)`. On failure fall back to
   `document.createElement("canvas")` sized 600 × 300. If neither exists (pure
   Node), **return `{ spawned: 0 }`** — this is why the emitter test skips
   `text`.
2. `getContext("2d", { willReadFrequently: true })`; bail with 0 if null.
3. Fill the whole 600 × 300 black, then draw white text with
   `textAlign = "center"`, `textBaseline = "middle"`,
   `font = "bold 120px sans-serif"`, at `(300, 150)`. The string is
   `(opts.textInput || "HELION").toUpperCase()`.
4. `getImageData(0, 0, 600, 300)`, then scan with **stride 2 in both axes**
   (75 000 candidate pixels) and keep a pixel when its **red channel > 128**
   (red only — the text is white on black, so red is a proxy for luminance).
5. Each kept pixel is stored normalised as
   `(px, py) = ((x − 300)/300, (y − 150)/150)`, both in [−1, 1]. If nothing was
   kept, return 0 spawned.
6. For each of `count` particles pick a **uniformly random** entry of that list
   (with replacement — no dedup, no stratification), and place it at
   `cx + px·scale`, `cy + py·scale` with `scale = 0.45·min(worldW, worldH)`,
   plus `U(−0.002, 0.002)` jitter on each axis. Zero velocity, `life = −1`,
   `mass·U(0.8, 1.2)`, random phase.

Note the aspect distortion: x is normalised by the half-*width* (300) and y by
the half-*height* (150), but both are multiplied by the same `scale`, so the
glyphs come out **stretched 2× vertically**. Long strings also silently
overflow the 600 px canvas: there is no `measureText` fit, so a long input is
clipped to whatever falls inside the bitmap.

**Image / video / CSV import** lives outside `emitters.ts`, in
`src/lib/import/`, and reaches the engine through `engine.spawnSamples`, not
`spawnGenerator`:

- `sampleImageData(imageData, maxCount)` — pure function over an `ImageData`
  buffer. `want = clamp(maxCount, 50, width·height)`, stride
  `step = max(1, ⌊√(width·height / want)⌋)`, so the sampling grid adapts to the
  requested count. A pixel is skipped when `alpha < 16` or when luminance
  `(0.2126R + 0.7152G + 0.0722B)/255 < 0.04`. Output is
  `x = (x + 0.5)/width`, `y = (y + 0.5)/height` (unit square) and
  `phase = 0.3·R/255 + 0.4·G/255 + 0.3·B/255` — brightness-ish, encoded into
  the hue channel. Returns early once `maxCount` samples are collected.
- `sampleImageFile(blob, maxCount)` — needs the DOM: `URL.createObjectURL`, an
  `HTMLImageElement` load, a `<canvas>` of at most 512 × 512, `drawImage`, then
  `getImageData`. Revokes the object URL in a `finally`.
- `sampleVideoElement(video, maxCount)` — same, from an `HTMLVideoElement`
  frame (bails when `readyState < 2`), capped at 512 × 512.
- `parseParticleCsv(text)` — pure. Skips blank lines and `#` comments,
  auto-detects a header (first line contains "x", "y" and any letter), splits on
  comma/tab/semicolon, requires finite x and y, defaults `vx, vy = 0`,
  `mass = max(0.05, col4 ?? 1)`, `life = col5 ?? −1`,
  `phase = clamp(col6 ?? (row mod 7)/7, 0, 1)`, and stops at 1 000 000 rows.

`engine.spawnSamples(samples, replace)` decides the coordinate space by
sniffing: if `maxX ≤ 1.5` **and** `maxY ≤ 1.5` the samples are treated as unit
and multiplied by `worldW`/`worldH`; otherwise they are taken as raw world
coordinates. Missing fields default to `vx = vy = 0`, `life = −1`,
`mass = params.mass`, `phase = undefined` (→ random).

**No network or model call is involved in any of this.** Image import is a
local file/canvas read; CSV is a local parse. (The store does have a separate
`applyAiScene(scene)` path that accepts a generator + params + count from
elsewhere in the app, but the generators themselves never call out.)

### Dependencies: what is not pure computation

| Dependency | Where | Notes for the port |
|---|---|---|
| **DOM / canvas 2-D** | `spawnText` (OffscreenCanvas → `<canvas>` → give up), `sampleImageFile`, `sampleVideoElement` | The only generator of the 26 that is not pure arithmetic. In Swift, rasterise the string with Core Text / `CTLineDraw` into a 600 × 300 single-channel bitmap and keep the stride-2, red > 128 sampling rule. |
| **`Math.random`** | all 26 (see below) | Not a platform dependency, but it is global mutable state; no generator accepts a seed. |
| **GPU** | none of the spawners | `spawnGenerator` writes only into the CPU SoA. The engine then calls `gpu.uploadSoA(soa)` after a spawn and `gpu.uploadSlice(...)` after each continuous-emitter tick, but that is transport, not generation. Springs are solved on the CPU. |
| **Network / model call** | none | No generator, importer or scene fetches anything. |
| **Renderer-only params** | `blend`, `palette`, `colorMap`, `pointSize`, `shape`, `trails*`, `bloom*`, `background` | Presets and scenes set these, but they never influence geometry — safe to port independently of the emitters. |
| **Physics-only params** | `sph*`, `flock*`, `flow*`, `nbodyG`, `softening`, `settle*`, `collide`, `restitution`, `particleRadius`, `boundary`, `clothIterations`, `gravity*` | Same: the emitters read only `mass`, `lifespan`, `centralMass`, `textInput` (plus `count`, `spread`, `speed`, `origin*`, `world*`). |

So 25 of the 26 generators, the two streaming helpers, `sampleImageData` and
`parseParticleCsv` are pure, testable arithmetic. Only `spawnText` (and the
file/video importers) need a rasteriser.

### Honest limits

Things the code, its comments or its tests admit — or quietly demonstrate — are
approximate, unfinished, cheap or wrong:

1. **The `nbody` cap does not exist.** `scenes.test.ts` asserts against
   `nbody: 2400 // spawnNbody: Math.min(count, 2400)` and `scenes.ts` says
   "spawnNbody caps at 2400; declare the real ceiling so nothing is dropped".
   `spawnNbody` contains no such clamp. The guard the test claims to provide is
   therefore not guarding anything for that kind.
2. **`CLAMP_MAX = 200_000` is wrong.** Both the test comment and the `scenes.ts`
   doc comment claim the store clamps `spawnCount` to 50..200 000; the store
   actually clamps to 50..`SYSTEM_LIMIT` (1 000 000).
3. **Orbits are not orbits.** `galaxy` and `ring` seed rigid-body rotation
   (`v ∝ r`), and `blackhole`'s `ω = √M / max(r, 0.02)` collapses to a constant
   tangential speed. None of them is Keplerian (`v ∝ 1/√r`), so a disc seeded
   this way shears immediately once real gravity runs. `blackhole`'s velocity
   squash (0.38/0.55) also disagrees with its positional squash (0.62).
4. **`worldH = 1` is hard-coded into geometry.** `pour` (`min(originY, 0.12)`),
   `fall` (`y = U·0.08`), `fire` (`0.78 + 0.2U`), `smoke` (`0.72 + 0.22U`),
   `cloth` (`startY = 0.06`), `sierpinski` (apex `y = 0.12`), `fireworks`
   (`oy = U(0.12, 0.55)`) and `lightning` (`py > 0.98`, start `y = 0.02`) all mix
   raw normalised y constants with world-scaled x. They are only correct because
   the engine pins `worldH = 1`.
5. **`spawnText` distorts the glyphs** (2× vertical stretch, per above), does no
   `measureText` fit so long strings are clipped by the 600 px bitmap, samples
   the valid-pixel list with replacement (so particles duplicate and the density
   is noisy rather than even), and thresholds on the red channel alone.
6. **`spawnCloth`'s buffer-full path is broken.** `if (i < 0) break;` exits only
   the inner (x) loop, so the outer row loop keeps going; worse, `indices` then
   no longer lines up with the `y·cols + x` lookup used to build springs, so a
   cloth that hits the capacity limit gets springs between the wrong particles.
7. **`spawnCrystal`'s `addHex` normaliser is wrong.** `maxD = 1.05·rings`, but
   the furthest lattice cell of the patch is at `√3·rings ≈ 1.732·rings`, so a
   hex stamped with "radius R" actually extends to about `1.65·R`. Flake cores
   and shards are therefore larger than their nominal radius.
8. **`spawnSierpinski` is not equilateral** — the triangle is `2·span` wide but
   only `1.62·span` tall instead of `1.732·span` — and its `phase = (i mod 3)/3`
   colours particles by spawn index, not by the vertex chosen, so the colour
   banding is decorative noise. The 24-iteration warm-up is itself an admission
   that the first points are wrong ("so the first particles aren't a smear from
   the seed").
9. **`spawnLightning` re-uses very few distinct points.** A bolt yields on the
   order of 16–60 recorded points; after the first pass the remaining budget
   (often 1500+) is scattered onto randomly repeated points with only ±0.006
   jitter, so the bolt is a string of dense clumps rather than an even line.
   Branch recursion is depth-limited to 3 and probability-gated at 0.22, so many
   spawns produce a single unbranched streak.
10. **`spawnMolecule`'s water is the wrong shape.** With `a = 104.5°/2` the two
    hydrogens are placed at `π − a` and `a`, giving a realised H–O–H angle of
    `π − 2a = 75.5°`, not the intended 104.5°.
11. **Partial molecules / partial flakes.** `atom()` returns −1 once the budget
    is reached and `bond()` silently skips broken pairs, so `molecule` can end
    with half a benzene ring and `crystal` with a truncated arm. `molecule`'s
    filler loop also relies on a `guard < n + 8` counter and a
    `springs.length > 2400` break rather than a real budget calculation.
12. **`tornado` seeds only the x half of the swirl** (`vy` carries just the
    updraught), so the rotation is a visual convention rather than a circular
    velocity field. Its `θ = 14t` is likewise a magic 14 radians, not a
    parameter.
13. **`fire`'s phase can go slightly negative** (`min(1, (0.92 − y)·1.4 + 0.15U)`
     with `y` up to 0.98 gives as low as −0.084); only the upper bound is
     clamped.
14. **`helix` is coloured by `colorMap: "life"` but spawns `life = −1`.** Because
     immortal particles get `maxLife = 1` and `life = −1`, the life ratio is
     constant, so that mapping conveys nothing; the same applies to `magma`
     (immortal, `colorMap: "speed"` saves it) and to any immortal generator under
     a life-based map.
15. **Spring lists are global and fragile.** The engine keeps one array and only
     replaces it when a generator returns a non-empty one, so spawning a
     spring-free generator without `replace` leaves stale springs pointing at
     recycled indices. `killSwap` compaction moves particles between indices
     without touching the spring list at all.
16. **Presets leak state by design.** `runGenerator` merges over the *current*
     params, so a param no preset happens to set (say `flow*` after tapping
     `tornado`, or `sph*` after `water`) persists into the next generator.
     Scenes were added specifically to avoid this, and only scenes get the
     `DEFAULT_PARAMS` baseline.
17. **Budgets are heuristics, not measurements.** `spawnBudget` is a hand-tuned
     switch of magic constants (`cap·0.08`, `cap·0.35`, …) with a blanket
     `min(budget, 5000)` on the Canvas2D backend, and several generators
     over-produce internally (`fireworks`' `bursts·per` can exceed `count`;
     `crystal`/`mandala`/`molecule` only stop when the next `add` is refused).

### Unseeded randomness

Every stochastic decision in `emitters.ts` goes through `rand()` /
`randRange()`, both thin wrappers over `Math.random()`, plus two direct
`Math.random()` calls inside `spawnSierpinski` and the implicit
`Math.random()` fallbacks for `phase` inside `spawnSlot`/`writeParticle`. There
is **no seed parameter, no injectable RNG and no determinism anywhere**:

- The same scene applied twice never reproduces the same picture. Saved
  creations restore *params*, not particle positions.
- `emitters.test.ts` can only make statistical assertions (spans, occupancy
  fractions, ≥ 90 % fill) because exact positions are not reproducible.
- Generators whose *structure* is random — `lightning`'s branch points,
  `crystal`'s shard placement, `molecule`'s filler tiling, `sierpinski`'s chaos
  game, `fireworks`' shell centres — vary substantially run to run, so any
  golden-image test in the Swift port will need an injected seeded generator.

For the port, threading a seedable PRNG (e.g. a small xoshiro/PCG passed through
`SpawnOpts`) through these functions is a cheap change that unlocks
reproducible captures, snapshot tests and shareable "same look" links — none of
which this reference codebase can do.

---

## Slice E — rendering: shapes, trails, bloom, backgrounds, the GPU paths

Reference source: `Built-Helion` (TypeScript / WebGL2 / WebGPU). This document is a complete
transcription of the rendering behaviour so the visuals can be rebuilt in Swift/Metal without
reopening the originals.

Files covered: `src/engine/shaders.ts` (GLSL + WGSL), `src/engine/webgl-renderer.ts`,
`src/engine/webgpu-backend.ts`, `src/engine/canvas-renderer.ts`, `src/engine/glyph-atlas.ts`,
`src/engine/webgpu-buffers.ts`, `noise.wgsl`, `src/components/lab/backdrop.tsx`. Supporting
constants pulled from `src/engine/camera.ts`, `src/engine/point-size.ts`,
`src/engine/palettes.ts`, `src/engine/types.ts`, `src/engine/engine.ts`.

### Coordinate conventions used throughout

| Space | Definition |
| --- | --- |
| World | `x ∈ [0, worldW]`, `y ∈ [0, worldH]`, **y points down**. `worldH = worldScale` (1.0 at rest), `worldW = aspect · worldScale`. |
| NDC | `ndc.x = x/worldW · 2 − 1`, `ndc.y = 1 − y/worldH · 2`. The `worldW`/`worldH` divisors are guarded with `max(·, 1e-6)`. |
| Backing pixels | CSS pixels × dpr. `dpr` is clamped per quality mode: low `= max(0.5, min(native,1)·0.7)`, medium `= min(native, 1.35)`, high `= min(native, 2.5)`, then `dpr = max(0.5, dpr)`. |
| Background colour | `(0.031, 0.035, 0.047)` linear-ish sRGB values written straight to an 8-bit target ⇒ `#08090C`. Used identically as the clear colour, the fade-quad colour, and the bloom threshold floor. |

---

### 1. The three backends

The engine (`ParticleEngine.start()`, `engine.ts` ≈ line 176) probes in a strict order and keeps
the first success. There is **no** quality- or device-based preference and no way to force a
backend from params.

1. `tryCreateWebGPU(canvas, cap)` — `navigator.gpu.requestAdapter({ powerPreference: "high-performance" })`, then `requestDevice()`, then `navigator.gpu.getPreferredCanvasFormat()`. If `attachCanvas()` fails the backend is disposed and the probe returns `null`. Any throw is caught, warned, and treated as unavailable.
2. `canvas.getContext("webgl2", { alpha: false, antialias: false, depth: false, stencil: false, premultipliedAlpha: true, powerPreference: "high-performance", preserveDrawingBuffer: true, failIfMajorPerformanceCaveat: false })`.
3. `canvas.getContext("2d", { alpha: false })`. If even this fails, `start()` throws `"No rendering context"`.

| | WebGPU | WebGL2 | Canvas2D |
| --- | --- | --- | --- |
| `backend` tag | `"webgpu"` | `"webgl"` | `"canvas"` |
| `compute` tag | `"webgpu"` | `"cpu"` | `"cpu"` |
| Physics | GPU compute (3 passes) **or** CPU, see below | CPU only | CPU only |
| Particle primitive | 6-vertex instanced triangle list (quad per particle) | `gl.POINTS` with `gl_PointSize` | one `ctx.fill()`/`drawImage` per particle |
| All 12 shapes | yes (SDF in fragment shader) | yes (SDF in fragment shader) | yes, but as **path geometry**, not SDFs |
| Velocity-streak stretch | **yes** (vertex shader) | **no** | no — draws a real line segment instead |
| Trails | fade quad into an accumulation texture | fade quad into an accumulation FBO | fade `fillRect` over the visible canvas |
| Bloom | 20-tap single-pass post shader | identical 20-tap post shader | `ctx.shadowBlur` only |
| Orbit camera | yes, in WGSL | yes, in GLSL | yes, on the CPU via `projectOrbit()` |
| Sorting | none | none | none |
| Decimation | none | none | **yes** — `step = n > 12000 ? ceil(n/12000) : 1` |
| Life fade curve uniform | hard-coded `0.22` | real `u_lifeCurve` uniform | `min(1, life)` |
| Draw calls per frame | 1–3 (`fade?` + `particles?` + `post`) | 1–3 | `1 + drawnParticles` |

**Important**: even on WebGPU the physics may run on the CPU. `engine.render()` computes
`cpuDriven = compute === "cpu" || springs.length > 0 || field !== null`; when true it re-uploads
the whole SoA every frame via `uploadSoA()` and the compute passes are effectively decoration.
Cloth/springs and painted force fields therefore **force** the CPU path.

---

### 2. Particle shapes — the exact coverage functions

All shapes are evaluated in a local square `p ∈ [−1, 1]²`:

* **WebGL**: `p = gl_PointCoord · 2 − 1`. `gl_PointCoord` has **y down**, so shapes are
  vertically mirrored relative to the WebGPU path.
* **WebGPU**: `p = in.coord`, the raw quad corner interpolated from
  `corners = [(−1,−1), (1,−1), (−1,1), (−1,1), (1,−1), (1,1)]`, i.e. **y up**.

Both compute `dist = |p|` (Euclidean) first, then override `dist` per shape. The WebGL path has
an extra **global early-out before the switch**: `r2 = dot(p,p); if (r2 > 1.0) discard;` — so in
WebGL every non-glyph shape is additionally clipped to the unit disc. WebGPU has no such clip.
This is a real, visible divergence (see §10).

The output alpha is always `a = soft · 0.8 · lifeAlpha · u_energy` (WebGL) or
`a = soft · 0.8 · lifeAlpha` (WebGPU — no energy term), and the fragment is emitted
**premultiplied**: `frag = vec4(colour · a, a)`.

Anti-aliasing is done **entirely by `smoothstep` on the implicit field** — there is no MSAA, no
derivative-based (`fwidth`) width, and no distance-to-edge normalisation. Every softening width
is a hard-coded constant in the shape's own metric units, so the apparent edge softness in pixels
**shrinks as the particle grows**. Shapes are also hard-`discard`ed at their outer bound, which
clips the outer half of the smoothstep ramp for several shapes.

| id | name | metric `d(p)` | discard when | soft = `1 − smoothstep(e₀, e₁, d)` | notes |
| --- | --- | --- | --- | --- | --- |
| 0 | circle | `‖p‖` | `d > 1` | `e₀ = 0.85`, `e₁ = 1.0` | widest AA ramp (0.15) |
| 1 | square | `max(|pₓ|, |p_y|)` — Chebyshev | `d > 1` | `0.8 → 1.0` | ramp 0.2; WebGL's disc pre-clip rounds the corners |
| 2 | ring | `|‖p‖ − 0.7| · 3.33` | `‖p‖ > 1` | `0.6 → 1.0` | annulus centred at r = 0.7; the `3.33` normalises a 0.3-wide band to ≈1. Fully opaque core for `‖p‖ ∈ [0.52, 0.88]` |
| 3 | diamond | `|pₓ| + |p_y|` — L1 | `d > 1` | `0.8 → 1.0` | |
| 4 | triangle | `edge = max(p_y − 0.72, |pₓ| − hw)` where `hw = 0.85·(p_y + 1)/1.7` | `p_y > 0.72` **or** `|pₓ| > hw` | `1 − smoothstep(−0.12, 0.0, edge)` | apex/base orientation flips between backends (y-down vs y-up). Half-width grows linearly with `p_y`; `hw = 0.85` at `p_y = 0.7` |
| 5 | star | 5-point polar: `an = atan2(p_y, pₓ)`; `sector = 2π/5 = 1.25664`; `a = mod(an + 1.5707963, sector) − sector/2`; `t = |a|/(sector/2)`; `edge = mix(1.0, 0.38, t)` | `‖p‖ > edge` | `1 − smoothstep(0.78·edge, edge, ‖p‖)` | tip radius 1.0, valley radius 0.38; `+π/2` rotates a point to the top. AA width is 22 % of the *local* radius so it varies around the star |
| 6 | hex | `max(|pₓ|, |pₓ|·0.5 + |p_y|·0.866025)` | `d > 0.95` | `0.78 → 0.95` | `0.866025 = √3/2`; flat-top/pointy orientation follows the axis convention |
| 7 | plus | `min( max(3.2·|pₓ|, |p_y|), max(3.2·|p_y|, |pₓ|) )` | `d > 1` | `0.8 → 1.0` | arm half-thickness = 1/3.2 = 0.3125 |
| 8 | heart | `hp = (pₓ, p_y + 0.2)`; `ax = |hpₓ|`; `heart = ax² + (hp_y − 0.18·√ax)²` | `heart > 0.42` | `smoothstep(0.28, 0.42, heart)` | field is a *squared* distance, so the ramp is non-linear in space. `0.18·√ax` makes the lobes; `+0.2` shifts it |
| 9 | spark | `plus = min( max(4.2·|pₓ|, |p_y|), max(4.2·|p_y|, |pₓ|) )`; `dia = |pₓ| + |p_y|`; `d = min(plus, 0.72·dia)` | `d > 1` | `0.72 → 1.0` | thinner plus (half-thickness 1/4.2 ≈ 0.238) intersected with a scaled diamond → four-point sparkle. Widest ramp of any shape (0.28) |
| 10 | emoji | glyph-atlas texture sample, see §7 | `g.a < 0.06` | n/a — alpha comes from the texture | |
| 11 | sprite | same path as 10 | `g.a < 0.06` | n/a | |

Shapes 10/11 share a single branch and differ only in what was uploaded to the atlas.

**Glyph branch colouring** (identical maths on both GPU backends):

```
uv    = WebGL: gl_PointCoord                 (y already down)
        WebGPU: (coord.x·0.5 + 0.5, 0.5 − coord.y·0.5)   // explicit V flip
g     = sample(glyphAtlas, uv)
pal   = sample(palette, (clamp(metric, 0, 0.92), 0.5))    // 0.92 clamp: WebGL only
col   = mix(g.rgb, g.rgb · pal, 0.22)       // only 22 % palette tint
a     = g.a · lifeAlpha
out   = vec4(col · a, a)
```

Note the `0.22` mix — emoji/sprites keep 78 % of their native colour. Note also that WebGL clamps
the palette coordinate to `0.92` (so the top 8 % of every palette is unreachable) while WebGPU
clamps to `1.0`. Another real divergence.

**Life fade.** WebGL uses a genuine uniform:

```
lifeAlpha(life) = 1                                  if life < 0        // immortal
                = 0                                  if life == 0
                = smoothstep(0, max(u_lifeCurve.y, 0.001), life)
```

`u_lifeCurve = (params.lifeFadeIn, params.lifeFadeOut)` — **`.x` (fade-in) is never used**; only
the fade-out constant matters. WebGPU hard-codes it as `smoothstep(0, 0.22, life)` applied when
`life >= 0`, which means WebGPU treats `life < 0` (immortal) as fully opaque but also *skips* the
`life == 0` cull in the fragment stage (the vertex stage collapses dead particles instead, via
`alive = life != 0 ? 1 : 0` scaling the quad to zero size). The default `lifeFadeOut` is `0.22`,
so the two agree by default and diverge as soon as the user moves the slider.

**Colour metric** (`metric ∈ [0,1]`, indexes the 256×1 palette LUT). Six modes; ids as packed
into `flags >> 8`:

| id | `colorMap` | formula |
| --- | --- | --- |
| 0 | `speed` | `min(1, ‖v‖ / 2.4)` (WebGL divides by `maxSpeed`, always called with `2.4`) |
| 1 | `life` | WebGL: `life < 0 ? 1 : life / max(maxLife, 1e-4)`. WebGPU: `clamp(life, 0, 1)` — **not normalised** |
| 2 | `density` | WebGL/CPU: `min(1, density / 40)`. WebGPU: falls through to the mass formula |
| 3 | `mass` | `min(1, mass / 3)` |
| 4 | `palette` | raw `phase` attribute |
| 5 | `position` | `min(1, ‖p − c‖ / max(0.5·min(worldW, worldH), 1e-4))`, `c = (worldW/2, worldH/2)` |

The palette LUT itself is a 256×1 RGBA8 texture baked on the CPU (`bakeParamsPalette`),
`LINEAR` filtered, `CLAMP_TO_EDGE`, sampled at `v = 0.5`. Priority: custom multi-stop list →
two-stop `colorA`/`colorB` gradient → one of seven named palettes (`rainbow`, `ember`, `ice`,
`aurora`, `solar`, `mono`, `plasma`; 4–7 RGB stops each, linearly interpolated). A `tint` hex is
multiplied in at bake time. Only re-baked when the key
`palette:tint:colorA:colorB:stopsJSON` changes.

**Canvas2D shapes are different geometry, not the same maths.** `drawDot()` builds real paths:
square = `rect(x−s, y−s, 2s, 2s)`; ring = `arc` stroked with `lineWidth = max(1, 0.28s)`;
diamond/triangle/hex/star = explicit polygons (star uses 10 vertices alternating `r = s` and
`r = 0.4s`, starting at `−π/2`, step `π/5`); heart = four `bezierCurveTo` segments; plus/spark =
two overlapping rects with half-thickness `0.35s` (plus) or `0.22s` (spark); emoji = `fillText`
at `max(12, 2.6s)px` with the emoji font stack. Star valley radius is **0.4** here versus **0.38**
in the shaders; triangle is a simple `(0,−s), (s,s), (−s,s)` rather than the tapered shader form.

---

### 3. Trails

The mechanism is a **persistent accumulation colour texture plus a per-frame translucent fade
quad**. There is no history ring buffer and no per-particle trail geometry on the GPU paths.

Per frame, on both GPU backends:

1. If `firstFrame || !params.trails` → **clear** the accumulation target to `(0.031, 0.035, 0.047, 1)` (`loadOp: "clear"` on WebGPU; `glClear` with blending disabled on WebGL). `firstFrame` is set on creation and on every resize.
2. Otherwise → `loadOp: "load"` and draw a **full-screen quad** of colour `(0.031, 0.035, 0.047, fade)` with `SRC_ALPHA, ONE_MINUS_SRC_ALPHA` blending. WebGL uses a 4-vertex `TRIANGLE_STRIP` over the static quad VBO `[-1,-1, 1,-1, -1,1, 1,1]`; WebGPU uses a 6-vertex triangle list generated in the shader.
3. Particles are then drawn **into the same accumulation target**.
4. The post/bloom pass blits the accumulation texture to the swapchain/default framebuffer.

**Fade maths** (`trailFadeAlpha`, `camera.ts`):

```
d       = isFinite(trailDecay) ? trailDecay : 0.22
persist = max(0.12, isFinite(trailLength) ? trailLength : 0.72)
fade    = clamp(d / persist, 0.03, 0.55)
```

So trail length is a **divisor**, not a length: longer `trailLength` ⇒ smaller `fade` ⇒ slower
decay. Defaults `trailDecay = 0.22`, `trailLength = 0.72` give `fade = 0.3056`.

Persistence is a geometric decay towards the background. After *k* frames a pixel retains
`(1 − fade)^k` of its original excess over the background. Useful conversions:

* Half-life in frames: `k½ = ln(0.5) / ln(1 − fade)`. At `fade = 0.3056`, `k½ ≈ 1.9` frames — the default trail is *very* short.
* A visible 1 % tail lasts `ln(0.01)/ln(1 − fade)` frames ≈ 12.6 frames at the default.
* The clamp means the slowest possible decay is `fade = 0.03` (half-life ≈ 22.8 frames, 1 % tail ≈ 151 frames) and the fastest is `0.55` (half-life ≈ 0.87 frames).

This is **frame-rate dependent**: the fade is applied once per rendered frame with no `dt`
term, so trails are shorter at 120 Hz than at 60 Hz.

**Velocity-streak stretching — WebGPU only.** In `WGSL_RENDER_VS.vs`, before the quad corner is
scaled to pixels:

```
spd = ‖vel‖
if (trailLength > 0.08 && spd > 0.04) {
  dir     = vel / spd
  tan     = (−dir.y, dir.x)
  stretch = 1 + trailLength · min(spd, 2.4)
  c       = dir · corner.x · stretch  +  tan · corner.y
}
```

The quad is rotated into the velocity frame and stretched **along** `dir` by `stretch`, capped at
`1 + 2.4·trailLength` (so ≤ 3.4× at `trailLength = 1.0`). The cross-axis is untouched. Because the
shape SDF still evaluates on the *unstretched* `corner`, the shape itself is smeared rather than
re-derived — a circle becomes an ellipse, a star becomes a stretched star. `params.trailLength`
reaches the shader via uniform slot 52 and is **forced to 0 when `params.trails` is false**, so
stretching only happens with trails on.

WebGL has **no** streak stretching at all — `gl_PointSize` is isotropic. Canvas2D instead draws a
literal line: when `params.trails && trailLength > 0.15` it strokes from the projected
`(prevX, prevY)` to the projected `(posX, posY)` with `lineWidth = max(1, 0.9·sz)` and
`lineCap = "round"`, which is a third, geometrically different look.

Canvas2D trails also fade the **visible** canvas directly (`fillStyle = rgba(8,9,12,fade)`,
`fillRect` over the whole canvas) — there is no offscreen accumulation texture, so the trail is
destroyed by any external clear.

---

### 4. Bloom / glow

A **single-pass, full-resolution, 20-tap threshold blur**. There is **no downsampling**, no
mip chain, no separable two-pass Gaussian, and no ping-pong. Identical maths in
`GL_POST_FS` and `WGSL_POST.fs_post`.

```
base = sample(accum, uv)
if (bloomEnabled <= 0.5) return base;              // hard early-out
step = (1 / texSize) * (2.8 * bloomStrength)       // per-tap scale, in texels
bg   = vec3(0.031, 0.035, 0.047)
bloom = 0
for k in 0..19:
  s      = sample(accum, uv + offsets[k] * step).rgb
  bright = max(s - bg, 0)                          // background subtraction, per channel
  lum    = dot(bright, vec3(0.3, 0.59, 0.11))      // NTSC-ish luma
  bloom += bright * smoothstep(0.04, 0.22, lum)    // soft knee threshold
bloom = (bloom / 20) * bloomStrength * 2.1
out   = vec4(base.rgb + bloom, 1.0)                // straight additive, alpha forced to 1
```

The 20 taps (all weights equal — `1/20` — so this is a **box**, not a Gaussian):

| ring | offsets | radius |
| --- | --- | --- |
| 1 (axial) | `(±1,0), (0,±1)` | 1.0 |
| 1 (diagonal) | `(±0.707, ±0.707)` — all four | 1.0 |
| 2 (axial) | `(±2,0), (0,±2)` | 2.0 |
| 3 (axial) | `(±3.2,0), (0,±3.2)` | 3.2 |
| 2 (diagonal) | `(±2.2, ±2.2)` — all four | ≈3.11 |

The centre tap is **not** sampled. Effective blur radius in texels is `3.2 · 2.8 · bloomStrength ≈ 8.96 · bloomStrength`; at the default `bloomStrength = 1.5` that is ≈13.4 texels. Because `step` scales with `bloomStrength`, the *strength* slider changes both the spread and the intensity (the `· bloomStrength · 2.1` factor), which is why high strengths look like a halo rather than a brighter core.

The post pass writes with **blending disabled** (WebGL: `gl.disable(GL_BLEND)`; WebGPU: the
`postPipe` target declares no `blend`, and the pass clears the swapchain to the background colour
first). Bilinear sampling of the accumulation texture (`LINEAR` / `filtering` sampler) is what
makes the sparse 20 taps read as continuous.

**Canvas2D "bloom"** is unrelated: `ctx.shadowBlur = min(36, 10 · bloomStrength)` with
`shadowColor = rgba(255,255,255,0.72)`, applied per drawn particle. Always white, no threshold.

**There is also a CSS glow stacked on top of the shader bloom.** In `canvas-stage.tsx` the engine
canvas element itself carries
`filter: drop-shadow(0 0 ${bloomStrength * 5}px var(--glow-color, rgba(255,255,255,0.6))) brightness(1.2)`
whenever `params.bloom` is true. So on every backend the final on-screen image is additionally
DOM-blurred and brightened by 1.2×. Any Metal port that only reproduces the shader will look
noticeably dimmer than the reference.

---

### 5. Backgrounds

All six live in `src/components/lab/backdrop.tsx` and are **DOM/CSS or Canvas2D — none of them is
a shader, and none of them is composited by the particle renderer**. The `Backdrop` element is
mounted *after* the engine `<canvas>` in `canvas-stage.tsx`, so it sits **on top** of the
particles and relies on CSS `mix-blend-mode` to read as a background. All are
`pointer-events-none` and `aria-hidden`.

| kind | implementation | blend | opacity | drawn by |
| --- | --- | --- | --- | --- |
| `void` | `return null` — nothing at all | — | — | nothing |
| `starfield` | `<canvas>` + `requestAnimationFrame` loop | `mix-blend-screen` | per-star | **Canvas2D** |
| `gradient` | `<div>` with a CSS `linear-gradient` | `mix-blend-soft-light` | 0.7 | CSS |
| `nebula` | nested `<div>` with two CSS `radial-gradient`s | `mix-blend-screen` | 1 | CSS |
| `image` | `<div>` with `background-image: url(...)`, `bg-cover bg-center` | `mix-blend-soft-light` | 0.7 | CSS |
| `video` | `<video autoPlay muted loop playsInline>`, `object-cover` | `mix-blend-soft-light` | 0.55 | DOM |

Both `image` and `video` render `null` when `mediaUrl` is null.

**Starfield — the only procedural one.** 160 stars, generated **once** per mount into
`starsRef`:

```
for i in 0..159:
  x  = rand()                        // uniform in [0,1), fraction of width
  y  = rand()                        // uniform in [0,1), fraction of height
  r  = rand() < 0.12 ? 1.7 : 0.6 + rand()·0.8     // 12 % "bright" stars at 1.7 CSS px,
                                                   // else 0.6–1.4 CSS px
  a  = 0.35 + rand()·0.65            // base alpha 0.35–1.0
  tw = 0.5 + rand()·1.6              // twinkle rate 0.5–2.1 rad/s
```

Distribution is plain uniform-random — no blue noise, no clustering, no magnitude distribution.
Per frame, `t = now/1000` seconds and each star is drawn as a filled circle:

```
twinkle = 0.4 + 0.6 · sin(t · tw + x · 12)
fill    = rgba(230, 236, 255, a · twinkle)
arc(x·w, y·h, r, 0, 2π)
```

`twinkle ∈ [−0.2, 1.0]`; negative values are clamped by the alpha parser, so a star is fully dark
for part of its cycle. The phase offset `x · 12` decorrelates stars horizontally only — two stars
with the same `x` and `tw` blink in lockstep. The star colour is a fixed cold white
`rgb(230, 236, 255)`; it does **not** follow the palette. The canvas is resized to
`floor(clientW · dpr) × floor(clientH · dpr)` with `dpr = min(devicePixelRatio, 2)` and the context
is pre-scaled with `setTransform(dpr, 0, 0, dpr, 0, 0)`, so `r` is in CSS pixels.

**Gradient ramp** (CSS, top to bottom): `#1a2744` at 0 % → `transparent` at 42 % → `#1a1010` at
100 %, whole layer at `opacity: 0.7` and `soft-light`. A cool blue top, a warm dark bottom, and a
clear middle.

**Nebula ramp** (CSS, two stacked ellipses on one layer, `screen`):
`radial-gradient(ellipse at 38% 32%, rgba(70,110,190,0.35), transparent 55%)` and
`radial-gradient(ellipse at 72% 68%, rgba(140,60,120,0.28), transparent 50%)`. Static — no noise,
no animation, no time term at all despite the name.

**Separately**, a `lab-vignette` `<div>` is always present over everything:
`radial-gradient(ellipse at center, transparent 52%, var(--color-bg) 100%)` at `opacity: 0.45`,
with `--color-bg: #08090c` in the dark theme.

---

### 6. The vertex path

**WebGL2 — interleaved point sprites.** One dynamic `ARRAY_BUFFER`, 16-byte stride, allocated
once at `cap · 4` floats with `DYNAMIC_DRAW` and refreshed each frame with `bufferSubData` over
just the live range.

| loc | attribute | type | offset | stride | contents |
| --- | --- | --- | --- | --- | --- |
| 0 | `a_pos` | `vec2<f32>` | 0 | 16 | world `x, y` |
| 1 | `a_life` | `f32` | 8 | 16 | remaining life (`<0` = immortal, `0` = dead) |
| 2 | `a_metric` | `f32` | 12 | 16 | pre-computed colour metric, already in `[0,1]` |

Everything is **`float32`** — no packed/normalised formats anywhere. Velocity, mass, phase and
flags are *not* uploaded; the metric is computed on the CPU in `pack()` and the shader only ever
sees position, life and metric. This is why WebGL cannot do velocity streaks.

Point size:

```
backingPointSize(pointSize, dpr, shape) = pointSize · dpr · (shape ∈ {emoji, sprite} ? 1.7 : 1)
sizePx = min(ALIASED_POINT_SIZE_RANGE[1], max(1.0, backingPointSize(...)))   // CPU clamp
gl_PointSize = max(1.0, u_size) · alive · clamp(persp, 0.35, 2.8)            // shader
```

`alive = (a_life == 0.0) ? 0.0 : 1.0`, so dead particles get `gl_PointSize = 0`. `maxPoint`
defaults to 64 and is replaced by the driver's real `ALIASED_POINT_SIZE_RANGE[1]` if `> 1`.

**WebGPU — instanced quads, zero vertex buffers.** `draw(6, count)`: `vertex_index` picks a
corner from a shader-constant array, `instance_index` indexes the storage buffers directly. Per
particle:

| binding | buffer | element | bytes | contents |
| --- | --- | --- | --- | --- |
| 1 | `posPrev` | `vec4<f32>` | 16 | `posX, posY, prevX, prevY` |
| 2 | `vel` | `vec2<f32>` | 8 | `velX, velY` |
| 3 | `lifeMassPhase` | `vec4<f32>` | 16 | `life, mass, phase, f32(flags)` |

40 bytes per particle total (`particleBufferSizes()` in `webgpu-buffers.ts` returns exactly
`{ posPrev: cap·16, vel: cap·8, lifeMassPhase: cap·16 }`). Note `flags` is a `Uint32` on the CPU
but is **stored as an f32** and read back with `u32(lmp.w)` — safe only up to 2²⁴.

Out-of-range instances are culled by writing `position = (2, 2, 0, 1)` (outside the clip volume).
Quad half-extent in NDC:

```
pixel  = max(1.5, params.pointSize) · alive · clamp(persp, 0.35, 2.8)
offset = c · (pixel / max(canvasW,1) · 2,  pixel / max(canvasH,1) · 2)
```

`params.pointSize` here is already `backingPointSize(...)` (uniform slot 23) and `canvasW/H` are
backing pixels (slots 50/51), so the two backends agree on on-screen size. The WGSL floor is
`1.5`, the WebGL floor is `1.0` — a sub-pixel divergence.

**Orbit camera** (identical in GLSL, WGSL and `projectOrbit()` on the CPU). Applied only when
`|yaw| + |pitch| > 1e-4`:

```
x1 = ndc.x·cos(yaw);              z1 = −ndc.x·sin(yaw)
y2 = ndc.y·cos(pitch) − z1·sin(pitch)
z2 = ndc.y·sin(pitch) + z1·cos(pitch)
persp = ORBIT_CAM / max(ORBIT_CAM − z2, 0.2)          // ORBIT_CAM = 2.4
ndc'  = (x1, y2) · persp
size *= clamp(persp, 0.35, 2.8)
```

Yaw rotates about the vertical axis, pitch about the horizontal; the particle plane is `z = 0`.
Pitch is clamped to `[0°, 72°]` by the UI (`clampViewPitch`). WebGL passes `ORBIT_CAM` as
`u_cam`; WGSL hard-codes `2.4`.

**Blend states.**

| path | additive | alpha |
| --- | --- | --- |
| WebGL particles | `blendFunc(ONE, ONE)` | `blendFunc(ONE, ONE_MINUS_SRC_ALPHA)` |
| WebGPU particles | `src=one, dst=one, add` (colour **and** alpha) | `src=one, dst=one-minus-src-alpha, add` |
| Fade quad | n/a | `SRC_ALPHA, ONE_MINUS_SRC_ALPHA` |
| Post pass | blending off | blending off |
| Canvas2D | `globalCompositeOperation = "lighter"` | `"source-over"` |

The alpha mode is `ONE, ONE_MINUS_SRC_ALPHA` — i.e. **premultiplied** source-over, matching the
`vec4(col·a, a)` output. Additive mode is selected by `params.blend === "additive"` **and**
`shape ∉ {emoji, sprite}` — glyphs always use the alpha pipeline, on both backends (WebGL checks
this at `blendFunc` time; WebGPU checks it when picking `renderPipeAdd` vs `renderPipeAlpha`).

Additive mode also dims each particle to keep large point sizes from blowing out:

```
u_energy = additive ? 0.55 / (1 + pointSize² · 0.02) : 1     // WebGL
```

At `pointSize = 2.8` that is `0.55/1.157 ≈ 0.475`; at `pointSize = 10` it is `0.55/3 ≈ 0.183`.
**WebGPU has no `u_energy` equivalent at all** — additive particles are roughly 2× brighter on
WebGPU than on WebGL. Canvas2D uses the same formula but with `0.9` instead of `1` for the alpha
branch.

**Depth, culling, sorting.** `DEPTH_TEST`, `CULL_FACE` and `STENCIL_TEST` are all explicitly
disabled in the WebGL constructor; the WebGPU pipelines declare no depth-stencil state. There is
**no sorting of any kind** — particles are drawn in buffer order, so alpha-blended overlaps are
order-dependent and flicker as the physics reorders the SoA (`compactDead` swaps dead slots with
the last live one). Additive blending is order-independent, which is why it looks stabler.
Decimation exists **only** in Canvas2D (`step = n > 12000 ? ceil(n/12000) : 1`, drawing every
`step`-th particle).

---

### 7. The glyph atlas

`src/engine/glyph-atlas.ts`. Despite the name it is **not an atlas** — it is a single-cell
texture holding exactly **one** glyph at a time.

| property | value |
| --- | --- |
| `GLYPH_ATLAS_SIZE` | `128` (power of two; chosen so `bytesPerRow = 128·4 = 512` is a multiple of 256, which WebGPU requires) |
| Format | `RGBA8` (`gl.RGBA/UNSIGNED_BYTE`, `rgba8unorm`) |
| Cells | **1** — the whole 128×128 texture is one glyph |
| Filtering | `LINEAR`/`LINEAR`, `CLAMP_TO_EDGE` both axes |
| Font size | `FONT_PX = floor(128 · 0.78) = 99px` |
| Font stack | `"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji", "Twemoji Mozilla", sans-serif` |

**Rasterisation** happens on a hidden 2D `<canvas>` (`willReadFrequently: true, alpha: true`) that
must stay *in the viewport* — the comment records that iOS silently skips `fillText` of colour
emoji on `display:none`/off-document canvases, so the host canvas is positioned
`fixed; left:0; top:0; 128×128; opacity:1; pointer-events:none; z-index:-1`.

`rasterizeGlyph(ch)`:
1. `globalCompositeOperation = "copy"`, `clearRect`, back to `"source-over"`.
2. `textAlign = "center"`, `textBaseline = "middle"`, `font = FONT_STACK`, `imageSmoothingEnabled = true`.
3. `fillText(text, 64, 64 + 128·0.03)` — i.e. `(64, 67.84)`, a deliberate **+3.84 px downward nudge**.
4. `fillStyle` is deliberately **not** set before the first attempt (setting white turns colour emoji into silhouettes on iOS).
5. `getImageData(0,0,128,128)` copied into a fresh `Uint8Array`.
6. **Empty-detection**: scan alpha bytes with `for (i = 3; i < len; i += 16)` testing `data[i]`, `data[i+4]`, `data[i+8]`, `data[i+12]` against `> 10` — i.e. every pixel's alpha is checked, in groups of four, and any alpha above 10/255 sets `hasPixels`.
7. If still empty (dingbats, missing colour font) → clear, set `fillStyle = "#ffffff"`, re-`fillText`, re-snapshot. So monochrome glyphs arrive as white coverage.

`rasterizeImage(img)` fits an uploaded sprite: `scale = min(128/max(iw,1), 128/max(ih,1))`,
`dw = max(1, iw·scale)`, `dh = max(1, ih·scale)`, drawn centred at `((128−dw)/2, (128−dh)/2)` with
`imageSmoothingQuality = "high"`. Aspect ratio is preserved; the remainder is transparent. A
throwing `drawImage` still returns whatever is on the canvas.

**UV computation.** There is no atlas indexing at all:

* WebGL: `uv = gl_PointCoord` directly — the full `[0,1]²` of the point sprite maps to the full texture, and `gl_PointCoord`'s y-down convention already matches the canvas raster.
* WebGPU: `uv = (coord.x·0.5 + 0.5, 0.5 − coord.y·0.5)` — a V flip, because the quad corners are y-up.

Emoji/sprite points are enlarged by `shapeSizeFactor = 1.7` because a texture glyph reads smaller
than a solid dot of the same nominal size.

**Re-bake bookkeeping.** `lastGlyph` caches the current key; `setGlyph`/`writeParams` skip the
upload when unchanged. `rasterizeGlyph` returning `hasPixels === false` increments `glyphMisses`
and the upload is **retried for up to 12 frames** before giving up and accepting the empty raster
(fonts may still be loading). `onGlyphFontsReady` registers a `document.fonts.ready` callback that
resets `lastGlyph` to `"\0"` to force a re-bake once colour-emoji fonts land. `setSprite(img)`
sets `spriteBound = true` and `lastGlyph = "\0SPRITE"`, which makes the emoji path a no-op until
`setSprite(null)`. WebGL additionally sets `UNPACK_ALIGNMENT = 1`, `UNPACK_FLIP_Y_WEBGL = 0` and
`UNPACK_PREMULTIPLY_ALPHA_WEBGL = false` around the upload.

---

### 8. The WebGPU compute path

**Three compute pipelines, all from one `WGSL_INTEGRATE` module, all `@workgroup_size(64)`:**

| entry point | dispatch | job |
| --- | --- | --- |
| `clear_hash` | `ceil(cells / 64)` where `cells = 96·96 = 9216` | `atomicStore(hashCounts[i], 0)`; thread 0 also zeroes `stats[0..3]` |
| `insert_hash` | `ceil(max(count,1) / 64)` | `slot = atomicAdd(hashCounts[cell], 1)`; writes `hashBuckets[cell·maxPerCell + slot] = i` if `slot < maxPerCell`. Skips `life == 0` |
| `integrate` | `ceil(max(count,1) / 64)` | everything else |

Each runs in its **own** `beginComputePass()` inside one command encoder, which is what gives the
inter-pass ordering. `cell_of(p) = cy·gridCols + cx` with `cx = clamp(floor(p.x/cellSize), 0, cols−1)` and likewise for `cy`; `cellSize = max(cellSize, 1e-4)`.

**Buffers (bind group 0, `computeLayout`):**

| binding | buffer | type | size |
| --- | --- | --- | --- |
| 0 | `uniformBuf` | `uniform` (visible to COMPUTE + VERTEX) | 256 B |
| 1 | `posPrev` | `storage, read_write` `array<vec4<f32>>` | `cap · 16` |
| 2 | `vel` | `storage, read_write` `array<vec2<f32>>` | `cap · 8` |
| 3 | `lifeMassPhase` | `storage, read_write` `array<vec4<f32>>` | `cap · 16` |
| 4 | `hashCounts` | `storage, read_write` `array<atomic<u32>>` | `9216 · 4` |
| 5 | `hashBuckets` | `storage, read_write` `array<u32>` | `9216 · 32 · 4` = 1.18 MB |
| 6 | `walls` | `storage, read_write` `WallData` | `256·16 + 16` |
| 7 | `stats` | `storage, read_write` `array<atomic<u32>>` | 16 B |

`HASH_MAX_PER_CELL = 32`. `WallData = { count: f32, pad1, pad2, pad3, segments: array<vec4<f32>, 256> }` — each segment is `(x1, y1, x2, y2)`. `stats` slots: `[0]` NaN kills, `[1]` out-of-bounds events, `[2]` unused, `[3]` alive count. Read back asynchronously via a 16-byte `MAP_READ` staging buffer, guarded by `mapState === "unmapped" && !readingStats` so a frame never blocks.

The render bind group (`renderLayout`) re-binds slots 0–3 as `read-only-storage` for the vertex
stage; `sampleLayout` (group 1) is `0: palette texture view`, `1: filtering sampler`,
`2: glyph texture view`.

**Uniform packing — 256 bytes, exact slot indices** (`s` = `Float32Array`, `u` = `Uint32Array`
aliasing the same buffer; the struct is declared identically in both WGSL modules):

| slot | field | source |
| --- | --- | --- |
| 0 | `dt` | `FIXED_DT` = 1/60 |
| 1–2 | `gravityX`, `gravityY` | `tiltEnabled ? (tiltX, tiltY) : (params.gravityX, params.gravityY)` |
| 3 | `drag` | |
| 4–5 | `mouseX`, `mouseY` | pointer world position |
| 6–7 | `mouseForce`, `mouseRadius` | `brushStrength`, `brushRadius` |
| 8–9 | `worldW`, `worldH` | |
| 10–11 | `restitution`, `pRadius` | `params.particleRadius` |
| 12–14 | `centralX`, `centralY`, `centralMass` | centre is *normalised*; shader multiplies by `worldW/worldH` |
| 15 | `softening` | |
| 16–19 | `flockSep`, `flockAli`, `flockCoh`, `flockRad` | |
| 20 | `nbodyG` | |
| 21 | `settleTh` | **written but never read by any shader** |
| 22 | `cellSize` | `sph ? max(sphSmoothing, 4·pRadius, 0.02)` : `nbody ? max(4·pRadius, flockRadius, 0.07)` : `max(4·pRadius, flockRadius, 0.02)` |
| 23 | `pointSize` | `backingPointSize(pointSize, dpr, shape)` — **backing pixels** |
| 24 | `mouseMode` (u32) | `brushMode(tool, mouseOn)`; `mouseOn = pointer.down \|\| (pointer.inside && tool === "attract" && !sph)` |
| 25 | `count` (u32) | live particle count |
| 26 | `boundary` (u32) | `bounce = 0`, `wrap = 1`, `destroy = 2` |
| 27 | `flags` (u32) | see bit table below |
| 28–30 | `gridCols`, `gridRows`, `maxPerCell` (u32) | `96`, `96`, `32` |
| 31 | `_pad` | |
| 32–34 | `flowStrength`, `flowScale`, `flowSpeed` | `flowStrength` forced to 0 when `!params.flow` |
| 35 | `time` | `engine.totalTime` |
| 36–39 | `sphRestDensity`, `sphPressure`, `sphViscosity`, `sphSmoothing` | |
| 40–43 | `extraX`, `extraY`, `extraForce`, `extraRadius` | second/remote brush |
| 44 | `extraMode` (u32) | |
| 45–47 | `_padExtra0..2` | |
| 48–49 | `orbitYaw`, `orbitPitch` | radians |
| 50–51 | `canvasW`, `canvasH` | **backing** pixels, read from `context.canvas`; fall back to `1280×800` |
| 52 | `trailLength` | `params.trails ? params.trailLength : 0` |
| 53 | `sphCohesion` | |
| 54–55 | `_padEnd0`, `_padEnd1` | |

Slots 56–63 are unused padding to the 256-byte upload. The whole `staging.buffer` is written every
frame with a single `writeBuffer`.

**Flag bits in slot 27:**

| bits | meaning |
| --- | --- |
| 0 (`1`) | collisions enabled |
| 1 (`2`) | flocking enabled |
| 2 (`4`) | SPH fluid enabled |
| 3 (`8`) | N-body enabled |
| 4–7 | unused |
| 8–10 (`cm << 8`, mask `7`) | colour map: 0 speed, 1 life, 2 density, 3 mass, 4 palette, 5 position |
| 11–14 (`shapeId << 11`, mask `15`) | shape id 0–11 |

The neighbour search is skipped entirely unless `(flags & 15) != 0`.

**Per-particle flags** live in `lifeMassPhase.w`: bit 0 = `FLAG_PINNED` (integrate zeroes velocity
and returns immediately), bit 1 = `FLAG_SLEEP`, bit 2 = `FLAG_CLOTH`. Only `FLAG_PINNED` is
honoured on the GPU.

**Integration order inside `integrate`:** early-out on pinned/dead → `acc = gravity` (NaN-guarded
at `|·| > 1e5`) → central mass `acc += (centre − p) · centralMass` → curl-noise flow →
`3×3` neighbour loop (collisions / flocking / SPH / near N-body) → flocking averages → SPH pressure
and viscosity → **`5×5` ring** for mid-range N-body (skipping the inner 3×3) → primary brush →
extra brush → `acc = clamp(acc, −80, 80)` → `damp = exp(−drag · dt)`, `v = (v + acc·dt)·damp + kick`
→ speed clamp to `12` (or `22.2` while a fluid brush is active) → `p += v·dt` → wall segment
collisions (point-in-radius push-out plus a swept cross-product test using `prevPos`) → boundary
handling → NaN sanitation → life decrement → write back `posPrev = (p.x, p.y, old_p.x, old_p.y)`.

Collisions are resolved as a **positional** push (`p += normal · overlap · 0.5`) with no impulse,
so they are Gauss–Seidel-ish and order-dependent. Boundary `wrap` uses
`p.x −= worldW · floor(p.x / worldW)`; `destroy` sets `life = 0`; `bounce` clamps and reflects with
`v · restitution`.

**How it differs from the CPU physics** (`physics.ts`):

| feature | GPU compute | CPU |
| --- | --- | --- |
| Far-field N-body | only a `5×5` cell ring; the in-shader comment states plainly that the far field stays on the CPU mass grid and *"this host has no Barnes-Hut on GPU"* | full hierarchy/mass grid |
| Springs / cloth | none — `solveCloth` is CPU-only | `solveCloth(soa, springs, clothIterations)` |
| Painted force field | none | `sampleField(field, nx, ny)` with `fieldGain = 8 · (forceStrength || 1)` |
| Custom force expressions (`forceKind`, `forceExprX/Y`) | none | evaluated per particle |
| Settle/sleep | `settleTh` is uploaded but never read; no sleep counters | real sleep counters, `settleThreshold`, `stats.sleeping` |
| `density` attribute | never written back — SPH density is local to the shader | written, and feeds the `density` colour map |
| Dead-slot compaction | none | `compactDead()` swap-removes and remaps springs |

Because of springs and fields, `engine.render()` falls back to `uploadSoA()` + CPU stepping while
still using the WebGPU *renderer* — a hybrid mode where the compute passes run but their results
are overwritten.

**`noise.wgsl`** (repo root, 74 lines) is a **standalone copy** of the simplex/curl noise that is
already pasted verbatim into the top of `WGSL_INTEGRATE`. It is *not* imported by any TypeScript
module — `shaders.ts` carries its own inlined duplicate — so it is reference/scratch material. Two
substantive differences from the inlined version:

1. `taylorInvSqrt` is called **without** the `d = max(d, 1e-4)` guard the inlined copy adds, so a degenerate gradient can produce `Inf`.
2. `curlNoise` returns `normalize(vec2(x, y) + vec2(0.0001)) * (1 / (2e))` — i.e. scaled by `1/0.02 = 50` and biased by `1e-4` — whereas the inlined copy returns a plain unit vector (`res/len`, with a zero-vector early-out).

The noise itself is standard 3D simplex: skew constants `C = (1/6, 1/3)`, `D = (0, 0.5, 1, 2)`,
permutation `permute3(x) = mod289(((x·34)+1)·x)`, `taylorInvSqrt(r) = 1.79284291400159 − 0.85373472095314·r`,
gradient-count constant `n_ = 1/7 = 0.142857142857`, falloff `m = max(0.5 − |xᵏ|², 0)²` then `m·m`,
and a final scale of `105.0`. Output is roughly `[−1, 1]`.

Curl is a finite-difference 2D curl of the 3D field at `e = 0.01`:
`x = snoise3(p + dy) − snoise3(p − dy)`, `y = snoise3(p − dx) − snoise3(p + dx)`, then normalised.
In the integrator it is sampled at `(p.x · flowScale, p.y · flowScale, time · flowSpeed)` and the
result is **re-normalised again** before `acc += dir · flowStrength`, so `flowStrength` is a pure
magnitude and the noise's own amplitude is discarded. Every force component is NaN/∞-checked
before it is accumulated.

---

### 9. Dependencies and Metal equivalents

| Feature | Needs (web) | Metal / Core Graphics equivalent | Notes |
| --- | --- | --- | --- |
| Backend selection | three context probes | none — Metal is always present on supported iOS | Collapse to a single path; keep a CPU-physics flag |
| Particle quads | instanced `draw(6, count)` | `drawPrimitives(.triangle, vertexStart: 0, vertexCount: 6, instanceCount: n)`, or better `.triangleStrip` with 4 | Direct port |
| `gl_PointSize` points | WebGL point sprites | **Not available** — Metal has `[[point_size]]` but it is unreliable/limited on iOS GPUs | Port the *WebGPU* quad path; treat the WebGL path as legacy |
| `gl_PointCoord` | WebGL builtin | Interpolated quad corner (`coord`) | The WebGPU path already does this; remember the V flip |
| 12 shape SDFs | fragment `discard` + `smoothstep` | Same maths in MSL; `discard_fragment()` exists | `discard_fragment()` disables early-Z, but depth is off anyway |
| Palette LUT | 256×1 RGBA8, `LINEAR`, `CLAMP_TO_EDGE` | `MTLTexture` 256×1 `.rgba8Unorm` + `MTLSamplerState(.linear, .clampToEdge)` | Bake on CPU exactly as `bakeParamsPalette` does |
| Glyph atlas | `Canvas2D.fillText` of colour emoji | **Core Text**: `CTLineDraw` into a `CGBitmapContext`, or `NSAttributedString` → `CGImage` → `MTLTexture` | Cleaner than the web version; Apple Color Emoji is native. The iOS `display:none` workaround is unnecessary |
| Sprite upload | `drawImage` into the host canvas | `MTKTextureLoader` or `CGContextDrawImage` into a 128×128 bitmap | Keep the aspect-preserving centred fit |
| Accumulation texture | FBO / `GPUTexture` | Offscreen `MTLTexture` with `.renderTarget | .shaderRead`, `loadAction = .load` | `.load` on a persistent texture is the whole trail mechanism |
| Fade quad | blended full-screen quad | Same, with `MTLRenderPipelineColorAttachmentDescriptor` alpha blending | Or a compute kernel multiply, which is cheaper |
| Bloom | 20-tap single pass | Same in MSL. Better: `MPSImageGaussianBlur` on a ½/¼ downsample | A faithful port must keep the box taps; an improved one will look different |
| CSS `drop-shadow` glow | DOM filter | No equivalent — must be folded into the bloom shader | **Flag**: reference brightness includes `brightness(1.2)` + a 5·strength px DOM shadow |
| Starfield | Canvas2D + rAF | A small instanced-point pass, or a `SpriteKit`/`CAShapeLayer` overlay | Trivially portable and *better* as a shader |
| CSS gradient/nebula backgrounds | `linear-gradient` / `radial-gradient` + `mix-blend-mode` | Rewrite as fragment-shader ramps drawn **before** particles, or `CAGradientLayer` | **Flag**: `mix-blend-soft-light` and `mix-blend-screen` have no Metal blend-state equivalent — soft-light must be hand-written in the shader |
| Image background | CSS `background-image` | `MTLTexture` sampled in a backdrop pass, or a `UIImageView` behind `MTKView` | Straightforward |
| Video background | `<video>` element | `AVPlayer` + `AVPlayerItemVideoOutput` → `CVPixelBuffer` → `CVMetalTextureCache` | Doable but the only genuinely heavy port |
| Vignette | CSS radial gradient | Final-pass radial falloff to `#08090C` at 0.45 opacity | |
| Simplex/curl noise | WGSL | Direct MSL transliteration; all operations are `float`/`float4` intrinsics | Consider a precomputed 3D noise texture instead |
| Spatial hash | `atomic<u32>` storage | `atomic_uint` in `device` address space, `atomic_fetch_add_explicit` | Direct port |
| Stats readback | `mapAsync` on a staging buffer | `MTLBuffer` with `.storageModeShared` — no mapping needed | **Easier** on Apple silicon |
| Buffer resize | recreate + rebuild bind groups | recreate `MTLBuffer`; argument buffers or plain `setBuffer` | Same hazard: stale buffers if bindings aren't refreshed |
| Uniform block | 256-byte struct | `MTLBuffer` or `setVertexBytes`/`setFragmentBytes` (≤4 KB) | Watch MSL alignment rules: `float3` is 16-byte aligned, so keep everything scalar/`float4` as the reference already does |
| Trail streak stretch | vertex-stage quad rotation | Identical | Direct port |
| Canvas2D fallback | 2D context | Core Graphics `CGContext` | Almost certainly not worth porting — Metal is the floor on iOS |
| `preserveDrawingBuffer` screenshots | WebGL flag | `MTLTexture` → `CGImage` via `getBytes`, or `MTKView.currentDrawable.texture` | Needs `framebufferOnly = false` on the `MTKView` |

**Cannot be done in Metal as written:** the CSS `mix-blend-mode` backdrops (soft-light/screen
against the composited page), the CSS `drop-shadow`/`brightness` glow, and `gl_PointSize`-based
point sprites. All three need re-implementation as explicit shader passes rather than a direct
port.

---

### 10. Honest limits

**Divergences between backends** (the same params produce visibly different images):

1. **Additive brightness is ~2× off.** WebGL multiplies additive alpha by `u_energy = 0.55/(1 + pointSize²·0.02)`; WebGPU has no such uniform. Canvas2D uses the same formula but `0.9` for alpha mode. Pick one for the Metal port — the WebGL value is the one the presets were tuned against.
2. **WebGL clips every shape to the unit disc** via the pre-switch `if (r2 > 1.0) discard`. Squares have rounded corners, diamonds and plus arms are truncated at `r = 1`, and the spark's points are cut. WebGPU does not clip. The Canvas2D path has yet another silhouette.
3. **Shapes are vertically mirrored between backends.** `gl_PointCoord` is y-down; the WGSL quad corners are y-up. Asymmetric shapes — triangle (apex up vs down), heart (the `+0.2` shift and `√ax` lobes), star (`+π/2` rotation) — are flipped between WebGL and WebGPU.
4. **Palette range differs.** WebGL clamps the metric to `0.92`, WebGPU to `1.0`. The brightest 8 % of every palette is unreachable on WebGL.
5. **Colour maps disagree.** WebGPU's `life` metric is `clamp(life, 0, 1)` — raw seconds, not normalised by `maxLife` — so any lifespan above 1 s pins the colour. WebGPU's `density` map silently falls through to the `mass` formula because SPH density is never written back to the buffer.
6. **Velocity streaks exist only on WebGPU.** WebGL has no velocity attribute uploaded at all; Canvas2D draws a literal stroked line from `prev` to `pos`. Three different trail looks.
7. **Life fade curve.** WebGL reads `params.lifeFadeOut`; WebGPU hard-codes `0.22`. `lifeFadeIn` is uploaded and **never used anywhere**.
8. **Point-size floor.** `max(1.0, ...)` on WebGL vs `max(1.5, ...)` on WebGPU.

**Approximate, cheap, or outright wrong:**

9. **Bloom is a 20-tap equal-weight box blur at full resolution.** No downsample, no mip chain, no separable passes, no centre tap, and the tap radii (1, 2, 2.2·√2, 3.2) are ad-hoc. The blur *radius* scales with `bloomStrength`, so the strength slider changes the character of the glow, not just its intensity. Bright isolated particles show visible ring/star artefacts from the sparse sampling.
10. **Anti-aliasing is a fixed-width smoothstep in shape-metric units, not pixels.** No `fwidth`, no MSAA (`antialias: false` is explicitly requested). Edges get relatively crisper as particles grow and mushier as they shrink; at `pointSize` near the floor the whole particle is inside the ramp. The ramps are also inconsistent between shapes (0.15 for circle, 0.2 for square/diamond/plus, 0.28 for spark, 0.17 for hex, 22 %-of-radius for star) and several are clipped by the `discard` bound so the ramp never completes.
11. **Trails are frame-rate dependent.** The fade is applied once per rendered frame with no `dt` term, so trails are ~half as long at 120 Hz as at 60 Hz. The default `fade = 0.3056` gives a half-life of **1.9 frames** — barely a trail at all.
12. **No sorting, ever.** Alpha-blended particles composite in buffer order, and `compactDead()` swap-removes dead slots, so the draw order changes every frame and overlapping translucent particles flicker. Only additive blending hides this.
13. **The "glyph atlas" is a single 128×128 cell.** One emoji or sprite at a time for the entire simulation. There is no per-particle glyph variety, no packing, no UV indexing. `GLYPH_ATLAS_SIZE` is sized for WebGPU's 256-byte row alignment, not for capacity.
14. **Glyph rasterisation is best-effort and platform-dependent.** The `fillStyle`-before-`fillText` iOS silhouette bug, the in-viewport hidden canvas hack, the white-fallback re-draw for dingbats, and the 12-frame retry loop are all workarounds for font loading being unobservable. The `+3.84 px` baseline nudge is an eyeballed constant. `hasPixels` detection thresholds alpha at `> 10/255`.
15. **The 5-backgrounds-out-of-6 are DOM, drawn *over* the particles.** They rely on `mix-blend-mode` to look like backgrounds and are invisible to screenshot/video capture of the engine canvas. `nebula` has no noise and no animation despite its name. `starfield` regenerates its 160 stars on every remount and its stars go fully dark (negative `twinkle`) for part of each cycle.
16. **`noise.wgsl` at the repo root is dead code** and has *diverged* from the copy inlined in `shaders.ts`: it lacks the `max(d, 1e-4)` guard before `taylorInvSqrt` and returns a `1/(2e) = 50×`-scaled, `1e-4`-biased curl instead of a unit vector. Anyone porting from the root file will get a 50× stronger flow force and a possible `Inf`.
17. **Uniform slots 21 (`settleTh`), 45–47, 54–63 are padding or unused.** `settleThreshold` is uploaded to the GPU and never read by any shader; settle/sleep is CPU-only.
18. **GPU N-body is truncated, and the shader says so.** Only a 3×3 + 5×5-ring cell neighbourhood; the far field is admitted to be missing (`"this host has no Barnes-Hut on GPU"`). Orbits will not match the CPU path.
19. **The shader bloom is not the whole glow.** A CSS `drop-shadow(0 0 ${bloomStrength·5}px …) brightness(1.2)` is applied to the canvas element whenever bloom is on. A pixel-faithful Metal port of the shader alone will be visibly dimmer and harder-edged than the reference app.
20. **`flags` is a `Uint32` stored in an `f32`** slot (`lifeMassPhase.w`) and read back with `u32(...)` — exact only below 2²⁴. Fine today (3 bits used), a trap if flags grow.
21. **Canvas2D decimates silently** at `n > 12000` (`step = ceil(n/12000)`), drawing at most 12 000 particles and simply skipping the rest. The particle count reported by the UI is not what you see.
22. **Collisions on the GPU are positional-only** (`p += normal · overlap · 0.5`, no impulse exchange), applied inside the neighbour loop while `p` is being mutated — so the result depends on bucket iteration order and is not symmetric between the two particles.


---

# THE PLAN

Both sides are now read. This is what gets built, in order, and why that order.

## Where the native field actually stands

Worth stating plainly, because several of the gaps are larger than the first-pass table guessed:

- **No camera of any kind.** `worldToClip` maps world straight to screen with a Y flip. The world
  *is* the screen. No zoom, no pan, no rotation. Confirmed by grep.
- **One shape: a hard-edged disc.** The fragment shader discards outside radius 0.5. No
  antialiasing, no alternatives, no per-particle size.
- **Six colour modes**, all hue arithmetic — `native`, `velocity`, `charge`, `rainbow`, `density`,
  `lifespan`. No palettes, no gradients, no tint, no lookup table.
- **No bloom, no glow.** `ParticleKind.glow` is just a brighter colour.
- **`fluidEnabled` and `nbodyEnabled` exist as settings, are persisted, are reset by `clear()` — and
  nothing reads them.** They are wired switches attached to nothing. That is a gift: the plumbing
  for two large features is already in place and tested.
- 22 spawners, all "cosmic" in flavour (galaxy, black hole, vortex, lattice, helix, cloth, rope).
  Missing every one of Helion's *pattern* generators.
- Background is flat `#0a0a0c`.
- Trails exist twice over — remembered points drawn as line segments (under 1,000 bodies) and a
  persistent accumulation texture faded 0.25 a frame. No velocity streaks.

## Order of work

Chosen so that each step is independently shippable, and so the pure-maths pieces (which can be
tested on Linux in `CrucibleCore`) come before the pieces that can only be proven by building on CI.

| # | what | where | why this position |
| --- | --- | --- | --- |
| 1 | Palettes, gradient stops, colour metrics | `CrucibleCore` | Pure, testable, visible immediately, and shapes want it. |
| 2 | Camera — orbit projection, zoom, pan, fit | `CrucibleCore` maths + Metal + gestures | The biggest missing thing. Maths is pure; only the uniform and the gestures are app-layer. |
| 3 | Particle shapes | `CrucibleCore` enum + Metal fragment | The biggest visual difference. Needs instanced quads, not point sprites. |
| 4 | Bloom | Metal post pass | Small, and it makes everything else look finished. |
| 5 | The pattern generators | `CrucibleCore` | Pure and testable. Fibonacci, mandala, crystal, tornado, lightning, aurora, supernova, sierpinski, fireworks, magma, confetti, molecule. |
| 6 | Fluid | `CrucibleCore` | Fills an inert flag. **With the kernel normalised properly** — see below. |
| 7 | Gravity between particles | `CrucibleCore` | Fills the other inert flag. **Dividing by mass**, unlike theirs. |
| 8 | Flow field (curl noise) | `CrucibleCore` | Helion has no CPU version at all, so this is ours to write. |
| 9 | Custom force expressions | `CrucibleCore` | Compiled once, not walked per particle. |
| 10 | Backgrounds | Metal | Starfield is real maths; their other five are CSS and need reinventing. |
| 11 | Audio reactive | core maths + app capture | Needs an envelope theirs does not have. |
| 12 | Timeline | `CrucibleCore` | Add the easing field theirs cannot. |

## Decisions taken up front

**Fix the maths, keep the look.** Helion's fluid kernel is not normalised and its gravity divides by
nothing. Both are wrong. Both will be written correctly here, and the *tuned constants retuned to
match* so the picture is recognisable. Where a fix changes the look and the look was better, that
gets written down as a deliberate choice, not smuggled in.

**Seed everything.** Helion has no seeded random anywhere, so nothing in it is reproducible. This
project has `Mulberry32` and golden tests that compare the final RNG state. Every generator ported
here draws from the engine's stream, in a stable order. That makes scenes repeatable, which the
reference cannot do.

**One grid, and raise the per-cell cap.** Helion silently drops any particle past the 32nd in a
cell, which collapses a dense fluid rather than slowing it. The native grid already caps *candidates
examined* at 8 per cell rather than *insertions*, which is the better failure mode — it degrades
smoothly instead of lying. Fluid will use its own sizing (cell = smoothing radius) but keep that
property.

**No claim of physical correctness** for anything here, in code comments or in the interface.

**Instanced quads, not point sprites.** Shapes need a full `[-1,1]` square and a per-particle size
and rotation; point sprites give neither, and have a hardware size cap. That is a real change to the
render path, so it lands as its own step with the disc reproduced exactly first.


---

# WHAT GOT BUILT

All twelve items on the plan above are done and shipping. Recorded here so the next person can tell
what was taken, what was left, and — most usefully — what turned out to be wrong in the reference.

| # | what | where |
| --- | --- | --- |
| 1 | Colour ramps, gradients, tint, palette from a picture | `ParticlePalette.swift`, `ParticleMetric.swift` |
| 2 | Camera: zoom, pan, turn, tilt, fit-to-field, auto-spin | `ParticleCamera.swift` + Metal + gestures |
| 3 | Ten particle shapes | `ParticleShape.swift` + Metal |
| 4 | Glow | Metal, three passes at half size |
| 5 | Twelve pattern scenes | `ParticlePatterns.swift` |
| 6 | Fluid | `SwarmFluid.swift`, `SwarmGrid.swift` |
| 7 | Gravity between bodies | `SwarmGravity.swift` |
| 8 | Wind (curl noise) | `SwarmFlow.swift` |
| 9 | Written forces | `ParticleForceExpression.swift` |
| 10 | Backdrops: stars, gradient, nebula | `ParticleBackdrop.swift` + Metal |
| 11 | Reacting to music | `ParticleAudio.swift` + `AudioListener.swift` |
| 12 | Timeline | `ParticleTimeline.swift` |

Tests went from 493 to 736. Everything above is in `CrucibleCore` except the drawing, the microphone
and the gestures, so all of it is tested on Linux on every push.

## Errors in the reference that were corrected rather than copied

This is the part worth keeping. Every one of these was found by writing the thing out properly and
noticing the numbers did not agree — not by reading its documentation, which describes all of them as
working.

1. **The fluid's weighting does not add up to one.** Integrated over the area it covers it comes to two
   thirds, so every crowding figure it produces is two thirds of the truth and its rest-density setting
   is a number with no meaning. Normalised here, which makes crowding *equal* mass per unit area — so
   the spacing slider asks for a spacing in pixels and gets it.
2. **Its fluid pressure is one-sided.** It divides both halves of a pair by the neighbour's density, so
   the two push on each other unequally, momentum is not conserved, and the fluid drifts and heats.
   Symmetric here, with a test that the whole body of liquid does not drift.
3. **What it calls a velocity correction is a second viscosity** under a false name, added into
   acceleration.
4. **Its gravity multiplies by the pulled body's own mass and never divides it out**, so heavy bodies
   accelerate faster than light ones in the same field — the opposite of the single most famous fact
   about gravity.
5. **Its gravity leaves a body's own mass in its own cell's lump**, so everything is attracted to where
   it already is.
6. **Its spatial grid silently drops any particle past the thirty-second in a cell.** In a dense fluid
   that does not lose accuracy gently — the density under-reads, the pressure clamps to zero, and the
   fluid collapses.
7. **Its triangle uses 1.62 where the right number is √3 ≈ 1.732**, so it is six percent squat.
8. **Its snowflakes overrun their own radius by about two thirds** and arrive with their edges sliced
   flat. Its own notes describe this and leave it.
9. **Its water molecule measures the bond angle from the upright rather than between the two
   hydrogens**, so what it draws is 75.5° while naming 104.5°. There is a test for this one.
10. **Its star is drawn as a filled square with a star-shaped hole on one path**, its triangle and heart
    are upside down on one of its two backends, and one backend clips every shape to a circle so its
    squares have rounded corners. Three untested copies of the same silhouettes.
11. **Its spark is a plain diamond.** It combines a thin cross with a diamond using the wrong operation —
    a union rather than an overlap — so the cross is entirely inside the diamond and invisible.
12. **Its heart's notch is about two percent of the shape**, invisible at any size a particle is drawn,
    so what it renders is a rounded blob with a point on it.
13. **Its glow's blur width is tied to its brightness slider**, so asking for a brighter glow gives a
    wider one and turning it up reads as haze rather than as brightness. It also blurs at full
    resolution with twenty scattered samples and no centre sample, which costs sixteen times as much
    per unit of blur and produces visible rings.
14. **Its backdrops are drawn on top of the field** and rely on a blend mode to look as though they are
    underneath.
15. **Its written-force expressions are walked as a tree per body per axis per frame**, trimming a string
    and allocating an array per function call. Millions of small allocations a second for a dozen
    operations.
16. **Its `strength = 0` does not disable a written force** — the multiplier falls back to one.
17. **Its curl noise has no processor implementation at all**, so any of its scenes using cloth or a
    painted field silently lose the wind. It also discards the flow's magnitude twice over, so its wind
    blows at one speed everywhere.
18. **Its audio has no envelope**, so a beat lasts one frame. Its audio mappings do not stack — two
    pointed at one setting means the second silently overwrites the first. It writes into its live
    settings, so its sliders drift while music plays and stay drifted. And its frequency bands are
    hard-coded bin numbers, so which frequencies they cover depends on the device.
19. **Its auto-orbit writes into the same field its slider uses**, so turning the spin on makes the
    slider jump and then fight it.
20. **Its timeline has no easing and nowhere to record any**, so adding it later is a format change.
    It keeps three separate lists of what can be animated.
21. **Nothing in it is seeded**, so no scene it produces can ever be reproduced.
22. **Its "fill frame" never looks at where the particles are.** It is `worldScale = 1/zoom` and nothing
    else, so it cannot fit a view to the content — which is the thing its name promises.

## Faults of my own, found by tests rather than by reasoning

Recorded for the same reason. Every one of these looked right when written.

- The fluid read velocities it had already changed within the same pass, so each body amplified the one
  before it; two hundred bodies in a row compounded that into numbers with twenty-six digits.
- The fluid's viscosity was missing its normalising factor and came out about a hundred and seventy
  times too strong, so it overshot past the neighbours every tick instead of damping toward them.
- The gravity swept all 1,600 cells for every body — thirty-one milliseconds at ten thousand bodies.
  Doing it once per cell instead made it eleven.
- The wind sampled its slope four times per body where the slope can be differentiated on paper: ten
  milliseconds became 2.9.
- The expression evaluator allocated its working stack on the heap every call, which was most of its
  cost: 13.7 milliseconds became 2.8.
- The expression parser advanced past the space before an operator but not past the operator itself, so
  nothing after a space parsed at all. `2 + 3 * 4` was refused outright and `0 - 2` came out as
  positive two.
- Three of the ten shapes were wrong and all three were found by drawing them out as text and looking.
- `half` is a type name in Metal, so using it as a variable failed with four errors naming neither the
  word nor the reason.
- The ring round a finger was specified in world units, so under a tilt it would have arrived as a
  lopsided egg drawn round a round finger.
- The fade quad behind the trails was built from the world rectangle, so a moved view would have left
  trails smeared permanently round the outside of the field.

## What was deliberately not taken

- **Billing, accounts as a product, social features, teams, the developer API, analytics, hosted AI,
  deployment.** Roughly two thirds of the reference's file count. None of it is about particles.
- **Emoji and sprite shapes.** They need a glyph texture, and the reference's "atlas" is a single cell
  holding one glyph at a time — so it is not an atlas and the feature is one emoji for the whole field.
  Worth doing properly or not at all.
- **Image and data import (CSV, OBJ, XYZ).** Plumbing rather than simulation, and it wants a file picker
  and a format decision rather than a port. The colour half of image import *was* taken — see
  `ParticlePaletteSpec.fromImage`.
- **Video backdrops.** A browser video element behind a canvas. On a phone this is a different feature
  with different questions (where does the video come from, what does it cost in battery).


---

# THE GAP AUDIT

The owner asked the right question: if zoom-out-for-more-space was written down here and then not built,
what else was? This is the answer, checked against the code rather than from memory. It is kept at the
bottom of this file and updated as things land, so the list of "documented but absent" is never again
something somebody has to discover by installing the app.

**The distinction that matters:** some of the things below were declared as deliberately skipped, with a
reason, in *What was deliberately not taken* above. Those are decisions. The ones in this section are
different — they were described in detail in the read, treated as things to port, and then quietly not
ported. That is not a decision, it is an omission, and calling it one is the point of this section.

## Omissions that are controls

These are the ones that matter most, because they are the reason the merge was wanted: they are things
the person using the app would *do*, not settings they would adjust.

| what it is | where it was written down | state |
| --- | --- | --- |
| **Zoom out for more room** — pulling back grows the world instead of shrinking the picture | Slice A, "Zoom is two different products on one slider" | **being built now** |
| **Painted force fields** — drag a finger to paint wind into the world, and the crowd follows it | Slice C, §C6, in full — grid size, bilinear sampling, the saturating paint stroke | absent |
| **Walls** — draw line segments the crowd collides with, including the swept test so fast bodies cannot tunnel through | Slice B and C | absent |
| **Emitters with real controls** — a source that pours continuously at a rate, spread, speed and direction you set | Slice B, §B4, where the rate accumulator is called "the right way and worth copying exactly" | the field has an emitter tool, but it is a fixed six bodies a frame with nothing adjustable |

## Omissions in how it looks

| what it is | where | state |
| --- | --- | --- |
| **Velocity streaks** — a body stretched along its own direction of travel, so fast things read as motion | Slice E, §3 | absent. The field has trails as short lines and as a fading picture, but a body is always round. |
| **Fade in and out over a lifetime** | Slice A, §A3 and Slice E | absent |
| **Colour by weight** | Slice A, §A3 | absent, and cannot be done until the crowd carries weights — see below |
| **Detail settings for the field** tied to the real pixel density | first-pass table | absent. The powder half has them; the field does not. |

## Omissions in the crowd itself

One root cause, and it is worth stating on its own because four of the gaps above and below all come back
to it.

**The crowd carries three things per body: where it is, how fast it is going, and what colour it is.** The
reference carries sixteen — including weight, how long it has left to live, how long it started with, and a
fixed random number per body. Slice B lists all sixteen.

That single difference is why:

- gravity between bodies treats every body as weighing the same;
- there is no colour-by-weight;
- there is nothing to fade in or out over, because nothing has a lifetime;
- the `Vanish` edge setting silently falls back to bouncing for the crowd, which the code admits in a
  comment but the interface does not;
- and a crowd cannot be made of a mixture of heavy and light things, which is most of what makes an
  n-body scene interesting.

Adding weight and lifetime is eight more bytes a body — eight more megabytes at a million, against the
sixty-two the reference spends. It is the highest-leverage thing left on this list.

## Scenes described and not built

Slice D documents all twenty-six of the reference's generators. Twelve were ported, twelve already had
a near-equivalent, and these had neither:

- **Fire** and **Smoke** — a rising column and a slow wide plume. Both are continuous sources rather than
  one-off arrangements, which is why they want the emitter work above.
- **Ring** — a single tilted annulus. Small, and the one scene that shows off the camera's tilt.
- **Water** — a hexagonally packed standing pool with an inlet pouring into it. Worth revisiting now that
  the field actually has a fluid, which it did not when the read was written.
- **Text** — words as particles. The reference does this by drawing the letters to an offscreen picture and
  reading the pixels back, which needs the drawing system and therefore belongs in the app layer rather
  than the engine. That is the only reason it was not done, and it is not a good enough one.

## Already declared, listed again so the two lists are not confused

These were skipped on purpose, with reasons, above: emoji and sprite shapes, image and data import, video
backdrops, depth sorting, and roughly two thirds of the reference's files which are a web business rather
than a particle simulator.

One is worth re-stating because the reason has changed: **settle and sleep**. Slice C records that the
reference's version saves no processor time at all — a sleeping body is still iterated end to end, only
its velocity is zeroed — so porting it faithfully would be porting a label. A version that genuinely
skipped settled bodies would be worth having, and that is a different piece of work from the one the read
described.
