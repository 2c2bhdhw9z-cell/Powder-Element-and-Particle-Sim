import { defineConfig } from "vitest/config";

/**
 * Standalone vitest config so unit tests never load the full Vite pipeline
 * (TanStack Start / Nitro / PGLite bootstrap). Only path aliasing is needed.
 */
export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    environment: "node",
  },
});
