# The online half

The shared room, cloud saves, the workshop and signing in are **built**. This file is the record
of how, why those particular choices, and — the part that still needs a person — what has to be
set on the server before any of it works for real.

The local port is described in [PORT-STATUS.md](PORT-STATUS.md). Read this before touching
anything online: several findings below took a while to establish and would otherwise be
rediscovered the hard way.

---

## What still needs a human

**Everything below this line is code and is finished. This section is not.**

The app cannot know where its server is, and the server needs four things set before it can keep
anything. Neither can be done from a sandbox.

### 1. Tell the app where the server is

There is no address compiled into the app, on purpose: this project is deployed by whoever
deployed it, to whatever address they were given, and a baked-in guess would look configured and
fail every request.

So in the app: **Lab → Your worlds and the workshop → Server address**, then the web address
Crucible opens at in a browser. It is checked immediately and reports what is wrong.

### 2. Set the server up

On Vercel, which is where this is deployed from (built out of `web/` by the root `vercel.json`).

| Variable | Why |
| --- | --- |
| `DATABASE_URL` | A real Neon database. **Without it nothing is kept** — see below. |
| `VITE_AUTH_ENABLED=true` | Otherwise there is nothing to sign in to. |
| `AUTH_ISSUER`, `AUTH_CLIENT_ID`, `AUTH_CLIENT_SECRET` | Federated sign-in. All three, or sign-in stays off. |
| `BETTER_AUTH_SECRET` | Or sessions die on every deploy. |
| `BETTER_AUTH_URL=https://<the deployed address>` | **Or signing in cannot work.** Without it the sign-in library works out its own address from each request, but only accepts hosts listed in `AUTH_ALLOWED_HOSTS` (empty by default) — anything else falls back to `http://localhost:8080`, so the page a sign-in returns to is on localhost and the app's sign-in sheet fails every time. |

And register `https://<the deployed address>/api/auth/oauth2/callback/<provider>` as a return address with
the sign-in provider behind `AUTH_ISSUER`.

**Limits the host imposes.** The host refuses any request or reply over 4.5 MB before the server sees it.
The app therefore holds a world to 4 MB and a workshop picture to 60 KB (240 pixels across), below the
server's own 8 MB and 400 KB, so that sixty pictures in one workshop listing still fit in a reply.

Then run the migrations — `web/migrations/0001_auth.sql` and `0002_lab.sql`, via
`web/scripts/migrate.mjs`, which `npm run build` already does.

**The database falls back silently, and this is the trap.** `web/src/lib/db.ts` uses Neon when
`DATABASE_URL` is set and an embedded PGLite otherwise, *by design*, so the app works with nothing
configured. The consequence:

> With no `DATABASE_URL`, every serverless invocation gets its own throwaway database. A saved
> world appears to save and is then simply gone.

The app now checks for exactly this and says so before anybody saves anything — `/api/v1/status`
reports whether storage is real, and the panel shows **"Temporary — nothing is kept"** in red. But
it is a warning, not a fix.

**And there is a third state, which fails closed on purpose.** With `DATABASE_URL` set and
`VITE_AUTH_ENABLED=false`, `requireUserId` refuses every request rather than sharing one
development user against a real database — which would let every visitor read everyone's rows. The
app reports that as "this server is not set up for accounts yet" (503) rather than as a bug.

---

## 1. The shared room

`native/Sources/CrucibleCore/Room/` for everything testable, `native/App/Simulation/RoomSession.swift`
and `RoomBridge.swift` for the transport, `native/App/Views/RoomSheet.swift` for the panel.
**68 tests.**

### MultipeerConnectivity, not WebRTC

The reference uses WebRTC with a signalling server (`web/src/lib/multiplayer/`, `web/src/routes/api/rtc.ts`).
Right for a browser, wrong here: iOS has no WebRTC, so it would mean a third-party framework — and
a framework is a dynamic library needing its own provisioning profile every time this app is signed
on a device. The `.ipa` ships unsigned and is signed by whoever installs it. Every embedded
framework is another way for that to fail. That constraint is recorded in `native/project.yml` and
is not negotiable without changing how the app is delivered.

MultipeerConnectivity is already in iOS, needs nothing added, and needs **no server at all**.

Two consequences, which the panel states out loud rather than burying in help:

- It is phone to phone over local network or Bluetooth. Two people in different cities cannot use it.
- A native room and a web room are **different rooms**. One is MultipeerConnectivity and the other
  WebRTC; there is no arrangement under which they interoperate. Cross-network rooms would need a
  relay on the server, which is separate work.

### The scheme, and the one that was wrong

An earlier version of this file said: full world once, then strokes, with a fingerprint to catch
drift. **That cannot work**, and the test named `scatteringBrushDrifts` is the proof — one spray of
sand puts two worlds permanently out of agreement, and every tick of ordinary physics does the same
thing, because two engines draw from their own random streams.

So: **followers do not simulate.** The host sends the whole world, continuously, and the follower
displays it. Strokes still travel, in both directions, so a follower's painting reaches the host
and appears under its own finger immediately rather than a network round trip later.

Making that affordable took three things:

- **Run-length encoding**, because a powder world is mostly air in long runs. Measured at the app's
  four detail settings: an empty 150,000-cell world packs to 1.2 KB (124×), a busy one to 18 KB, and
  the largest world the app makes to 55 KB. With a plain-bytes fallback for a world that will not
  compress, so the worst case is one byte of overhead rather than double the size.
- **A binary frame, not base64 inside JSON.** Base64 adds a third to the traffic that dominates the
  link, plus the processor time to encode and decode it on both phones for nothing. The frame
  describes itself — width, height, gravity, a sequence number and the sender's fingerprint in the
  header — so it is checked against its own claims rather than a size the receiver was told
  separately. A body laid down at the wrong row length shears the whole world diagonally and reports
  nothing.
- **Acknowledgement pacing.** A timer sending thirty frames a second fails badly on a link that
  cannot carry thirty: they queue, and the follower falls further behind every second while the host
  thinks all is well. Nothing reports it. So a frame goes, the follower says it drew it, and only
  then does the next one go — the rate becomes the link's to choose, with a ceiling so a fast link
  does not starve the simulation, and a deadline so a peer that walked out of range does not stop the
  room.

### Implementation notes

- Service type `crucible-room` — 13 characters; the limit is 15, lower case, digits, hyphens.
- **`Info.plist` must declare both or it silently fails on iOS 14+**, and there is nothing to debug
  because nothing errors: `NSLocalNetworkUsageDescription`, and `NSBonjourServices` listing
  `_crucible-room._tcp` **and** `_crucible-room._udp`. Both, because MultipeerConnectivity uses
  whichever suits the link.
- The room code travels in the advertiser's `discoveryInfo`, and is checked again on the invitation.
- **Host election with no handshake:** the lowest-sorting identifier, computed independently by every
  peer. A negotiation to elect a host is one more thing to fail on the least reliable part of the
  feature, and the peer that would run it is the one that just disappeared.
- **Lower invites higher**, so exactly one of any two peers invites the other. Without a rule like
  that, both browse, both invite, and the pair can end up with two half-built connections where
  neither side agrees which is real.
- Identifiers are `"<device name> <four random characters>"`. From iOS 16 `UIDevice.name` returns
  the model, so without the suffix two iPhones would be called the same thing and sorting them
  would be a coin toss each phone could flip differently.

### The bug worth knowing about

**When the host leaves and another phone takes over, the new host's frame numbering restarts at
one.** Measured against the old host's five hundredth frame, one looks like something from the
distant past — so every frame from the new host would be rejected as stale and the follower would
sit in front of a frozen world for good, with the link working perfectly and nothing to indicate
why.

It is fixed (the follower notices the world is arriving from a different phone and starts again),
and it is recorded here because it needs three phones and one of them to leave. It was found by
reading, and that was the only way it could have been.

### What cannot be tested here

The transport, entirely — it needs two real phones. That is exactly why the decisions moved into
the engine: who hosts, when a frame may go, whether an arriving frame is newer, what a typed code
means. All of that has tests. The panel is written to make the state obvious — the code, who is
connected, which phone is running the world, and whether frames are still arriving — because when
it does go wrong, that display is the only diagnostic anyone will have.

---

## 2. Cloud saves and the workshop

`native/Sources/CrucibleCore/Cloud/CloudProtocol.swift` (**45 tests**),
`native/App/Simulation/CloudClient.swift` and `CloudAccount.swift`,
`native/App/Views/CloudSheet.swift` and `WorkshopSheet.swift`.
Server side: `web/src/lib/lab-store.ts`, `web/src/lib/api/` (**13 tests**),
`web/src/routes/api/v1/$.ts`.

### Why there are new routes at all

The queries already existed in `web/src/lib/lab-api.ts` as TanStack **server functions** — an
arrangement where the client is generated from the server's types, so there are no URLs. Good for
the website, unusable from an app.

So `/api/v1/*` was added, and the server functions were **reduced to wrappers over the same
queries** in `lab-store.ts`. Writing the routes out separately would mean every column rename made
twice, with the second the one that gets missed — and, worse, so would every `where user_id =`. A
route that forgets that returns somebody else's saves, and nothing about it looks wrong from the
outside. The zod limits moved there too: the server function's validator is not in the HTTP path,
so leaving them would have given one of two callers no limits at all.

### Two findings that made this easier than expected

**Bearer-token authentication already worked.** `web/src/lib/auth/middleware.ts` already accepted
one, built for the embedded preview whose iframe has partitioned cookies. Exactly what an app needs.

**The same-site guard already permitted a native client, deliberately.**
`web/src/lib/auth/isolation.server.ts` returns early when there is no `Sec-Fetch-Site` header,
because that means a non-browser client. Its threat model is a malicious *sibling browser tab*
riding a `SameSite=Lax` cookie. **Do not "fix" this by tightening it** — read the comment first.

### But the routes do not rely on that

`/api/v1/*` reads a bearer token and **refuses to look at cookies**, via `requireUserIdForApi`. A
route that accepts a cookie is a route another site can make a browser send a request to on
somebody's behalf; a route that accepts only a token the caller has to know cannot be, whatever
headers the browser adds. The app always holds a token, so it loses nothing, and the guarantee
becomes structural rather than a header check that has to stay correct.

### The shape

```
GET    /api/v1/status                  is this server usable, and does it keep anything
GET    /api/v1/me                      is this token still good
GET    /api/v1/auth/providers          which sign-in buttons to draw
GET    /api/v1/auth/start/:provider    begin signing in
GET    /api/v1/auth/done               finish signing in
GET    /api/v1/saves                   list
POST   /api/v1/saves                   keep
GET    /api/v1/saves/:id               open
DELETE /api/v1/saves/:id               remove
GET    /api/v1/maps                    the workshop, with sort and tag
POST   /api/v1/maps                    publish
GET    /api/v1/maps/:id                read
POST   /api/v1/maps/:id/like           like
POST   /api/v1/maps/:id/download       count an opening and return the world
```

One splat route in the generated route tree; the dispatch is a table in `v1-routes.ts`, which has
no server imports so it can be tested without starting a database.

**`needsAccount` is the part to be careful with.** It is one exhaustive switch — adding an
operation without deciding this fails to compile — and the test walks every operation there is and
asserts the answer. A route that forgets to require an account has no symptom: it works perfectly,
for everybody, including the people it should keep out. Verified by breaking it.

### The one thing the interface is most careful about

**Never an empty list for a request that failed.** "You have no saved worlds" and "nobody managed
to ask" look identical and mean opposite things, and the second shown as the first is how somebody
concludes their work is lost. So a list has three states rather than two, the failed one says what
went wrong and whether trying again could go differently, and a failed refresh leaves the previous
list alone instead of emptying it.

---

## 3. Signing in

`ASWebAuthenticationSession` — the system sign-in sheet. The only route both Apple and an identity
provider accept, it shows a real address bar so somebody can see whose page they are typing a
password into, and the app never sees the password.

### The bridge that was needed

Better Auth hands out a **cookie**. The OAuth round trip happens inside the sheet, and that cookie
belongs to the sheet and vanishes with it — the app never sees it. What the app can carry is a
bearer token, which the `bearer()` plugin already accepts.

So `web/src/lib/api/native-auth.server.ts` does what the preview's popup already does
(`web/src/lib/auth/popup.server.ts`), with the last step changed:

1. `/api/v1/auth/start/<provider>` begins OAuth, asking for the callback to return to step 2 —
   same origin, so the cookie lands inside the sheet where it is useful.
2. `/api/v1/auth/done` reads that cookie server-side and redirects to `crucible://auth?token=…`.

The sheet matches the scheme and **stops**. It never fetches that address, so nothing logs it, and
no page is written, so it is in no history or cache. A page showing a code to copy would be worse
in every way, including for security, because a code somebody types is a code they can be talked
into typing somewhere else.

- `AUTH_PROVIDERS` in `web/src/lib/auth/providers.ts` remains the source of truth: Google and X.
- The scheme `crucible` appears in three places that must agree — `CFBundleURLSchemes` in
  `Info.plist`, `CloudSignIn.scheme` in the app, `nativeCallbackScheme` on the server. Getting it
  wrong shows up as a sheet that opens, completes, and then just sits there.

### Where the token is kept, and why not the keychain

**A file with complete protection, not the keychain**, and this is deliberate.

The app ships unsigned with no entitlements and is signed on the device by whoever installs it.
Keychain access depends on the entitlements the signing tool happens to inject, and when they do not
line up it fails with `-34018` — so signing in would appear to work and then be forgotten on every
launch, on some phones and not others, for reasons nothing in the app could explain.

A protected file needs no entitlement, so it cannot fail that way, and is still encrypted with the
device's passcode and unreadable while the phone is locked. One code path, and it is the one that
was reasoned about.

### The case that would have been silently broken

A session token is two base64 parts joined by a dot, so it contains `+`, `/` and `=`. Every one
arrives percent-encoded, and a callback decoder that mishandled any would produce a token that looks
perfectly reasonable and is refused by every request from then on — which reads as "signing in does
not work" with nothing to point at. There is a test for exactly that.

---

## Things that will waste your time otherwise

Repeated from `PORT-STATUS.md` because they bite hardest here:

- **The app layer cannot be compiled in this sandbox.** No Mac, no iOS SDK. CI is the only compiler
  for anything under `native/App/`. Read new code carefully before pushing rather than after — a
  round trip is about four minutes.
- **`/tmp` does not persist between shell calls.**
- **`node` is not on the PATH.** `export PATH="$HOME/.nvm/versions/node/v22.23.2/bin:$PATH"`.
- **`gh run list` and anything under `gh pr` fail here.** Use `gh api`. For a failed build:
  `gh api repos/{owner}/{repo}/actions/runs/{id}/jobs` then
  `gh api repos/{owner}/{repo}/actions/jobs/{id}/logs`.
- **The releases list is not in date order.** Sort by `created_at` yourself or you will look at a
  build from hours ago and think nothing shipped.
- **Migrations are in `web/migrations/`, not the repository root.** They moved with the web front
  end and this file used to say otherwise.
- **`#expect(condition, message)` needs a literal.** A plain `String` variable does not compile —
  interpolate it: `"\(message)"`.
- **`#require` cannot be nested inside another `#require`.** Compute into a `let` first.
