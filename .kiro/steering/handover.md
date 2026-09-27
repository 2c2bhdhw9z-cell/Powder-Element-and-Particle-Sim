---
inclusion: always
---

# Handover: work in progress

Written so a new conversation can carry on exactly where the last one stopped. The Kiro app has twice refused
to continue a long conversation ("The selected model cannot continue this conversation"). Keep this file up to
date as items are finished.

## How to work here

- The owner does not read code. Talk in plain, everyday English. Post one short line each time a build is ready.
- Do not stop to report while work is unfinished. Do not ration work or weaken tests. There is no time limit.
- Push straight to the project's main line. It has been renamed twice. Look up its name before every push
  (`gh api repos/2c2bhdhw9z-cell/Powder-Element-and-Particle-Sim --jq .default_branch`) and push with
  `git push origin HEAD:refs/heads/<that name>`. Never recreate a branch the owner deleted (a branch called
  `main` was deleted on purpose). No other branches, no pull requests.
- If a bot merges something that breaks the project on purpose again, undo it with `git revert` (never force
  push), say so in one line, and keep going. Do not stop to ask. This happened with pull requests #6 and #7
  (the "arena" bot); they were undone in commit 3aae16a.
- Builds and checks run on any push to the main line, whatever it is called. Each good app build is published
  as a release called build-N. The app itself only compiles on the checks' Macs (Swift 6, warnings are errors,
  iOS 17, no entitlements, no app extensions).
- Engine tests: `cd native && swift build --build-tests && swift test --skip-build`.

## Where things stand (27 September 2026)

Done and shipped, newest last:

- build-103/104: powder lasso, thermometer, rewind, tide, measurements, poster and pen-plotter drawing.
- build-105: measurements for the particle field, sent as a spreadsheet.
- In progress: a speed check that fails the checks when the engine gets much slower
  (`native/Sources/CrucibleBench/SpeedGate.swift`, `native/bench-baseline.json`, a step in `engine.yml`).

## Still to build, in this order

1. Round 7 of `docs/lab-ideas.md`, everything that needs nothing from the owner: #1 a quick check started by hand,
   #4 build cache, #5 checks for the server's half (the routes and tables the phone talks to), #8 plain-English
   release notes, #3 a tap-through test of the app and #2 pictures of the app (these two will probably show the
   Field tray crash; do not fix it yet), #9 where iOS keeps crash reports, #10 breadcrumb and "last time ended
   badly", #13 "that looked wrong" button, #15 long runs with rules that must hold, #7 bad-link room tests, #23 a
   picture of the day's world, #25 battery, #26 hot phone and Low Power, #27 sensors, #28 guest mode, #30 gallery
   of kept worlds, #31 first run, #32 iPad and sideways, #22 the television, #39 sleeping bodies, #40 the powder
   world in the 3D view, #21 the engine in a browser, #34 METHOD.md, #35 second opinion (another AI provider is
   not available; use the semantic_reviewer sub-agent and say so), #36 "if this stops" page, #47 note that
   history now exists.
2. Rounds 4 to 6: talk to it, wave at it, look round with your head, on your table, the big screen, discoveries
   notebook, guided lab book, movie studio, Live Photo, send a 3D moment, layers, creature builder, parallel
   worlds, worlds within worlds, shape recipe box, living soundscape, powder in 3D, little people.
3. Notes: the help panel, PORT-STATUS.md, the README's test count, mark what is built in `docs/lab-ideas.md`.
4. LAST, as the owner ordered: the crash when the up arrow on the Field tray's header is tapped (the app closes
   to the home screen; the Powder tray's arrow is fine). Also make opening a tray stop resizing the world.
5. Then a plain-English report of what was done and what was not. End it with these four notes, word for word:

[STEERING steer-f710cdee-9f7e-4306-8999-0d02cb84b7dd: You said the home-screen screenshot was the crash. Understood. The Field tray crash is on the list and will be fixed last.]
[STEERING steer-9e2ebc53-3795-4f81-9b01-c3eb4fb84382: I had gone to the crash against your order. I went back to doing everything else first, with the Field tray last.]
[STEERING steer-9d73b9df-0282-4d3f-94ab-1b48a78b3643: Order confirmed. I carried on with the other work.]
[STEERING steer-23f79822-d4ee-4592-9ad3-7ae9704a193d: Understood that the risk of changes piling up doesn't matter to you. I kept adding features.]

Waiting on the owner, so not to be started: server variables (#6), TestFlight and the paid account (#11, #12,
#49), anything needing an app extension (#44 to #46), "say 1.0" (#29), where the public face lives (#19).
