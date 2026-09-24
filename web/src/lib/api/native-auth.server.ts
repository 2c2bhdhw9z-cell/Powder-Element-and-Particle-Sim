/**
 * Signing in from the iOS app — server-only.
 *
 * ## The problem
 *
 * Better Auth hands out a session **cookie**. An app is not a browser: it opens a
 * system sign-in sheet, the OAuth round trip happens inside that sheet, and the
 * cookie that comes back belongs to the sheet and vanishes with it. The app never
 * sees it.
 *
 * What the app can carry is a bearer token — the `bearer()` plugin already accepts
 * one, and `/api/v1/*` accepts nothing else. So the missing piece is a way to get
 * the token out of the sheet and into the app.
 *
 * ## The way across
 *
 * Exactly the arrangement the live preview already uses for its popup (see
 * `popup.server.ts`), with the last step changed. The preview posts the token to
 * the window that opened it; there is no such window here, so instead:
 *
 *   1. `/api/v1/auth/start/<provider>` begins OAuth and redirects into it, asking
 *      for the callback to come back to step 2 — same origin, so the cookie lands
 *      inside the sheet where it is useful.
 *   2. `/api/v1/auth/done` reads that cookie on the server and redirects to
 *      `crucible://auth?token=…`.
 *
 * The app's sign-in sheet is watching for `crucible://`. It never loads that URL —
 * it hands it straight back to the app, which takes the token and puts it in the
 * keychain. Nothing is ever written to a page, so the token is not in any history
 * or cache.
 *
 * ## Why the token is in the URL, which normally it should not be
 *
 * Because this particular URL is never fetched by anything. `ASWebAuthenticationSession`
 * matches the scheme and stops; no request is made, no server logs it, no proxy
 * sees it. The alternative — a page that shows a code to copy — is worse in every
 * way, including for security, because a code somebody types is a code they can be
 * talked into typing somewhere else.
 *
 * The responses below are still marked `no-store`, and the redirect carries no
 * body, so there is nothing for an intermediate cache to keep either way.
 */
import { auth, AUTH_PROVIDERS, SESSION_TOKEN_COOKIE } from "@/lib/auth/server";

/** The scheme the app registers. Must match `CFBundleURLSchemes` in Info.plist. */
export const nativeCallbackScheme = "crucible";

/** Where the app's sign-in sheet is watching. */
const nativeCallback = `${nativeCallbackScheme}://auth`;

/** Which providers exist, for the app to draw buttons from. */
export function providersResponse(): Response {
  return new Response(
    JSON.stringify({
      providers: AUTH_PROVIDERS.map(({ providerId, label }) => ({
        id: providerId,
        label,
      })),
    }),
    {
      status: 200,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    },
  );
}

/** Hands the app back to itself, with either a token or a reason. */
function backToApp(params: Record<string, string>): Response {
  const url = new URL(nativeCallback);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return new Response(null, {
    status: 302,
    headers: { location: url.toString(), "cache-control": "no-store" },
  });
}

/**
 * Step one: start the OAuth round trip.
 *
 * The provider is checked against the configured list rather than passed through.
 * Better Auth would refuse an unknown one anyway, but it would refuse it with an
 * error page inside the sign-in sheet — where the app cannot read it and somebody
 * is left looking at a blank sheet. Refusing here sends the reason back through
 * the callback, where the app can say it.
 */
export async function startNativeSignIn(request: Request, provider: string): Promise<Response> {
  const known = AUTH_PROVIDERS.some((entry) => entry.providerId === provider);
  if (!known) return backToApp({ error: "unknown_provider" });

  const url = new URL(request.url);
  const done = `${url.origin}/api/v1/auth/done`;

  try {
    const started = await auth.api.signInWithOAuth2({
      body: {
        providerId: provider,
        callbackURL: done,
        errorCallbackURL: `${done}?failed=1`,
      },
      // Forwarded so Better Auth derives the same origin this request arrived on,
      // which is what the OAuth redirect_uri has to match.
      headers: request.headers,
      asResponse: true,
    });

    if (!started.ok) {
      return backToApp({ error: `sign_in_unavailable_${started.status}` });
    }
    const body = (await started.json().catch(() => null)) as { url?: string } | null;
    if (!body?.url) return backToApp({ error: "sign_in_no_destination" });

    // Every Set-Cookie forwarded: the OAuth state and PKCE verifier live in them,
    // and without them the callback in step two cannot complete.
    const headers = new Headers({ location: body.url, "cache-control": "no-store" });
    for (const cookie of started.headers.getSetCookie()) {
      headers.append("set-cookie", cookie);
    }
    return new Response(null, { status: 302, headers });
  } catch {
    return backToApp({ error: "sign_in_failed" });
  }
}

/**
 * Step two: the OAuth round trip has finished. Hand the token to the app.
 *
 * A missing cookie here is reported as a failure rather than as an empty token.
 * An app handed an empty token would store it and then be signed out on every
 * request afterwards, with no way to tell that from an expired one.
 */
export function finishNativeSignIn(request: Request): Response {
  const url = new URL(request.url);
  if (url.searchParams.has("failed")) {
    return backToApp({ error: "sign_in_declined" });
  }
  const token = readCookie(request, SESSION_TOKEN_COOKIE);
  if (!token) return backToApp({ error: "no_session" });
  return backToApp({ token });
}

/** Reads one cookie, tolerating `=` inside the value. */
function readCookie(request: Request, name: string): string | null {
  const header = request.headers.get("cookie");
  if (!header) return null;
  for (const part of header.split(";")) {
    const trimmed = part.trim();
    const eq = trimmed.indexOf("=");
    if (eq <= 0) continue;
    if (trimmed.slice(0, eq) !== name) continue;
    const raw = trimmed.slice(eq + 1);
    try {
      return decodeURIComponent(raw);
    } catch {
      return raw;
    }
  }
  return null;
}
