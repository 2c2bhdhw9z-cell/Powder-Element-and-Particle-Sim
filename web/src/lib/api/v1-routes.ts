/**
 * Which request means which operation.
 *
 * Separated from `v1.server.ts` on purpose, and with no server imports at all, so
 * it can be tested without starting a database. What is left in the server file is
 * the part that actually does something; this is the part that decides *what* —
 * path parsing, method matching, and which operations need an account.
 *
 * The last of those is the reason this split is worth having. A route that forgets
 * to require an account is a bug with no outward symptom: it works perfectly, for
 * everybody, including people who should not be able to reach it. `needsAccount`
 * below is a single table, and the test alongside it asserts the answer for every
 * operation there is — so adding one without deciding this is not possible.
 */

/** Everything the API can be asked to do. */
export type ApiV1Operation =
  | { kind: "status" }
  | { kind: "listSaves" }
  | { kind: "createSave" }
  | { kind: "loadSave"; id: string }
  | { kind: "deleteSave"; id: string }
  | { kind: "listMaps" }
  | { kind: "publishMap" }
  | { kind: "loadMap"; id: string }
  | { kind: "likeMap"; id: string }
  | { kind: "downloadMap"; id: string };

/** What a request resolved to, including the ways it did not resolve. */
export type ApiV1Route =
  | { kind: "operation"; operation: ApiV1Operation }
  | { kind: "notFound" }
  | { kind: "wrongMethod"; allowed: readonly string[] };

/** The prefix every path sits under. */
export const apiV1Prefix = "/api/v1";

function operation(operation: ApiV1Operation): ApiV1Route {
  return { kind: "operation", operation };
}

function wrongMethod(...allowed: string[]): ApiV1Route {
  return { kind: "wrongMethod", allowed };
}

const notFound: ApiV1Route = { kind: "notFound" };

/**
 * Splits a path into its parts.
 *
 * Empty parts are dropped, so a trailing slash or a doubled one does not shift
 * every segment along and turn a valid path into a 404. Each part is decoded, so
 * an id containing a slash or a space arrives as it was written.
 */
export function apiV1Segments(pathname: string): string[] {
  const path = pathname.startsWith(apiV1Prefix) ? pathname.slice(apiV1Prefix.length) : pathname;
  return path
    .split("/")
    .filter((part) => part.length > 0)
    .map((part) => {
      try {
        return decodeURIComponent(part);
      } catch {
        // A malformed escape. Left as written rather than throwing — it will not
        // match any id, so it becomes an ordinary "not found".
        return part;
      }
    });
}

/** Works out what a request is asking for. */
export function resolveApiV1Route(method: string, pathname: string): ApiV1Route {
  const segments = apiV1Segments(pathname);
  const verb = method.toUpperCase();

  if (segments.length === 1 && segments[0] === "status") {
    return verb === "GET" ? operation({ kind: "status" }) : wrongMethod("GET");
  }

  if (segments[0] === "saves") {
    if (segments.length === 1) {
      if (verb === "GET") return operation({ kind: "listSaves" });
      if (verb === "POST") return operation({ kind: "createSave" });
      return wrongMethod("GET", "POST");
    }
    if (segments.length === 2) {
      const id = segments[1];
      if (verb === "GET") return operation({ kind: "loadSave", id });
      if (verb === "DELETE") return operation({ kind: "deleteSave", id });
      return wrongMethod("GET", "DELETE");
    }
    return notFound;
  }

  if (segments[0] === "maps") {
    if (segments.length === 1) {
      if (verb === "GET") return operation({ kind: "listMaps" });
      if (verb === "POST") return operation({ kind: "publishMap" });
      return wrongMethod("GET", "POST");
    }
    const id = segments[1];
    if (segments.length === 2) {
      return verb === "GET" ? operation({ kind: "loadMap", id }) : wrongMethod("GET");
    }
    if (segments.length === 3 && segments[2] === "like") {
      return verb === "POST" ? operation({ kind: "likeMap", id }) : wrongMethod("POST");
    }
    if (segments.length === 3 && segments[2] === "download") {
      return verb === "POST" ? operation({ kind: "downloadMap", id }) : wrongMethod("POST");
    }
    return notFound;
  }

  return notFound;
}

/**
 * Which operations need a signed-in account.
 *
 * Written as an exhaustive switch rather than a list of the ones that do. A list
 * can be added to without noticing; a switch over a union fails to compile the
 * moment an operation exists that nobody has decided about.
 *
 * The three that do *not* need one — browsing, liking and downloading published
 * worlds — match the website exactly. That is the point: the two ways in must
 * agree about who may do what, or the app becomes a way around the website's
 * rules.
 */
export function needsAccount(operation: ApiV1Operation): boolean {
  switch (operation.kind) {
    case "status":
      return false;
    case "listSaves":
    case "createSave":
    case "loadSave":
    case "deleteSave":
      // Somebody's own worlds. Every one of these is scoped by user id in
      // `lab-store.ts`, and the scoping is meaningless without knowing who it is.
      return true;
    case "publishMap":
      // Publishing puts a name on something, so it needs somebody to name.
      return true;
    case "listMaps":
    case "loadMap":
    case "likeMap":
    case "downloadMap":
      return false;
  }
}

/** Every operation there is, so a test can walk the whole set. */
export const allApiV1Operations: readonly ApiV1Operation[] = [
  { kind: "status" },
  { kind: "listSaves" },
  { kind: "createSave" },
  { kind: "loadSave", id: "x" },
  { kind: "deleteSave", id: "x" },
  { kind: "listMaps" },
  { kind: "publishMap" },
  { kind: "loadMap", id: "x" },
  { kind: "likeMap", id: "x" },
  { kind: "downloadMap", id: "x" },
];
