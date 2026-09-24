/**
 * The HTTP side of the lab, for callers that are not this website.
 *
 * ## Why these exist at all
 *
 * The web app talks to the server through TanStack **server functions**: the
 * client is generated from the server's types and there are no URLs involved.
 * That is a good arrangement and completely unusable from an iOS app, which can
 * only make HTTP requests. So there is a small, plain, versioned API here.
 *
 * Every one of these is a wrapper. The queries and the size limits are in
 * `lab-store.ts`, shared with the server functions, because two copies of a
 * `where user_id = …` is one copy that eventually gets forgotten.
 *
 * ## The two things that are easy to get wrong
 *
 * **Who is asking.** Answered by `requireUserIdForApi`, which reads a bearer
 * token and refuses to look at cookies at all — see the long note on it. That
 * makes a cross-site request structurally unable to borrow somebody's session,
 * rather than merely unlikely to.
 *
 * **What a failure looks like.** An app that cannot reach its server must say so.
 * The failure that matters is not the obvious one: it is a request that fails and
 * gets shown as an empty list, so somebody is told they have no saved worlds when
 * in fact nobody asked. So every path here answers with a status the app can tell
 * apart — 401 for signed out, 404 for not there, 400 for a bad request, 503 for a
 * server that is not set up — and never with an empty success.
 *
 * Server-only.
 */
import { dbSource } from "@/lib/db";
import { authConfigured } from "@/lib/auth/server";
import { requireUserIdForApi, UnauthorizedError } from "@/lib/auth/verify.server";
import { needsAccount, resolveApiV1Route } from "@/lib/api/v1-routes";
import {
  finishNativeSignIn,
  providersResponse,
  startNativeSignIn,
} from "@/lib/api/native-auth.server";
import {
  createSaveFor,
  deleteSaveFor,
  downloadMapById,
  likeMapById,
  listMapsWith,
  listSavesFor,
  loadMapById,
  loadSaveFor,
  mapInput,
  mapQuery,
  publishMapFor,
  saveInput,
} from "@/lib/lab-store";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      // Per-user data and single rows. A cache anywhere in between holding one
      // person's saves and handing them to the next caller would be the worst
      // possible bug in this file.
      "cache-control": "no-store",
    },
  });
}

function failure(message: string, status: number): Response {
  return json({ error: message }, status);
}

/**
 * Turns whatever went wrong into a status the app can act on.
 *
 * The 503 case is the one worth having. A deployment with `VITE_AUTH_ENABLED=false`
 * and a real `DATABASE_URL` refuses every request on purpose — sharing one local
 * user against a real database would let every visitor read everybody's rows — and
 * without this it would surface as a generic 500 that looks like a bug rather than
 * as something the operator needs to go and fix.
 */
function describe(error: unknown): Response {
  if (error instanceof UnauthorizedError) {
    return failure("Sign in to do that.", 401);
  }
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("refusing to fall back to the shared dev user")) {
    return failure("This server is not set up for accounts yet.", 503);
  }
  // A validation failure. Reported as the caller's fault, which it is, and with
  // enough detail to act on — an app told only "400" cannot say which field was
  // too long.
  if (error instanceof Error && error.name === "ZodError") {
    return failure(readableValidationFailure(error), 400);
  }
  return failure("Something went wrong on the server.", 500);
}

/**
 * Turns a validation failure into one sentence.
 *
 * `error.message` on a ZodError is the whole issue list as JSON. It is exactly
 * what you want in a log and exactly what you do not want on a phone screen:
 * several hundred characters of `{"code":"too_big","maximum":80,…}`, which the app
 * would show verbatim because it has no way to know it is not a message.
 *
 * So the first issue is picked out and named. First rather than all of them
 * because fixing one usually fixes the rest, and a list of five is not more
 * helpful than the first.
 */
function readableValidationFailure(error: Error): string {
  const issues = (error as { issues?: { path?: unknown[]; message?: string }[] }).issues;
  const first = Array.isArray(issues) ? issues[0] : undefined;
  if (!first?.message) return "That request was not valid.";
  const field = Array.isArray(first.path) ? first.path.filter(Boolean).join(".") : "";
  return field ? `${field}: ${first.message}` : first.message;
}

/** Reads a JSON body, or throws something `describe` turns into a 400. */
async function body(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    const error = new Error("The request body was not JSON.");
    error.name = "ZodError";
    throw error;
  }
}

/**
 * What the app needs to know before it shows anybody a sign-in button.
 *
 * Without this the app has to guess. A deployment with accounts switched off is
 * indistinguishable from one where signing in is broken, and offering a button
 * that cannot work is worse than offering nothing.
 */
function status(): Response {
  return json({
    // Not a version of the app — a version of this API, so a newer app can tell
    // whether an older server will understand it.
    api: 1,
    accounts: authConfigured,
    // `pglite` means the database is the throwaway one that ships with the app, so
    // anything saved will disappear. The app says so rather than pretending.
    storage: dbSource,
    persistent: dbSource === "neon",
  });
}

/**
 * Handles a request to `/api/v1/*`.
 *
 * Which request means what is decided by `resolveApiV1Route`, in a file with no
 * server imports so it can be tested without a database. All that is left here is
 * carrying it out.
 *
 * Note where the account check happens: once, in one place, driven by
 * `needsAccount` — not scattered through the branches below. Scattered, it is a
 * check that can be missing from one branch, and a missing one has no symptom
 * except that the thing works for people it should not.
 */
export async function handleApiV1(request: Request): Promise<Response> {
  try {
    const url = new URL(request.url);
    const route = resolveApiV1Route(request.method, url.pathname);

    if (route.kind === "notFound") return failure("No such endpoint.", 404);
    if (route.kind === "wrongMethod") {
      return failure(`Use ${route.allowed.join(" or ")}.`, 405);
    }

    const operation = route.operation;
    const userId = needsAccount(operation) ? await requireUserIdForApi(request) : "";

    switch (operation.kind) {
      case "status":
        return status();

      case "providers":
        return providersResponse();

      case "signInStart":
        return startNativeSignIn(request, operation.provider);

      case "signInFinish":
        return finishNativeSignIn(request);

      case "me":
        // Reaching here at all means the token was good — `needsAccount` is true for
        // this one, so a stale token has already been turned into a 401 above. That
        // is exactly what the app uses this for.
        return json({ signedIn: true, id: userId });

      case "listSaves":
        return json({ saves: await listSavesFor(userId) });

      case "createSave": {
        const input = saveInput.parse(await body(request));
        return json(await createSaveFor(userId, input), 201);
      }

      case "loadSave": {
        const save = await loadSaveFor(userId, operation.id);
        // "Not yours" and "not there" are answered identically on purpose. Telling
        // them apart would let somebody test whether an id exists at all.
        return save ? json(save) : failure("No such saved world.", 404);
      }

      case "deleteSave": {
        const deleted = await deleteSaveFor(userId, operation.id);
        return deleted ? json({ ok: true }) : failure("No such saved world.", 404);
      }

      case "listMaps": {
        const query = mapQuery.parse({
          sort: url.searchParams.get("sort") ?? undefined,
          tag: url.searchParams.get("tag") ?? undefined,
          limit: url.searchParams.get("limit") ?? undefined,
        });
        return json({ maps: await listMapsWith(query) });
      }

      case "publishMap": {
        const input = mapInput.parse(await body(request));
        return json(await publishMapFor(userId, input), 201);
      }

      case "loadMap": {
        const map = await loadMapById(operation.id);
        return map ? json(map) : failure("No such world.", 404);
      }

      case "likeMap": {
        const likes = await likeMapById(operation.id);
        return likes === null ? failure("No such world.", 404) : json({ ok: true, likes });
      }

      case "downloadMap": {
        const map = await downloadMapById(operation.id);
        return map ? json(map) : failure("No such world.", 404);
      }
    }
  } catch (error) {
    return describe(error);
  }
}
