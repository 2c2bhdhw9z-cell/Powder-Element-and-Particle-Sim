# If this stops

The one document here that assumes nobody is paying attention to the project any more. Everything else describes how
Crucible works; this describes where it lives, so that somebody — including you, in a year — can pick it up, keep it
running, or shut it down deliberately rather than by neglect.

Written in plain English on purpose. Nothing below needs any of the code to be understood.

## What Crucible is, in two lines

A lab of two simulated worlds on an iPhone: falling material on a grid (sand, water, lava, fire) and a crowd of bodies
pulling on one another (orbits, swarms, cloth, jellies). One repository holds two implementations of it — the phone app,
which is the real one, and the original website, which is kept as the thing the phone app is checked against.

## Where everything lives

| Thing | Where | What happens if it goes |
| --- | --- | --- |
| The code, its history, and every build | GitHub, `2c2bhdhw9z-cell/Powder-Element-and-Particle-Sim` | Everything is gone except whatever is on somebody's machine. This is the only copy that matters. |
| The app people install | GitHub Releases on that repository, one per build, `Crucible.ipa` | Nobody can install it again until a new build is made. Already-installed copies keep working until their signature expires. |
| The checks that build it | GitHub Actions, in `.github/workflows` | Nothing is built or checked. The code is unaffected. |
| The website half | Vercel, deployed from the same repository | The app loses saving to a server and the workshop. Everything else in the app works with no server at all. |
| The worlds people kept on a server | A Postgres database, reached through the `DATABASE_URL` variable | Those worlds are gone. Worlds kept on the phone itself are not affected. |
| Signing in | `better-auth` in the website, with Google and X | Nobody can sign in, so nobody can keep a world on the server or publish one. Browsing the workshop still works. |

## The server settings it needs

Set in Vercel, not in the repository. Without them the public server still opens, but accounts are off and its
throwaway database forgets every saved world. The app notices and says so plainly.

| Variable | What it is for |
| --- | --- |
| `DATABASE_URL` | Where the worlds are kept. Without it, storage is temporary. |
| `VITE_AUTH_ENABLED=true` | Switches real accounts on. |
| `AUTH_ISSUER` | The address of the service that signs people in. |
| `AUTH_CLIENT_ID` / `AUTH_CLIENT_SECRET` | The pair issued for this app. Without both, signing in stays off. |
| `BETTER_AUTH_SECRET` | Signs the login cookies. Any long random string; changing it signs everybody out. |
| `BETTER_AUTH_URL` | The public server's exact address, so sign-in comes back to the right place. |

`AUTH_ALLOWED_HOSTS` is optional for preview deployments. Vercel's **Production Branch** must also exactly match
GitHub's current default branch; it did not on 28 September 2026, so new commits were only reaching Preview. These are
the exact names the server reads; the app reads none of them and never sees them.

The app finds the server by being told its address once, in its own **Your worlds** panel. The app has no way of
guessing it, and there is nothing to change in the app if the address changes.

## How a build is made

No Mac is involved in building this, and there never has been one.

1. Push to the project's main line. (It has been renamed twice; whatever GitHub shows as the default branch is it.)
2. **Engine** runs the simulation's own tests on Linux and on macOS, in both plain and optimised builds, and fails if
   anything has become much slower than the figures in `native/bench-baseline.json`.
3. **iOS app** builds an unsigned `.ipa` on a macOS runner and publishes it as a release called `build-N`, with notes
   saying what changed since the last one.
4. **App tour** opens the app on a simulated iPhone and iPad, uses it, and fails on a crash, a hang or a blank world.
5. **Server** replays every request the app makes against the real server code and real tables.
6. **Long runs** leaves every scene running for thousands of moments, checking that nothing impossible happens.

To install a build: open the release on the phone, download `Crucible.ipa`, and sign it on the device with a
re-signing tool. The app is deliberately built with no entitlements, no app extensions and no dynamic frameworks,
because each of those is a way for signing on the device to fail.

## What is deliberately not here

- **No Apple developer account.** So: no TestFlight, no widgets, no lock-screen clock, and no way for somebody else to
  install it without re-signing it themselves. Every one of those is one paid membership away and nothing else.
- **No crash reporting service.** The phone already writes a report every time an app closes by itself (Settings →
  Privacy & Security → Analytics & Improvements → Analytics Data). The app keeps its own note of what the *world* was
  doing, and offers to send it on the next launch.
- **No analytics of any kind.** Nothing about anybody is collected or sent anywhere. The only thing the app ever sends
  is a world somebody chose to keep on a server or publish.

## If you want to shut it down deliberately

In this order, so that nothing half-works:

1. Say so in the README, with a date. An unmaintained project that says so is useful; one that does not is a trap.
2. Delete the Vercel deployment, or leave it and remove `DATABASE_URL` — the website then runs with a throwaway
   database and the app says plainly that nothing will be kept.
3. Leave the releases alone. They cost nothing, and they are the only way anybody can install what was built.
4. Leave the repository public and archive it on GitHub. Archiving stops the checks from running and makes it
   read-only, which is exactly the right state for something finished.

## If you want to pick it up again

- Read `PORT-STATUS.md` for what is built and what is not, and `docs/lab-ideas.md` for everything that was considered.
  Both admit what is missing, which is the point of them.
- `.kiro/steering/handover.md` is the shortest way in: it says where the work stopped and what was next.
- The engine imports nothing from Apple, so `cd native && swift test` runs the whole simulation's test suite on any
  machine with Swift on it, including Linux. That is the fastest way to find out whether anything still works.
