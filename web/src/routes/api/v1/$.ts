import { createFileRoute } from "@tanstack/react-router";
import { handleApiV1 } from "@/lib/api/v1.server";

/**
 * The lab's plain HTTP API, for the iOS app.
 *
 * One splat route rather than a file per path. The dispatch is in
 * `@/lib/api/v1.server`, where the whole surface can be read at once — and this
 * way the generated route tree gains a single entry instead of nine.
 */
const handle = ({ request }: { request: Request }) => handleApiV1(request);

export const Route = createFileRoute("/api/v1/$")({
  server: {
    handlers: {
      GET: handle,
      POST: handle,
      DELETE: handle,
    },
  },
});
