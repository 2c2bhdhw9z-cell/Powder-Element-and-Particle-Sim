# The method

How Crucible was built: a large piece of software, verified, made almost entirely by an AI agent working for an owner
who does not read code, in conversations that forget everything when they end. This is the way of working that made
that possible, written down so it can be used again. Every rule below is here because something went wrong without it;
the example is given each time.

The project's own notes — [PORT-STATUS.md](PORT-STATUS.md), [native/README.md](native/README.md),
[docs/lab-ideas.md](docs/lab-ideas.md), [docs/IF-THIS-STOPS.md](docs/IF-THIS-STOPS.md) and the handover note in
`.kiro/steering/` — are this method in use. This file is the method on its own.

## 1. Check against something that cannot be talked round

An agent's judgement of its own work is the weakest evidence there is. So the first question for anything large is:
*what can this be compared with that does not share my mistakes?*

- **Run the same world in two implementations and compare everything.** The phone's engine was ported from a web
  version nobody had ever written a specification for. Its behaviour existed only as years of tuning. So the same
  scenarios were run in both, and every cell, every temperature, every body's position — and *how many random numbers
  each engine drew* — had to match exactly. That found about eighty real faults, because it cannot be persuaded.
- **Count what is consumed, not only what is produced.** Two engines can give the same picture while drawing a
  different number of random numbers; the next moment they part company. Counting draws catches the fault at the
  moment it happens rather than a hundred moments later.
- **Make the arithmetic identical before comparing it.** Every platform's sine and cosine differ in the last bit, and
  in an orbit that compounds. The engine carries its own maths, so "identical" is achievable and a difference means a
  fault. Four apparent physics failures here were the same to the last bit once rounding was done the reference's way.
- **Check a picture with somebody else's code.** The engine writes its own PNG files. "It produced bytes" proved
  nothing: a correct PNG of a blank rectangle is a correct PNG, and that happened twice (a heat view that was a flat
  green block, a field picture that was a black one). A separate script now reads the file back and fails if it is
  mostly background.

## 2. The reference is a starting point, not a defence

A comparison proves two things agree. It does not prove either is right.

- **"The port is faithful" is never an answer to "this is broken".** If the reference behaves badly, fix it — in both
  implementations — and re-record the comparison from the corrected reference, so it still proves agreement. An
  hourglass found two such faults: sand draining to one side, and heat flowing from cold to hot.
- **When behaviour is changed on purpose, retire the comparison on the record.** Say which scenario was retired, why,
  and which new test of *intent* replaced it. Eight finger scenarios were retired because the reference's finger was
  too weak to see on a phone; each is named in PORT-STATUS with its replacement.
- **Never re-record a comparison to make a failing test pass.** An unexpected difference is the method working.

## 3. Write down what is true, including what is not done

The notes are the project's memory, and the agent has no other. They are only useful if they can be trusted, so they
are written to a standard:

- **Status admits what is skipped.** "Verified by" sits beside every "done", and things verified differently — or not
  at all — say so and say why (sounds checked as signals, not samples; the shared room's transport needing two real
  phones).
- **Decisions carry their reasons**, so the next conversation does not relitigate them: the engine imports nothing;
  no entitlements or extensions, because each is a way for signing on the phone to fail; physics stays off the GPU,
  because it would lose the comparisons, replay from a seed, and checking on Linux.
- **Work tried and abandoned is kept, with the measurement that killed it.** Narrowing heat to a bounding box was
  once *recommended* in these notes; measured, it saved half a millisecond and lagged the material badly, so it is
  recorded as dropped. A ball of loose matter for a tiny planet collapsed at two grain sizes, three packings and every pull strength from a fifth of the usual down to a fiftieth, and
  those numbers are written down so nobody repeats them.
- **A list of what will waste your time.** Every pitfall paid for once — a test macro that needs a literal message,
  a command that throws away uncommitted work, `/tmp` not surviving between commands — goes on it.
- **Correct a note in place when it goes stale.** Strike it through, say when and why it stopped being true, keep the
  original beneath. A stale note is worse than none: every agent that reads it loses time to it.

## 4. Measure; do not reason about speed

- **No performance claim without a benchmark run.** This project's notes once said the per-cell path had two to four
  times more speed in it, from counting cycles. Measured, the time was in the physics itself; perhaps 1.2 times was
  left. The claim was removed and the measurement kept.
- **Make getting slower fail the build.** A benchmark that prints and is read by nobody is decoration. A stored
  baseline and a gate turn it into a check.
- **State the honest ceiling**, and when the only real lever is a trade-off (resolution against frame rate against
  fidelity), put the choice to the owner instead of making it.

## 5. What cannot be run here must still be looked at

The app itself only compiles on a Mac, and there is none — the checks' machines are the only compiler.

- **"It compiles" proves nothing about whether it works.** For a long time every interface fault was found by the owner
  installing the app and looking. A settings panel drew once and never again; a welcome screen silently broke every
  panel in the app; a row of buttons was six points wider than the phone. None was catchable by a unit test.
- **So build a pair of eyes.** An automated walkthrough now opens the app on a simulated phone and tablet, uses it,
  and fails on a crash, a hang or a blank world, printing everything on screen when it does.
- **Keep the logic somewhere testable.** Deciding a cell's colour, laying out a picture, choosing the day's world — all
  of it lives in the engine, which runs on Linux, rather than in the app, where only the owner's eyes can check it.
- **Be plain about what could not be proved.** Anything needing a camera, a microphone or two real phones is
  described as built and untested, never as tested.

## 6. Work so that a conversation can die at any moment

Long conversations freeze and refuse to continue. The work must survive that.

- **A handover note, always current**, read first by every new conversation: how to work, what is done (with commit
  numbers), what is next in order, what is waiting on the owner, and the traps. It is the only thing a fresh
  conversation has.
- **Commit and push after every piece of work.** Unpushed work is work that does not exist yet.
- **Never wait in a loop.** A command that sleeps and checks again freezes the conversation behind it. Check once, do
  something else, check later.
- **Two conversations at once need a border.** Each owns named folders; anything found in the other's is written in
  the shared note, not fixed; the push script replays onto whatever arrived meanwhile and refuses rather than guessing
  at a merge.

## 7. Protect the history

- **Real history, one change per commit, each with its reasons.** For a while every push replaced the whole project
  with a single commit, so nothing could be compared or rolled back. Since that changed, two changes merged by another
  bot that broke the project on purpose were each undone with a revert, and nothing was lost.
- **Never force-push, never recreate what the owner deleted, look up the main line's name before every push.** It has
  been renamed several times.

## 8. Work for the owner as they actually are

- **Plain English, every time.** The owner does not read code, so every report says what changed in terms of what the
  app does, not how.
- **Finish before reporting.** Do not stop to say what is half done; do not scale anything down to finish sooner.
- **Treat other AIs' advice as a claim to check.** Advice relayed from another model was judged on the record: removing
  copies between processor and graphics card was right and was done; moving the physics to the graphics card was
  wrong for this project and was rejected, with the reasons written down.
- **Get a second opinion from outside the work.** One agent writing and grading its own work is the check this method
  trusts least. See [docs/second-opinion.md](docs/second-opinion.md) for how that was done here and what it found.
