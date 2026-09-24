# The online half

The local port is finished — see [PORT-STATUS.md](PORT-STATUS.md). This is the plan for the rest:
the shared room, cloud saves, the workshop, and signing in.

Written down in this much detail because the findings below took a while to establish and would
otherwise have to be rediscovered. **Read this before touching any of it.**

The owner has confirmed all of it is wanted. On hosting, their answer was that they have not touched
the project in a long time and have no preference — so the decisions below are mine to make, and the
constraints they have to satisfy are recorded rather than assumed.

---

## What is already done

**The room's vocabulary**, in `native/Sources/CrucibleCore/Room/RoomProtocol.swift`, with fourteen
tests in `RoomProtocolTests.swift`. No transport — nothing in it can reach another device. It
defines what a message can say, how it becomes bytes, and what applying one does to a world.

The scheme is deliberately **not** the reference's. The reference broadcasts the whole grid every
tenth of a second; at the sizes this app runs that is megabytes a second. Here:

1. the full world goes once, when a peer joins;
2. strokes go as they happen, as *instructions* rather than results;
3. a cheap fingerprint goes out periodically;
4. a follower whose fingerprint disagrees asks for the whole world — and only then.

`PowderEngine.hashLite()` is the fingerprint and was built for exactly this. It was once broken in a
way that made this scheme fail completely: it mixed raw cell values while the compact format sent
something narrower, so the two never agreed, the drift test was permanently true, and the whole grid
was resent every tick. The tests cover that case now, including the one it originally missed
(inverted gravity).

---

## 1. The shared room — phone to phone

### Why not WebRTC

The reference uses WebRTC with a signalling server (`web/src/lib/multiplayer/`, plus
`web/src/routes/api/rtc.ts`). That is the right choice on the web and the wrong one here:

- iOS has no built-in WebRTC. It would mean a third-party framework.
- **A dynamic framework cannot be in this app.** The `.ipa` ships unsigned and is signed on the
  device; every embedded framework is another thing that needs a matching provisioning profile and
  another way for on-device signing to fail. That constraint is recorded in `native/project.yml` and
  is not negotiable without changing how the app is delivered.

### What to use instead

**MultipeerConnectivity.** Built into iOS, no dependency, and — importantly — **no server at all**.
It does exactly what the feature is for: two phones in the same place sharing a world.

Consequences to be honest about, in the app's own words:

- It is phone-to-phone over local network or Bluetooth. Two people in different cities cannot use it.
- It will not interoperate with the web version's rooms. Those are WebRTC; these are not. A native
  room and a web room are different rooms.

If cross-device-cross-network rooms are ever wanted, that is a separate piece of work and the honest
route is a small relay on the server, not WebRTC in the app.

### Implementation notes

- Service type `crucible-room` (13 characters; the limit is 15, lowercase letters, digits, hyphens).
- **`Info.plist` must declare both or it silently fails on iOS 14+:**
  - `NSLocalNetworkUsageDescription`
  - `NSBonjourServices` containing `_crucible-room._tcp` **and** `_crucible-room._udp`
- Room code travels in the advertiser's `discoveryInfo` so only matching codes connect.
- **Host election without negotiation:** the peer whose identifier sorts lowest among itself and its
  connected peers is the host. Stable, needs no handshake, and re-elects automatically when the host
  leaves.
- Strokes and worlds go `.reliable`; fingerprints go `.unreliable` (they are advisory and frequent).
- A stroke is under 200 bytes, so broadcasting one per touch at 120 a second is about 24KB/s. Fine.
  A world at the app's largest detail setting is a few hundred kilobytes, which is why it is sent
  once rather than continuously.

---

## 2. Cloud saves and the workshop

### The obstacle, precisely

The queries, tables and validation already exist in `web/src/lib/lab-api.ts` — `listSaves`,
`loadSave`, `createSave`, `deleteSave`, `listMaps`, `loadMap`, `downloadMap`, `likeMap`,
`publishMap`. They are **TanStack server functions**: an RPC arrangement where the client is
generated from the server's types. There are no URLs a native app can call.

So the work is to add ordinary HTTP routes that wrap the same queries. Alongside the existing
`web/src/routes/api/auth/$.ts` and `web/src/routes/api/rtc.ts`.

### Two findings that make this much easier than expected

**Bearer-token authentication already works.** `web/src/lib/auth/middleware.ts` already accepts a
bearer token and forwards it to `requireUserId`. It exists for the embedded preview, whose iframe has
partitioned cookies — but it is exactly what a native app needs. No new auth mechanism required.

**The same-site guard already permits a native client.**
`web/src/lib/auth/isolation.server.ts` rejects scripted cross-site requests, and I expected that to
block the app. It does not, and the reason matters: it returns early when there is no
`Sec-Fetch-Site` header, because that means a non-browser client. Its threat model is a malicious
*sibling browser tab* riding a `SameSite=Lax` cookie. A native app carrying an explicit bearer token
is not that threat and is not subject to it. **Do not "fix" this by tightening it** — read the
comment in that file first.

### Shape of the routes

Keep them boring and separate from the server functions rather than trying to share a handler:

```
GET    /api/v1/saves            list
POST   /api/v1/saves            create
GET    /api/v1/saves/:id        load
DELETE /api/v1/saves/:id        delete
GET    /api/v1/maps             list, with sort and tag filters
GET    /api/v1/maps/:id         load
POST   /api/v1/maps             publish
POST   /api/v1/maps/:id/like    like
POST   /api/v1/maps/:id/download  count a download and return the grid
```

Every one scoped by the authenticated user where the server function was. The existing zod
validation and limits (name ≤80, data ≤8MB, thumbnail ≤400,000 characters) must be applied here too
— the server function is not in the path any more, so its guarantees do not come for free.

---

## 3. Signing in on a phone

`ASWebAuthenticationSession` — the system sign-in sheet. It is the only route that is both
acceptable to Apple and acceptable to an OAuth provider, and it needs no embedded browser.

Flow: open the app's existing `/api/auth` sign-in URL with a callback scheme the app registers,
better-auth completes the provider round trip, the callback returns a bearer token, the app stores it
in the keychain and sends it on every request.

- Register a URL scheme in `Info.plist` (`crucible://`).
- `AUTH_PROVIDERS` in `web/src/lib/auth/providers.ts` is the source of truth for which buttons exist:
  currently Google and X.
- Sign-in can be **off** in a deployment (`VITE_AUTH_ENABLED`), in which case a shared development
  user is resolved and nothing throws. The app must handle that gracefully rather than showing a
  sign-in button that does nothing.

---

## 4. Hosting — the thing that actually needs attention

The owner does not know how this is deployed, so: it is on **Vercel**, built from `web/` by the root
`vercel.json`.

**The database falls back silently.** `web/src/lib/db.ts` uses Neon Postgres when `DATABASE_URL` is
set and an embedded PGLite otherwise, *by design*, so the app works with nothing configured. The
consequence for this feature is severe and worth stating plainly:

> If `DATABASE_URL` is not set in the deployment, cloud saves will appear to work and then vanish,
> because each serverless invocation gets its own throwaway database.

So before the workshop is announced to anybody:

1. Set `DATABASE_URL` to a real Neon database.
2. Run the migrations — `migrations/0001_auth.sql` and `0002_lab.sql`, via `scripts/migrate.mjs`.
3. Set `VITE_AUTH_ENABLED=true` and the `AUTH_*` variables, or sign-in stays off.
4. Confirm `dbSource` reports `neon` and not `pglite` once deployed.

The app should also **fail honestly**: if the server is unreachable or unconfigured, say so rather
than showing an empty list that looks like "you have no saves".

---

## Order of work

1. Room transport and its interface. No server, nothing to configure, works immediately. ✅ protocol done
2. REST routes on the web, with the existing validation reapplied.
3. Native API client, written to treat every response as untrusted — the same discipline the save
   format already gets.
4. Sign-in.
5. Cloud saves interface, then the workshop.

---

## Things that will waste your time otherwise

Repeated from `PORT-STATUS.md` because they bite hardest here:

- **The app layer cannot be compiled in this sandbox.** No Mac, no iOS SDK. CI is the only compiler
  for anything under `native/App/`. Expect to iterate through pushes, and read new code carefully
  before pushing rather than after.
- **`/tmp` does not persist between shell calls.** Download, extract and read in one command.
- **`node` is not on the PATH.** Prefix with
  `export PATH="$HOME/.nvm/versions/node/v22.23.2/bin:$PATH"`.
- **`gh run list` and anything under `gh pr` fail here.** Use `gh api` instead.
- MultipeerConnectivity cannot be tested in this sandbox at all. The protocol is tested; the
  transport will need two real phones, and the interface should therefore be written to make its
  state obvious — connected peers, whether this device is the host, and when it last agreed.
