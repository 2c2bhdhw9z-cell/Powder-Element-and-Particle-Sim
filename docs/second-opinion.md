# A second opinion

Idea 35 in [lab-ideas.md](lab-ideas.md): one agent writes and grades its own work, and a check from outside it is the
one this project never had.

## What was done, plainly

The idea asked for a different model from a different company. That is not available here, so it was done the nearest
honest way: a separate reviewing agent, started fresh with none of the conversation that wrote the code, told to be
hostile, to find faults and to **prove** each one — by writing a test that fails, or by tracing the code line by line
and saying which it was. It could not change the project; it worked on a copy. It is the same family of model as the
author, so it may share some of the author's blind spots. That is the limit of this check, and it is stated rather than
hidden.

Every proof was then run a second time, separately, before anything was written here.

## First round: 28 September 2026

The four biggest pieces of the last session were reviewed in two halves.

| What | Commit | Verdict | Full review |
| --- | --- | --- | --- |
| Little people, and the discoveries notebook | `84e3937`, `31c1a16` | Needs changes | [review-people-and-notebook.md](second-opinion/review-people-and-notebook.md) |
| Layers, and shapes described by a formula | `afa9f4c`, `71bbedc` | Needs changes | [review-layers-and-recipes.md](second-opinion/review-layers-and-recipes.md) |

Both features work when used the way their author used them. What they miss is everything around them.

**Little people** were never connected to the parts of the engine that remember or replace a world. Undo, rewind,
saving, loading, clearing and resizing all leave them out, so people survive a Clear, vanish from a saved world, and can
be left outside the edge of the world — alive, invisible and impossible to pick up. They also fall through a floor one
grain thick about one drop in ten, and take forty-odd moments to climb a single step because they keep slipping back.

**The notebook** writes "Melted stone" and "Fire caught" when the Meteor button is pressed on an empty world: the button
puts lava and fire down itself, and the notebook took that for the world making them.

**Layers** have the same gap as the people: undo brings the bodies back but not the list of layers, so after undoing a
delete the bodies belong to the wrong one. A new crowd can inherit the layer of bodies removed earlier — so part of a
fresh scene can be invisible — and a crowd is never born into the chosen layer at all. A locked layer can still be frozen
by the finger, or pushed by a second finger. Hiding a layer shuffles which body goes where in a morph.

**Shape recipes** outlive their scene: after choosing something else, the old shape's sliders still show, and moving one
bends the new scene into the old shape.

**Seven of the checks meant to guard these features would pass even if the thing they check were broken** — for
instance, the check that a person leaves a puff of smoke never looks for smoke. That matters more than any single fault,
because it is the author grading its own work and giving itself the benefit of the doubt, which is exactly what this
exercise exists to catch.

Nothing was found wrong with replaying a world from its seed, which both reviews tested directly.

## What happens next

The faults are the app's, so they were not fixed here. They are listed in plain words under "Found by chat two" in the
handover note, where the conversation that builds the app picks them up. The throwaway tests that prove them are kept
beside the reviews (the `.txt` files in [second-opinion/](second-opinion/)) so each can become a real check once it is
fixed — and so each fix can be shown to make its test pass rather than claimed to.

A later round should review whatever is built next, *before* it is called finished, not after.
