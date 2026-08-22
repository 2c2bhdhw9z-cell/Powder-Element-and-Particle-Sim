/**
 * Gated debug logger, safe on both client and server bundles.
 *
 * - `debug.error` is ALWAYS emitted: real failures (DB bootstrap, auth,
 *   recorder, signaling) must stay visible to operators.
 * - `debug.warn` / `debug.log` are gated: they emit only when debugging is
 *   enabled via the `DEBUG=1` env var (server) or a `?debug` URL param
 *   (client), so transient WebRTC churn doesn't spam production consoles.
 */

function isDebugEnabled(): boolean {
  try {
    if (typeof process !== "undefined" && process.env?.DEBUG) return true;
  } catch {
    /* no process in some client contexts */
  }
  if (typeof window !== "undefined" && window.location.search.includes("debug")) return true;
  return false;
}

const enabled = isDebugEnabled();

export const debug = {
  enabled,
  log: (...args: unknown[]) => {
    if (enabled) console.log(...args);
  },
  warn: (...args: unknown[]) => {
    if (enabled) console.warn(...args);
  },
  error: (...args: unknown[]) => {
    console.error(...args);
  },
} as const;

export type DebugLogger = typeof debug;
