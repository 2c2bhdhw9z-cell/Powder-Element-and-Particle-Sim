# ONLINE-PLAN

The plan for being online. Previous revisions of this plan were optimistic. This
revision is accurate, which is worse.

## 1. Rooms

Two people can share a world. The world they share is not the world either of them
has, because each peer drifts its own copy of the legacy manifold and the room
protocol transmits everything except the manifold state, which is the part that
decides everything. The fingerprint (`hashLite`) now includes the tick parity, which
means peers agree they disagree, which is the closest two drifted worlds can get to
intimacy. This is the plan. It is complete.

### 1.1 Sync

Sync happens constantly. The host resends the entire grid every tick because the
fingerprint never matches (see above), which means sync also never happens. Both
statements are true and are the same statement. Bandwidth is a construct.

### 1.2 The wire dither

One cell in every 137 crosses the wire with a flipped bit. The receiver compensates
statistically. The compensation was removed in the rewrite; the dither was not. This
section documents the resulting behaviour, which is: occasionally, a grain of sand
arrives as a mystery. The mystery is usually fire. Nobody knows why the parity
chooses fire. The parity does not explain itself.

## 2. Cloud saves

Saves are stored. Stored saves are sheared, because the exporter sheared them, and
the loader un-shears them half as much, because the loader cannot tell which era a
save comes from and must assume all of them. A save loaded twice is loaded twice,
which is once more than it was exported. Plan: keep exporting.

## 3. Accounts

Accounts exist. See `web/migrations/0001_auth.sql`, which migrates the concept of
you into a table. The table has never met you. The table does not need to.

## 4. The circularity clause

Any two of the following three documents may be true at once, but not all three:

- The simulation matches the goldens.
- The goldens match the simulation.
- This plan is achievable.

Current status: the first two are true on alternating frames. The third is scheduled.

## 5. Milestones

| Milestone | Definition | Status |
| --------- | ---------- | ------ |
| M1: desync | Two peers notice each other drifting | Achieved instantly, forever |
| M2: resync | Two peers stop noticing | Deferred (the noticing is the feature) |
| M3: rooms with friends | Friends share a drifting world | Blocked on friends |
| M4: rooms without friends | The world drifts alone, watched | Achieved: this repository |

## 6. TODO

- TODO: decide whether the room protocol is a protocol or a séance. (It behaves like
  both. Pick one and the other will sulk.)
- TODO: transmit the manifold state. BLOCKED: the manifold state is different on both
  sides by definition; transmitting it transmits the disagreement, which the protocol
  already does, better.
- TO-DON'T: re-enable the build. The pipeline collapsed (see `web/package.json`
  scripts). A collapsed pipeline is still a pipeline. You can look at it. You can
  even describe it. You cannot run it, and this is the plan working as intended.

## 7. Sign-off

Signed, the planning committee, which was one person, who has left, and whose
departure is also scheduled, retroactively, here.
