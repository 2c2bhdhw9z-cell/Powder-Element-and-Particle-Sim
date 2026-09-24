import { describe, expect, it } from "vitest";
import {
  allApiV1Operations,
  apiV1Segments,
  needsAccount,
  resolveApiV1Route,
  type ApiV1Operation,
} from "../v1-routes";

/**
 * The API's routing table.
 *
 * Worth testing separately from the handlers, and it is why they were separated:
 * every failure here is silent. A path that resolves to the wrong operation, a
 * method that is accepted when it should not be, an id that arrives still escaped —
 * none of those throw. They just quietly do the wrong thing.
 *
 * The most important test in the file is the last one. It walks every operation
 * there is and asserts which need an account, because a route that forgets to
 * require one works perfectly for everybody, including the people it should be
 * keeping out.
 */

/** The operation a request resolves to, or `null` if it does not resolve to one. */
function operationFor(method: string, path: string): ApiV1Operation | null {
  const route = resolveApiV1Route(method, path);
  return route.kind === "operation" ? route.operation : null;
}

describe("splitting a path", () => {
  it("ignores the prefix, and tolerates it being absent", () => {
    expect(apiV1Segments("/api/v1/saves")).toEqual(["saves"]);
    expect(apiV1Segments("/saves")).toEqual(["saves"]);
  });

  it("is not thrown off by extra or missing slashes", () => {
    // A trailing slash used to shift every segment along, which turned a perfectly
    // valid request into "no such endpoint".
    expect(apiV1Segments("/api/v1/saves/")).toEqual(["saves"]);
    expect(apiV1Segments("/api/v1//saves//abc//")).toEqual(["saves", "abc"]);
    expect(apiV1Segments("/api/v1")).toEqual([]);
    expect(apiV1Segments("/api/v1/")).toEqual([]);
  });

  it("decodes an id, so one with a space or a slash in it arrives as written", () => {
    expect(apiV1Segments("/api/v1/saves/a%20b")).toEqual(["saves", "a b"]);
    expect(apiV1Segments("/api/v1/saves/a%2Fb")).toEqual(["saves", "a/b"]);
  });

  it("does not throw on a malformed escape", () => {
    // It will not match any id, so it becomes an ordinary "not found" — but it must
    // not take the whole request down on the way there.
    expect(() => apiV1Segments("/api/v1/saves/%ZZ")).not.toThrow();
    expect(resolveApiV1Route("GET", "/api/v1/saves/%ZZ").kind).toBe("operation");
  });
});

describe("resolving a request", () => {
  it("maps every path and method to the right thing", () => {
    expect(operationFor("GET", "/api/v1/status")).toEqual({ kind: "status" });

    expect(operationFor("GET", "/api/v1/saves")).toEqual({ kind: "listSaves" });
    expect(operationFor("POST", "/api/v1/saves")).toEqual({ kind: "createSave" });
    expect(operationFor("GET", "/api/v1/saves/abc")).toEqual({ kind: "loadSave", id: "abc" });
    expect(operationFor("DELETE", "/api/v1/saves/abc")).toEqual({
      kind: "deleteSave",
      id: "abc",
    });

    expect(operationFor("GET", "/api/v1/maps")).toEqual({ kind: "listMaps" });
    expect(operationFor("POST", "/api/v1/maps")).toEqual({ kind: "publishMap" });
    expect(operationFor("GET", "/api/v1/maps/xyz")).toEqual({ kind: "loadMap", id: "xyz" });
    expect(operationFor("POST", "/api/v1/maps/xyz/like")).toEqual({
      kind: "likeMap",
      id: "xyz",
    });
    expect(operationFor("POST", "/api/v1/maps/xyz/download")).toEqual({
      kind: "downloadMap",
      id: "xyz",
    });
  });

  it("accepts a method in any case, as a client might send it", () => {
    expect(operationFor("get", "/api/v1/saves")).toEqual({ kind: "listSaves" });
    expect(operationFor("Post", "/api/v1/saves")).toEqual({ kind: "createSave" });
  });

  /**
   * The distinction matters to the app. "Wrong method" means the app has a bug;
   * "not found" means the server is older than the app expects. Collapsing both
   * into 404 would leave it unable to tell those apart.
   */
  it("tells a wrong method apart from a path that does not exist", () => {
    expect(resolveApiV1Route("DELETE", "/api/v1/maps")).toEqual({
      kind: "wrongMethod",
      allowed: ["GET", "POST"],
    });
    expect(resolveApiV1Route("PUT", "/api/v1/status")).toEqual({
      kind: "wrongMethod",
      allowed: ["GET"],
    });
    expect(resolveApiV1Route("DELETE", "/api/v1/maps/xyz")).toEqual({
      kind: "wrongMethod",
      allowed: ["GET"],
    });
    expect(resolveApiV1Route("GET", "/api/v1/maps/xyz/like")).toEqual({
      kind: "wrongMethod",
      allowed: ["POST"],
    });
  });

  it("refuses anything it does not recognise", () => {
    for (const path of [
      "/api/v1",
      "/api/v1/",
      "/api/v1/nonsense",
      "/api/v1/saves/abc/extra",
      "/api/v1/maps/xyz/nonsense",
      "/api/v1/maps/xyz/like/again",
      "/api/v1/status/extra",
      "/api/v1/SAVES",
    ]) {
      expect(resolveApiV1Route("GET", path).kind, `for ${path}`).toBe("notFound");
    }
  });

  /**
   * Deleting is scoped to one save. A request that resolved to something broader
   * because a segment went missing would delete more than was asked, so the shape
   * of the path is checked rather than just its start.
   */
  it("does not let a shortened path become a broader operation", () => {
    expect(resolveApiV1Route("DELETE", "/api/v1/saves").kind).toBe("wrongMethod");
    expect(resolveApiV1Route("DELETE", "/api/v1/saves/").kind).toBe("wrongMethod");
  });
});

describe("who has to be signed in", () => {
  /**
   * The one that would be silent. Walked over every operation rather than spot
   * checked, so an operation added without a decision fails here — and the switch
   * in `needsAccount` fails to compile, which is the other half of the same guard.
   */
  it("is decided for every single operation", () => {
    const answers = new Map(allApiV1Operations.map((op) => [op.kind, needsAccount(op)]));

    expect(answers.size).toBe(allApiV1Operations.length);
    expect(Object.fromEntries(answers)).toEqual({
      // Asking whether the server works needs nothing.
      status: false,
      // Somebody's own worlds. Every query for these is scoped by user id, which is
      // meaningless without knowing whose.
      listSaves: true,
      createSave: true,
      loadSave: true,
      deleteSave: true,
      // Putting a name on something needs somebody to name.
      publishMap: true,
      // Browsing, liking and downloading published worlds need nothing — matching
      // the website exactly, because the app must not be a way around its rules.
      listMaps: false,
      loadMap: false,
      likeMap: false,
      downloadMap: false,
    });
  });

  it("requires an account for everything that touches one person's own saves", () => {
    for (const path of ["/api/v1/saves", "/api/v1/saves/abc"]) {
      for (const method of ["GET", "POST", "DELETE"]) {
        const route = resolveApiV1Route(method, path);
        if (route.kind !== "operation") continue;
        expect(needsAccount(route.operation), `${method} ${path}`).toBe(true);
      }
    }
  });
});
