import { debug } from "@/lib/debug";
import { getRequest } from "@tanstack/react-start/server";
import { auth, authConfigured } from "./server";

/**
 * Server-side session resolution (server-only).
 *
 * Because this app runs its OWN Better Auth at same-origin `/api/auth/*`, the
 * session cookie is sent with every request to this app — server functions AND
 * SSR loaders included. So we resolve the user straight from the request cookies
 * via `auth.api.getSession` (no client-minted JWT needed). Never trust a
 * client-supplied user id — only the result of this verification.
 */

/** True when a real database is configured server-side. */
const databaseConfigured = Boolean(process.env.DATABASE_URL?.trim());

/** Re-export so callers can branch on it without importing `server.ts`. */
export { authConfigured };

if (databaseConfigured && !authConfigured) {
  debug.error(
    "[auth] DATABASE_URL is set but auth is disabled (VITE_AUTH_ENABLED=false) " +
      "— requireUserId() will reject every request (fail closed) rather than " +
      "share one dev user on a real database.",
  );
}

/** Dev fallback user id, used only when auth is disabled (VITE_AUTH_ENABLED=false). */
export const DEV_USER_ID = "dev-user";

/**
 * Thrown by `requireUserId` when the caller has no valid session. Carries
 * `status: 401`; the message is a stable contract — match
 * `err.message === "Unauthorized"` client-side to send the visitor to sign-in.
 */
export class UnauthorizedError extends Error {
  readonly status = 401;
  constructor() {
    super("Unauthorized");
    this.name = "UnauthorizedError";
  }
}

export type VerifiedUser = { id: string; email: string | null };

/**
 * Resolve the signed-in user from the current request, or `null` when auth isn't
 * configured / nobody is signed in. Safe to call from server functions and SSR
 * loaders.
 *
 * `bearerToken` is for the LIVE PREVIEW: the app runs in a partitioned iframe
 * whose cookies don't reach the server, so `authMiddleware` forwards the session
 * as a bearer token, which we present as `Authorization: Bearer …` (the `bearer`
 * plugin resolves it). When deployed no token is passed and the cookie is used.
 */
export async function getSessionUser(bearerToken?: string): Promise<VerifiedUser | null> {
  if (!authConfigured) return null;
  const request = getRequest();
  if (!request) return null;
  let headers = request.headers;
  if (bearerToken) {
    headers = new Headers(request.headers);
    headers.set("Authorization", `Bearer ${bearerToken}`);
  }
  return userFromHeaders(headers);
}

/** Resolve a user from an explicit set of headers. Shared by both callers below. */
async function userFromHeaders(headers: Headers): Promise<VerifiedUser | null> {
  const session = await auth.api.getSession({ headers });
  if (!session?.user) return null;
  return { id: session.user.id, email: session.user.email ?? null };
}

/**
 * Resolve the user for a plain HTTP API route (`/api/v1/*`), from a bearer token
 * and **nothing else**.
 *
 * ## Why this refuses to look at cookies
 *
 * `getSessionUser` reads whatever the request carried, cookie included, which is
 * right for the web app's own server functions — those are protected from a
 * malicious same-site sibling riding a `SameSite=Lax` cookie by the
 * Fetch-Metadata check in `isolation.server.ts`.
 *
 * These routes could have relied on that same check. They deliberately do not.
 * A route that accepts a cookie is a route another site can make a browser send
 * a request to on the visitor's behalf; a route that accepts *only* a token the
 * caller has to know cannot be, whatever headers the browser adds. The native
 * app always holds a token, so it loses nothing — and this way the guarantee is
 * structural rather than a header check that has to be kept correct.
 *
 * When auth is switched off entirely (`VITE_AUTH_ENABLED=false`) this follows
 * exactly the same rule as `requireUserId`: the shared local user with no
 * database, and a refusal when there is a real one.
 */
export async function requireUserIdForApi(request: Request): Promise<string> {
  if (!authConfigured) {
    if (databaseConfigured) {
      throw new Error(
        "Auth is disabled (VITE_AUTH_ENABLED=false) but DATABASE_URL is set — " +
          "refusing to fall back to the shared dev user against a real database.",
      );
    }
    return DEV_USER_ID;
  }

  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim();
  if (!token) throw new UnauthorizedError();

  // Built from scratch, carrying the token and nothing else. Copying the request's
  // own headers would bring the cookie back in and undo the point of this.
  const user = await userFromHeaders(new Headers({ Authorization: `Bearer ${token}` }));
  if (!user) throw new UnauthorizedError();
  return user.id;
}

/**
 * Resolve the current user id for a server function, or throw when unauthorized.
 * Prefer `authMiddleware` (`./middleware`), which calls this for you.
 *
 * Auth is opt-in and OFF by default. It is only "configured" when the operator
 * supplies their own OAuth provider via env (AUTH_ISSUER +
 * AUTH_CLIENT_ID + AUTH_CLIENT_SECRET on the server, and
 * VITE_AUTH_ENABLED=true on the client). There is no baked shared preview
 * client, so a fresh clone contacts no external auth host.
 * - Auth configured -> the verified session user id; throws `UnauthorizedError`
 *   when signed out.
 * - Auth NOT configured + `DATABASE_URL` set -> throw (fail closed): one shared
 *   local dev user on a real database would let every visitor read/write
 *   everyone's rows.
 * - Auth NOT configured + no database -> the local dev user id (DEV_USER_ID).
 */
export async function requireUserId(bearerToken?: string): Promise<string> {
  if (!authConfigured) {
    if (databaseConfigured) {
      throw new Error(
        "Auth is disabled (VITE_AUTH_ENABLED=false) but DATABASE_URL is set — " +
          "refusing to fall back to the shared dev user against a real database.",
      );
    }
    return DEV_USER_ID;
  }
  const user = await getSessionUser(bearerToken);
  if (!user) throw new UnauthorizedError();
  return user.id;
}
