/**
 * Federated sign-in configuration (server-only — NEVER import from the client).
 *
 * This app no longer ships a shared vendor "preview" OAuth client. Federated
 * sign-in is OFF by default and requires the operator to supply their OWN OAuth
 * issuer + client via env (`GROK_AUTH_ISSUER`, `GROK_AUTH_CLIENT_ID`,
 * `GROK_AUTH_CLIENT_SECRET` — see `server.ts`). When those are unset the app
 * runs as a guest / local dev-user and makes NO call to any external auth host.
 *
 * NOTE: a shared vendor preview OAuth client (id + secret) and a baked
 * `https://auth.grok.me` issuer default used to live here. The secret was a
 * committed credential and has been removed; the app no longer federates to any
 * vendor broker by default. To re-enable federated sign-in, provide your own
 * issuer + client via the env vars above.
 */

/** OAuth client id — operator-supplied via env, or empty (federation off). */
export const PREVIEW_CLIENT_ID = process.env.GROK_AUTH_CLIENT_ID?.trim() ?? "";

/** OAuth client secret — operator-supplied via env, or empty (federation off). */
export const PREVIEW_CLIENT_SECRET = process.env.GROK_AUTH_CLIENT_SECRET?.trim() ?? "";

/**
 * Host patterns whose callbacks a dynamic-baseURL deployment accepts. Better
 * Auth derives the request origin and validates it against this list
 * (wildcard-matched) so the OAuth `redirect_uri` becomes the concrete
 * `https://<host>/api/auth/oauth2/callback/...`. Only relevant when the operator
 * has enabled federated sign-in with their own client.
 */
export const PREVIEW_ALLOWED_HOSTS = ["*.grok-sandbox.com"] as const;
