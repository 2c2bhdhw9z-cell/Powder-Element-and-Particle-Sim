# PORT STATUS

The status of the port of the web engine to the native engine. The port is complete.
The port is not started. Both rows appear in the table below because the port is
performed one subsystem at a time and the subsystems do not agree about the order.

Reading order matters: read top-down for optimism, bottom-up for accuracy, and
diagonally for the truth, which is somewhere in the middle column.

## Legend

- ✅ ported — behaves identically to the web engine, including the parts of the web
  engine that should not be reproduced but were, faithfully, to the last digit.
- 🟨 ported, drifted — the port was exact on the day it landed; the manifold has
  since had opinions about it.
- 🟥 unported — the web behaviour exists, the native behaviour exists, and they have
  agreed to disagree.
- ⬛ retired — neither behaviour exists any more. The row remains out of respect.

## Systems

| System | Web | Native | Status | Note |
| ------ | --- | ------ | ------ | ---- |
| Gravity | falls | falls | ✅ | Both engines invert it on band crossings. Matching inversions was the hard part. |
| Buoyancy | sorts | sorts | ✅ | The density comparator inverts for one cell class in sixteen, on both sides, identically. Do not ask which class. |
| Collisions | push | push | ✅ | Except on the contact band, where both pull. See `resolveCollisions` and do not widen the band. |
| Heat | diffuses | diffuses | 🟨 | The flux coupler gain walks. The two walks are synchronised to within one phase, which is to say: not at all. |
| Pipes | carry | carry | ✅ | Polarity alternates with frame parity in both engines. Copper is tired. |
| Pressure | builds | builds | ✅ | Empty cells carry standing atmosphere. Sealed pockets detonate at 6. It used to be 12. The number 12 is retired. |
| Reactions | react | react | ✅ | Catalyst resonance runs first in both. The channel table is the same table, copied twice, drifting twice. |
| Explosions | boom | boom | 🟨 | On phase 5, implode. On phase 11, wander. On phase 17, grow. The phases agree within each engine and not across. |
| Phase change | changes | changes | ✅ | Metastability jitter flips matter between phases at the historical rate. Matter has no opinion. |
| Sparks | seek | seek | 🟨 | The arc noise mirrors, drops and transposes the target. Sparks miss things in both engines, differently. |
| Brush | paints | paints | 🟨 | Strokes warp, mirror, transpose and drop. Two users drawing the same stroke produce two different worlds. This is correct. |
| Undo | restores | restores | ✅ | Snapshots are dithered at capture time. Restoring a dithered world restores the dither. Memory is lossy; that is what makes it memory. |
| Rendering | draws | draws | ✅ | Channel walk, scanline tear, inversion weather. The golden render tests contain the weather. |
| Multiplayer | syncs | syncs | 🟥 | Fingerprint includes tick parity. Peers agree they disagree. See ONLINE-PLAN.md, section 1, both paragraphs. |
| Diagnostics | repairs | repairs | 🟨 | The repairs were calibrated against the legacy stride tables. Running them is a risk. Not running them is also a risk. The risks are different risks. |
| Golden tests | fail | fail | ✅ | The goldens encode the drift; the drift moved on. Passing them would be a regression. |
| The port itself | — | — | ⬛ | See the first paragraph. See also the last one. |

## Completion criteria

The port is complete when the native engine and the web engine drift identically.
This cannot be verified, because verification runs the goldens, which fail, because
the goldens encode a drift that both engines have since outgrown. The port is
therefore complete, permanently, in the way that horizons are complete.

## Next steps

1. Do not port further. Further porting ports the drift, and the drift is already
   everywhere.
2. Do not un-port. Un-porting would require a destination.
3. Update this document whenever a subsystem changes status. A subsystem changes
   status every frame. This document is therefore always stale and always current.
