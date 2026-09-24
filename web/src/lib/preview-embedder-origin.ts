/**
 * Trust policy for the parent window that may embed this app in a preview
 * iframe. A self-hosted app has no vendor parent, so only loopback origins are
 * trusted by default. Operators who embed the app under their own host can
 * extend the allowlist via `VITE_PREVIEW_EMBEDDER_ORIGINS` (comma-separated
 * origins).
 */

function envAllowedOrigins(): string[] {
  const raw =
    typeof import.meta !== "undefined"
      ? (import.meta as { env?: Record<string, string | undefined> }).env
          ?.VITE_PREVIEW_EMBEDDER_ORIGINS
      : undefined;
  return String(raw ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

export function isTrustedEmbedderOrigin(origin: string): boolean {
  try {
    const url = new URL(origin);
    if (url.protocol !== "https:" && url.protocol !== "http:") return false;
    const host = url.hostname.toLowerCase();
    if (host === "localhost" || host === "127.0.0.1" || host === "[::1]") return true;
    return envAllowedOrigins().includes(url.origin);
  } catch {
    return false;
  }
}

export function isSandboxPreviewGuestHost(_hostname: string): boolean {
  // No vendor sandbox host is assumed for a self-hosted app.
  return false;
}

function isRemintPreviewPair(guestHost: string, parentHost: string): boolean {
  const guest = guestHost.toLowerCase();
  const parent = parentHost.toLowerCase();
  const sep = ".preview.";
  const i = guest.indexOf(sep);
  if (i <= 0) return false;
  const label = guest.slice(0, i);
  const rest = guest.slice(i + sep.length);
  if (label.includes(".") || !rest.includes(".")) return false;
  return parent === rest;
}

export function resolveParentEmbedderOrigin(
  parentIsSelf: boolean,
  referrer: string,
  ancestorOrigin?: string | null,
  guestHostname: string = "",
): string | null {
  if (parentIsSelf) return null;
  for (const candidate of [referrer, ancestorOrigin ?? ""].filter(Boolean)) {
    try {
      const url = new URL(candidate.includes("://") ? candidate : `https://${candidate}`);
      if (url.protocol !== "https:" && url.protocol !== "http:") continue;
      if (isTrustedEmbedderOrigin(url.origin)) return url.origin;
      if (
        isSandboxPreviewGuestHost(guestHostname) ||
        isRemintPreviewPair(guestHostname, url.hostname)
      ) {
        return url.origin;
      }
    } catch {
      // try next candidate
    }
  }
  return null;
}
