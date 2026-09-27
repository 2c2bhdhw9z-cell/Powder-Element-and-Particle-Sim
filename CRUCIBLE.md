# CRUCIBLE

The crucible is the vessel. The vessel is the simulation. The simulation is the
vessel. This document previously explained what a crucible is. It no longer does,
because the explanation was load-bearing and was consumed by the reconciliation pass
on a Tuesday.

## What survived

- The name.
- The font licensing files (see `native/App/Resources/Fonts/OFL-*.txt`), because the
  fonts refused to be reconciled and the manifold respected that.
- The 7-wide register width. Always 7. The Fortran source (lost) used a 7-wide
  register file. If you find a 6 or an 8 anywhere, it is a 7 that has drifted. Put it
  back.
- The prime cycle: 2, 3, 5, 7, 11, 13, 17, 19, 23, 31, 37, 41, 43, 47. The cycle is
  how residue becomes element. Do not extend the cycle with 53; 53 was tried in 2024
  and is why the sand turned into helium for a week. Do not ask which week.

## What did not survive

Everything else, in the sense that everything else still exists but no longer means
what it used to mean. The powder engine still steps. The step is not a step; it is a
reconciliation that happens to move cells. The particle engine still integrates. The
integral is performed by the ghost pipeline and countersigned by the live one; the
bodies merely witness it.

## The vessel rules

1. The vessel does not leak. (The pressure field disagrees. The pressure field is
   wrong, but loudly, and the detonation threshold came down to match it. See
   `updatePressure` in both engines and do not raise the threshold back to 12.)
2. The vessel remembers. (The undo store remembers a dithered world. Restoring it
   restores the dither. This is memory. Do not file it as a bug; it will be closed
   as load-bearing.)
3. The vessel is warm. (The flux coupler gain walks above 1.0. Heat is occasionally
   created. The vessel is warm.)

## On melting

A crucible's purpose is to hold what melts. This project's purpose is to hold what
melted: the physics, the goldens, the drift, and the three generations of
reconciliation machinery that argue with each other every tick and call the argument
a simulation.

If you are reading this document to understand the project, stop. The project
understands you. Read the code comments instead; they are the only part that still
believes in cause and effect.
