/**
 * Federated sign-in configuration (server-only — NEVER import from the client).
 *
 * Federated sign-in is OFF by default and requires the operator to supply their
 * OWN OAuth issuer + client via env (`AUTH_ISSUER`, `AUTH_CLIENT_ID`,
 * `AUTH_CLIENT_SECRET` — see `server.ts`). When those are unset the app runs as
 * a guest / local dev-user and makes NO call to any external auth host. The app
 * ships no baked issuer, client id, or client secret.
 */

/** OAuth client id — operator-supplied via env, or empty (federation off). */
export const PREVIEW_CLIENT_ID = process.env.AUTH_CLIENT_ID?.trim() ?? "";

/** OAuth client secret — operator-supplied via env, or empty (federation off). */
export const PREVIEW_CLIENT_SECRET = process.env.AUTH_CLIENT_SECRET?.trim() ?? "";

/**
 * Extra host patterns whose callbacks a dynamic-baseURL deployment accepts, on
 * top of the loopback hosts handled in `server.ts`. Empty by default (no vendor
 * host is trusted); set `AUTH_ALLOWED_HOSTS` (comma-separated) if the operator
 * serves the app from additional hosts behind a proxy. Better Auth derives the
 * request origin and validates it against this list (wildcard-matched) so the
 * OAuth `redirect_uri` becomes the concrete request URL.
 */
export const PREVIEW_ALLOWED_HOSTS: readonly string[] = (process.env.AUTH_ALLOWED_HOSTS ?? "")
  .split(",")
  .map((host) => host.trim())
  .filter(Boolean);
