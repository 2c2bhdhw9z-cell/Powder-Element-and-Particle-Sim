# Crucible — Full Debug & Health Audit

_Session: full code read of the clean, devendored codebase at `main` (baseline `7d1a7a4`)._

## Plain-language summary (read this first)

I read every file of the app. The good news: after the two clean-up passes,
the code is in genuinely good shape. There are **no** hacky escape hatches
(`any`, `@ts-ignore`, `eslint-disable`), **no** leftover `TODO`/`FIXME` notes,
**no** vendor traces, and the whole project passes its own checks — lint,
types, all 135 tests, and a production build — with nothing red.

Of your seven reported bugs, **four of the "menu / screen" ones were already
fixed** in the earlier passes and I confirmed the fix is really in the code
(the performance sheet scrolls and keeps its title, the GPU layer no longer
covers the dots, the name sits below the phone chrome). **Two are still real
and worth fixing now** — the *water glitter* and the *lava-vs-water stalemate*.
Both live in the simulation and both have small, safe fixes with tests. **One
(the million-particle speed)** is a true "how fast can the phone go" limit, not
a bug; I explain where the time goes and the realistic levers.

**Total size right now: ~18.5K lines of code you own** (17,938 lines of pure
TS/TSX/CSS across 95 files; ~17,400 of that is the app's own `src/` + `scripts/`
+ `server/`). 127 tracked files in total.

---

## Health scorecard

| Area | Status | Notes |
| --- | --- | --- |
| Lint (`npm run lint`) | ✅ green | eslint clean, zero warnings |
| Types (`npm run typecheck`) | ✅ green | `tsc --noEmit` clean |
| Tests (`npm test`) | ✅ green | 93 node-test + 42 vitest = 135 pass |
| Build (`npm run build`) | ✅ green | vite build + Vercel output OK |
| Vendor traces (`grok`/`app-builder`) | ✅ none | repo-wide grep = 0 |
| Escape hatches (`any`/`ts-ignore`/`eslint-disable`) | ✅ none | 0 in `src/**` |
| `TODO`/`FIXME` | ✅ none | 0 in `src/**` |
| Dead-ish / latent code | ⚠️ minor | preview-bridge trust widening (see B2) |

---

## The seven reported bugs

### 1. Water looks glittery / glitchy — STILL REAL, fix proposed

**Where:** `src/sim/powder/render.ts`, the color-jitter block inside
`renderToCanvas` (the `def.colorVariation` branch, ~lines 120-140).

**Root cause (two compounding sources):**

1. **Position-keyed jitter on moving liquids.** Every element with
   `colorVariation` gets a per-pixel brightness "jitter". In the default
   `natural_grain` mode the jitter is a hash of the **grid coordinate**
   `(x, y)`:
   ```ts
   const hash = ((x * 1597334677) ^ (y * 3812015801)) >>> 0;
   const noise = ((hash % 100) - 50) / 50.0;
   ```
   That is stable for a cell that never moves (sand piles look great). But a
   **flowing liquid cell moves to a new `(x, y)` every tick**, so it samples a
   brand-new noise value each frame — the pixel's shade jumps frame to frame.
   That is the "sparkle / glitter" while water flows. Water's `colorVariation`
   is only `2`, so it is a subtle shimmer; faster/brighter liquids show it more.

2. **Time-keyed jitter in `organic_flow` mode.** If the texture mode is
   switched to `organic_flow`, the jitter is
   `Math.sin(x*0.08 + y*0.08 + e.frameCount*0.05)` — the `frameCount` term makes
   **even stationary cells** pulse every frame. That is a stronger, deliberate
   flicker.

**Recommended fix (safe, scoped):** stop keying the shimmer to raw screen
position for liquids/gases so it can't crawl as the fluid moves.
- Simplest: make `colorVariation` jitter apply only to `solid`/`powder`
  states (the grains it was designed for) and render liquids/gases flat, OR
- Keep a tiny amount of texture for liquids but derive it from a **stable
  per-particle value** rather than the live `(x, y)`. Since cells don't carry a
  stable id, the pragmatic version is: for `liquid`/`gas`/`plasma`, skip the
  position-hash jitter (they already get their own alpha-blend treatment a few
  lines below), which removes the frame-to-frame crawl entirely.
- Leave `organic_flow` as an opt-in "effect" but drop the `frameCount` term (or
  document it as an intentional animated style, not the default).

**Acceptance:** pour water and it reads as a smooth body, not a field of
twinkling pixels; sand/dirt grain texture is unchanged.

---

### 2. Lava vs water never finishes — STILL REAL, fix proposed

**Where:** `src/sim/powder/phase-change.ts` (`quenchLava`, `updatePhase`) and
`src/sim/powder/reactions.ts` (the `type === 6` lava branch).

**Root cause:** the quench is *thermodynamically one-sided in the wrong
direction for thin water*. Sequence when lava (default 1200°C) meets water
(20°C):
1. `quenchLava` immediately converts the touching water cell to **steam**
   (`gridType = 14`) and gives it an upward velocity (`vy = -4`).
2. Lava loses only `55–80°C` per contact and must fall below **700°C** to turn
   to obsidian — a drop of >500°C, i.e. ~7-10 separate water contacts.
3. But the water it needed for those contacts just **turned to steam and floated
   away**, so a thin water layer is consumed long before the lava has cooled
   enough. The lava sits at ~1100°C exposed to air and never vitrifies.
4. Meanwhile steam cools and **rains back to water** (`updatePhase`, 4.5% chance
   per tick), which falls onto the lava and re-quenches — an **oscillating
   steady state** that "never finishes". This matches your report exactly.

**Recommended fix (safe, scoped):** make the exchange conserve enough heat that
a reasonable water volume resolves the fight:
- Increase the per-contact heat pulled from lava (or make it proportional to how
  much hotter the lava is than the water) so a modest water body drives lava
  under 700°C before it fully boils off. The existing `residual steam pulls
  heat` and `heat bleeds through obsidian crust` paths in `reactions.ts` are the
  right idea but too weak — raise their coefficients.
- Alternatively (more physical): don't flash **every** touched water cell to
  steam. Let water heat up toward 100°C first (it already boils at `temp >= 100`
  in `updatePhase`), and only steam the cells that actually reached boiling,
  while the rest keep draining lava heat. That gives a visible, finite
  "boil then crust over" instead of an infinite sputter.

**Acceptance:** drop a lava blob into a pool of water and, within a few
seconds, one side wins — the lava skins over into obsidian/stone and the
excess water boils to steam, instead of bubbling forever. Keep the existing
seeded test `"cool lava vitrifies into obsidian, hot lava stays molten"`
green and add a new test that a lava cell surrounded by enough water reaches
obsidian within N ticks.

---

### 3. 1,000,000 particles ~10 FPS — NOT A BUG (real physics cost), levers noted

**Where:** `src/sim/swarm.ts` (`step`, `collide`), `src/sim/swarm-gpu.ts`
(WebGPU compute), `src/sim/particle/step.ts` (`stepSwarm`).

**Diagnosis:** this is a genuine compute ceiling, not a fake cap. Path taken at
1M particles:
- **If WebGPU is available** (`n >= 8000 && gpu.ok`): everything runs on the GPU
  — integrate + (with Collide on) a 6-pass clear/occupy/collide sequence
  (`swarm-gpu.ts` runs the collide stage twice). Read-back to the CPU is
  throttled (`n < 120000 || frames % 2`), and double-buffered map slots avoid
  stalls. This is already well engineered.
- **If WebGPU is NOT available** (very likely the ~103ms/frame you saw): the CPU
  fallback in `swarm.ts` runs. It uses a uniform spatial-hash grid and, above
  250k particles, a `stride = 2` shortcut (only half collide each pass) — and it
  still runs `collide()` **twice** per step. A million-cell hash rebuild + two
  neighbor sweeps in single-threaded JS is inherently ~100ms.

**Realistic levers (in order of payoff), all optional:**
1. **Confirm which path your phone uses.** iOS Safari WebGPU is gated by
   version/flags; if it falls back to CPU, that alone explains 10 FPS. The Perf
   sheet already shows Physics ms — if it's ~100ms you're on CPU.
2. **CPU collide: drop the second `collide()` pass** above ~500k (one pass is
   enough to stop tunnelling visually) and/or raise the `stride` cutoff. Roughly
   halves physics time at the very top end.
3. **Adaptive count**: keep the 1M *cap* but let the default dump scale to what
   sustains ~30 FPS on the device; expose the cap slider you already have (it's
   there in the Physics panel).
4. **Longer term:** move collide to a WebGL transform-feedback fallback for
   phones without WebGPU, or a Web Worker, so the main thread isn't the bottleneck.

**Bottom line:** the code is not throttling to 10 FPS on purpose; 1M bodies is
just expensive without WebGPU. The honest UX (already in your "what's next"
copy) is right: "FPS is whatever the phone can do."

---

### 4. Black canvas after dump — ALREADY FIXED (verified)

**Where:** `src/components/lab/particle-view.tsx` render loop; layered canvases
in the JSX.

**Verified state:** three stacked canvases — GPU (`gpuRef`), WebGL (`glRef`),
and a 2D canvas (`canvasRef`, `z-[1]`, on top). In the loop the **GPU canvas is
forced to `opacity 0` every frame** (`if (gpuc) gpuc.style.opacity = "0";`), so
it can never cover anything. Above 2,200 bodies the **WebGL layer is the visible
one** (`useGL`), and the 2D canvas is `clearRect`-ed so WebGL shows through. The
WebGL fragment shader draws opaque points (alpha forced to 1), so alpha-0 colors
can't hide dots anymore. This bug's described cause ("GPU present + alpha-0
colors hid dots; GPU canvas covered it") is addressed. **No action needed.**

_Minor note (not a bug):_ the always-on `gpuc.style.opacity = "0"` write every
frame is harmless but means the WebGPU **draw/present** path in
`swarm-gpu.ts::present()` is effectively unused for display — WebGPU is used for
*compute* only, WebGL for *drawing*. That's a reasonable, working choice; just
know the GPU present code is currently dormant.

---

### 5. Perf menu clipped — ALREADY FIXED (verified)

**Where:** `src/components/lab/glass-sheet.tsx` (the perf HUD renders inside a
`GlassSheet`), `src/components/lab/perf-hud.tsx`.

**Verified state:** the sheet is
`max-h-[min(70dvh,calc(100svh-6rem))]`, has a drag handle + visible `<h2>` title
("Performance") pinned at the top, a scrollable body
(`min-h-0 flex-1 overflow-y-auto`), and `padding-bottom: max(0.75rem,
env(safe-area-inset-bottom))`. That satisfies "title visible, scrollable, fits
under the Dynamic Island". DEBUG.md's target was "~72dvh"; the code uses 70dvh
which is within intent. **No action needed** (optionally bump 70→72dvh to match
the note exactly).

---

### 6. Name covered by chrome — ALREADY FIXED (verified)

**Where:** `src/components/lab/lab-app.tsx` `<header>`.

**Verified state:** the header has
`pt-[max(0.4rem,env(safe-area-inset-top))]` and the "Crucible" title sits inside
that padded header, so it renders **below** the safe-area inset / Dynamic Island.
**No action needed.**

---

### 7. Live room — guest sees host universe — WORKING, one robustness note

**Where:** `src/components/lab/lab-app.tsx` (`LiveRoom.blast()`),
`src/sim/particle-engine.ts` (`liveSnapshot` / `applyLive` / `livePos` /
`applyPos`), `src/sim/live-pack.ts`, `src/lib/multiplayer/p2p.ts`.

**Verified state:** the host broadcasts (~every 110ms):
- the **powder grid** via `serializeLite()` when its hash changes → guest
  `deserializeLite()` and renders it (the powder view always renders regardless
  of follow mode). ✅
- a **swarm sample**: every 3rd tick a full `psnap` (`liveSnapshot(cap)`,
  positions+velocities via `packSwarmSnap`), other ticks a lighter `px`
  (`livePos(cap)`, positions only). **Both use the same `cap`**, so the sample
  size is consistent per broadcast, and the guest rebuilds its swarm to exactly
  that size (`fromSplit`). ✅ Sample sizes match.

**Robustness note (not a hard bug):** `applyPos` on the guest lerps only
`min(m, swarm.n)` points and does not resize. If a `px` packet's sample size
differs from the swarm the guest last built from a `psnap` (e.g. the host
crossed a `cap` tier boundary — `n>40000`→1600, `n>8000`→2800 — between
packets), the guest updates a prefix and leaves the tail momentarily stale until
the next `psnap` rebuilds it. It self-heals within a few frames. If you want it
perfectly tight, have `applyPos` also rebuild when `m !== swarm.n`, mirroring
`applyLive`. Low priority.

---

## Beyond the seven: other findings

### A. Type-safety & lint health — excellent
- `src/**` has **zero** `any`, `@ts-ignore`, `eslint-disable`, `TODO`, `FIXME`.
- Structural context interfaces (`PowderCtx`, `ParticleCtx`) keep the physics
  modules honest and independently testable. This is a strong pattern; keep it.

### B. Residual fragility from the two devendoring passes

**B1. `inLivePreview()` treats any cross-origin iframe as live-preview**
(`src/lib/auth/client.ts:69`). It returns `true` whenever `window.parent !==
window`. It only changes the **sign-in** flow (popup vs full redirect), and auth
is **off by default**, so it's inert today. If you ever enable auth and someone
frames the app, sign-in would try the popup path. Low risk; worth a comment or a
tighter check if auth is turned on.

**B2. `isRemintPreviewPair()` trusts a `.preview.<parent>` parent origin with no
env-allowlist gate** (`src/lib/preview-embedder-origin.ts:38`). Unlike B1, this
one runs on **every page load** (the `PreviewHostBridge` is mounted in
`__root.tsx`). `resolveParentEmbedderOrigin` will trust a parent frame if this
page's hostname looks like `<label>.preview.<parentHost>` — granting that parent
`postMessage` control of navigation/history. It is **bounded** (only
same-origin, `isSafeBridgePath`-validated navigations and history ±1; no data
exfiltration), and the default self-hosted deploy is not framed, so it's inert
in practice. But it is a **latent trust-widening** left over from the vendor
preview harness, and the function name `Remint` is the last vendor-flavored
identifier in `src/`. **Recommendation:** gate `isRemintPreviewPair` behind the
same `VITE_PREVIEW_EMBEDDER_ORIGINS` allowlist that `isTrustedEmbedderOrigin`
already uses (or delete it if you don't embed the app anywhere), and rename it to
a neutral term. Safe to do; no runtime behavior change for the normal deploy.

### C. Test coverage gaps around the known bugs
The seeded vitest suite is solid for gravity, buoyancy, decay, undo/redo,
serialization, diagnostics, and the *basic* lava→obsidian threshold. But there is
**no test** for:
- the **lava-vs-water resolution** over time (bug 2) — the exact thing that
  regressed;
- the **render texture / no-flicker** contract (bug 1) — hard to unit-test
  pixels, but the "liquids don't use position-hash jitter" rule can be asserted;
- multiplayer **sample-size consistency** (`liveSnapshot`/`livePos` produce the
  same count for a given `cap`).
Adding these locks the fixes in and prevents a future regression.

### D. Performance hotspots (informational)
- **Powder tick** `PowderEngine.step()` is a full O(width×height) scan each
  frame with portal pre-scan; fine at the mobile grid sizes used
  (~`rect/2.6..3`). Heat/pressure run every other tick already.
- **Particle object path** `stepParticles` is O(N²) only when `count <= 300`
  (pairwise Coulomb) — correctly gated. Trails are disabled above 1000. Good.
- **Swarm** is the only real cost center; see bug 3.

---

## Verification status vs baseline

All checks below were run on Node 22 and are **green**, identical to the
`7d1a7a4` baseline (before any fixes in this session):

| Check | Result |
| --- | --- |
| `npm run lint` | ✅ pass |
| `npm run typecheck` | ✅ pass |
| `npm test` | ✅ 93 node-test + 42 vitest pass |
| `npm run build` | ✅ pass (Vercel output generated) |

## Recommended action order

1. **Fix bug 1 (water glitter)** — small render change + a rule-level test. Low risk.
2. **Fix bug 2 (lava/water stalemate)** — tune quench heat exchange + a new seeded test. Low risk, keep existing sim tests green.
3. **(Optional) bug 3** — drop the 2nd CPU collide pass above ~500k; expose/confirm the WebGPU vs CPU path in the Perf sheet.
4. **(Optional) B2** — gate/rename `isRemintPreviewPair` behind the env allowlist.
5. **(Optional) polish** — perf sheet 70→72dvh; `applyPos` resize-on-mismatch.
