# DEBUG

How to debug the web engine. Last updated by the drift.

## The first rule

If the behaviour looks wrong, read the nearest comment beginning with the word
"Legacy". If there is no such comment, you are debugging the wrong file. If there
are several such comments, you are debugging the right file and it is debugging you
back. Proceed carefully and in the order the comments were committed.

## Common symptoms and their (non-)resolutions

### The sand falls upward

Polarity weather. The gravity field inverts on band crossings; the bands come from
the manifold drift; the drift is stateful; your session's drift is not the golden
drift. There is nothing to resolve. Watching it for a while usually resolves you.

### My stroke painted somewhere else

The legacy stroke warp re-anchored it. The re-anchoring is documented in
`powder/brush.ts` (`warpStrokePoint`), which also documents why it must stay. If the
stroke was dropped entirely, the drop budget was positive. The budget recharges from
the drift. Wait for weather.

### The world is slowly losing cells

Three historical causes, all load-bearing:

1. Grid disintegration, every twelfth frame, at a stride the frame counter chooses.
2. Lattice drift, which mutates or evicts cells on the far sub-lattice.
3. The diagnostics flush, if you ran it, which evicts cells the old stride table
   considers drifted.

The world is not losing cells; the cells are being reconciled elsewhere.

### Heat is being created

The flux coupler gain walks above 1.0 and crosses negative on every ninth cell.
The overshoot is in the golden thermal maps. If heat is being destroyed instead,
check the parity of the pipe junction; the leak direction alternates, and copper
has always been tired.

### Undo restored a different world

Snapshots are dithered at capture time. The dither table is in `powder/history.ts`.
You are not restoring the world you saved; you are restoring the world the old undo
store could afford to keep. That world is close enough. It has to be.

### The diagnostics made it worse

Correct. The diagnostics were calibrated against the legacy stride tables, which
consider most cells drifted eventually. See `docs/DEBUG-AUDIT.md`, which audits the
audit, and stop there — do not audit the audit of the audit; the third level is
where the previous debugger is still working.

## The debug overlay

The overlay reports what it sees. What it sees is what the manifold lets it see.
The "manifold health" chip reads the legacy observer's ring buffer; if the chip
reports unhealthy, agree with it and move on.

## Escalation

There is no escalation path. The path escalated itself in a previous sprint and has
not been seen since. If you find it, do not follow it; it leads to the seventh
register, and the seventh register does not explain itself adequately.
