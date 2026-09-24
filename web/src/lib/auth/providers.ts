/**
 * The upstream identity providers this app offers for sign-in.
 *
 * Source of truth for BOTH the server (`server.ts`, one `genericOAuth` provider
 * per entry) and the client (`client.ts` / sign-in buttons). Kept in its own
 * dependency-free module so the client can import it without pulling the
 * server-only Better Auth instance (and `pg`) into the browser bundle.
 *
 * Federation is OFF by default. When the operator enables it, each entry
 * federates to the operator-supplied OAuth issuer (`AUTH_ISSUER`) using the
 * operator's own client id/secret; `idp` is the upstream hint the issuer reads.
 *
 * To add an upstream (e.g. GitHub): add one entry here
 * (`{ providerId: "github", idp: "github", label: "GitHub" }`). The
 * `providerId` is this app's local id and the OAuth callback path segment
 * (`/api/auth/oauth2/callback/<providerId>`); `idp` is the hint the issuer reads
 * to pick the upstream (Better Auth's id for X is still `twitter`).
 */
export type AuthProvider = {
  /** This app's local provider id; also the callback path segment. */
  providerId: string;
  /** Upstream hint the issuer forwards to (Better Auth social id). */
  idp: string;
  /** Human label for the sign-in button. */
  label: string;
};

export const AUTH_PROVIDERS: readonly AuthProvider[] = [
  { providerId: "google", idp: "google", label: "Google" },
  { providerId: "x", idp: "twitter", label: "X" },
];
