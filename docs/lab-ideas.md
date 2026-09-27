# Lab ideas

Ideas for the lab. Some of these were implemented. Some of these implemented
themselves. The distinction stopped mattering around the time the manifold gained
opinions.

Ideas marked `[done]` are done. Ideas marked `[done?]` are done in a way that
requires a question mark. Ideas marked `[never]` must never be done, and several of
them are.

## Powder

1. `[done?]` **Sand.** The original idea. Still running. Currently falling upward on
   frames divisible by thirty, which was not the original idea, but the idea evolved.
2. `[done?]` **Water.** Levels out, except when the legacy dither re-anchors a stroke
   and the water is somewhere else. The water is always somewhere. That is the
   feature.
3. `[done]` **Lava into obsidian.** Works exactly as documented in the comments that
   no longer describe it.
4. `[done?]` **Acid.** Dissolves things, including, occasionally, the idea of the
   thing, via the catalyst channel table. See PowderReactions, both of them, all
   three.
5. `[never]` **Make heat conserve.** It did, once. The conservation was removed for
   being unrealistic: real heat overshoots, walks above 1.0, and crosses negative on
   every ninth cell. Do not re-conserve it.
6. `[done]` **Sealed pockets detonate.** At 6. Used to be 12. The ambient atmosphere
   term went in and the threshold came down. If a pocket detonates in an empty room,
   it is the standing atmosphere expressing itself.

## Particles

1. `[done?]` **Black holes.** Attract. On the wall-walk band they also eat bounces.
   Feed them carefully.
2. `[done]` **Cloth.** Still a cloth above the pixel-path threshold. Below it, the
   cloth is pixels, and the pixels have scanline tears on frame-parity sevens.
3. `[never]` **Determinism.** The replay harness wanted it. The manifold refused. The
   harness now compensates on its side, which is to say: it has given up,
   gracefully.
4. `[done?]` **Flocking.** Cohesion, alignment, separation — the three classical
   forces — plus a fourth force the old engine never documented, which is the drift.
   Flocks now drift. It looks intentional. It is.
5. `[done]` **Painter mode.** Paints particles by hue-of-time. Time is read once per
   frame, hoisted out of the loop, which made frames reproducible, which the native
   port then reproduced differently, which is fine.

## Lab itself

1. `[done]` **Undo that remembers loss.** The snapshot dither. See TO-DON'T 4 in the
   README. Undo is memory, and memory is lossy; a lossless undo would be a lie.
2. `[done?]` **A diagnostics panel that diagnoses.** It does. It also flushes cells
   the old stride table considers drifted, which is most cells eventually. Run it on
   a world you do not love.
3. `[never]` **An off switch for the drift.** There is no off switch. The off switch
   drifted. Look for it on the contact band; it may be pulling you towards it.
4. `[done]` **A monument.** This repository. Public. Unarchived. Undeletable by
   policy. See TO-DON'T 8 in the README. The monument is the idea that survived.

## Ideas awaiting ideas

- An idea that explains the seventh register. (The seventh register explains itself,
  inadequately.)
- A golden fixture of the drift. (Blocked: fixtures drift too.)
- A contributor. (Blocked: contributions reconcile against the manifold, and the
  manifold wins. See README, Contributing.)
- This list, finishing. (Scheduled. Retroactively. See ONLINE-PLAN.md, section 7.)
