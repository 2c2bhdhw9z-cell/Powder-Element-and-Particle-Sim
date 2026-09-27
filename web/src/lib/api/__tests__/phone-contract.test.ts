import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { beforeAll, describe, expect, it, vi } from "vitest";

/**
 * The server's half of the agreement with the phone.
 *
 * `phone-requests.json` is written by the phone's own tests (native/Tests/CrucibleCoreTests/CloudContractTests.swift)
 * from the phone's own path builder and encoder: every request its cloud client makes, byte for byte. This replays
 * each one through the real API handler, against a real database built from the real migrations, and records what
 * came back in `server-replies.json` — which the phone's tests then decode with the phone's own types.
 *
 * Only the sign-in itself is stood in for: a fixed token means a fixed person. Everything after it — the routing,
 * the checking of what was sent, the SQL, the shape of every answer — is the code that runs on the server.
 *
 * After a deliberate change to an answer, record them again with
 *
 *     CRUCIBLE_WRITE_CONTRACT=1 npx vitest run phone-contract
 *
 * and then run the phone's tests, which will say whether the phone can still read them.
 */

const signIn = vi.hoisted(() => {
  class UnauthorizedError extends Error {
    readonly status = 401;
    constructor() {
      super("Unauthorized");
      this.name = "UnauthorizedError";
    }
  }
  return { UnauthorizedError, token: "phone-contract-token", userId: "phone-contract-user" };
});

vi.mock("@/lib/auth/verify.server", () => ({
  UnauthorizedError: signIn.UnauthorizedError,
  requireUserIdForApi: async (request: Request) => {
    if (request.headers.get("authorization") !== `Bearer ${signIn.token}`) {
      throw new signIn.UnauthorizedError();
    }
    return signIn.userId;
  },
}));

vi.mock("@/lib/auth/server", async () => {
  // The real list of ways to sign in, so the phone is tested against what the server really offers.
  const { AUTH_PROVIDERS } = await import("@/lib/auth/providers");
  return { authConfigured: true, auth: {}, AUTH_PROVIDERS, SESSION_TOKEN_COOKIE: "session_token" };
});

import { handleApiV1 } from "@/lib/api/v1.server";
import { resolveApiV1Route } from "@/lib/api/v1-routes";
import { getSql } from "@/lib/db";

type PhoneRequest = {
  name: string;
  method: string;
  path: string;
  operation: string;
  id?: string;
  signedIn: boolean;
  body?: string;
  replay: boolean;
};

type Reply = { name: string; status: number; body: unknown };

const fixtures = join(
  dirname(fileURLToPath(import.meta.url)),
  "../../../../../native/Tests/CrucibleCoreTests/Fixtures",
);
const requestsFile = join(fixtures, "phone-requests.json");
const repliesFile = join(fixtures, "server-replies.json");
const requests = (JSON.parse(readFileSync(requestsFile, "utf8")) as { requests: PhoneRequest[] }).requests;

/** Stand-ins for the ids the server makes up, and a fixed moment for its clock, so the recording is the same every run. */
const recordedMoment = "2026-01-01T00:00:00.000Z";
const isoMoment = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;

function normalised(value: unknown, ids: Map<string, string>): unknown {
  if (typeof value === "string") {
    if (ids.has(value)) return ids.get(value);
    return isoMoment.test(value) ? recordedMoment : value;
  }
  if (Array.isArray(value)) return value.map((item) => normalised(item, ids));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalised(item, ids)]));
  }
  return value;
}

describe("the requests the phone makes", () => {
  /** The server's ids for the save and the map made along the way, by the stand-in the phone's file uses. */
  const made = new Map<string, string>();
  const put = (text: string) => text.replaceAll("SAVE-ID", made.get("SAVE-ID") ?? "SAVE-ID")
    .replaceAll("MAP-ID", made.get("MAP-ID") ?? "MAP-ID");

  beforeAll(async () => {
    // Somebody to be signed in as, so a published world has an author's name to carry.
    const sql = await getSql();
    await sql`
      insert into "user" (id, name, email, "emailVerified")
      values (${signIn.userId}, ${"Test Physicist"}, ${"phone-contract@example.invalid"}, ${true})
      on conflict (id) do nothing`;
  }, 60_000);

  it("are answered in the shape the phone was last shown", async () => {
    const replies: Reply[] = [];
    for (const request of requests) {
      const url = new URL(put(request.path), "https://crucible.test");

      // It reaches the operation it is meant to, with the id it is meant to, once the escaping is undone.
      const route = resolveApiV1Route(request.method, url.pathname);
      expect(route.kind, `${request.name} did not reach anything`).toBe("operation");
      if (route.kind !== "operation") continue;
      expect(route.operation.kind, `${request.name} reached the wrong operation`).toBe(request.operation);
      if (request.id !== undefined) {
        expect("id" in route.operation ? route.operation.id : undefined, `${request.name} arrived with the wrong id`)
          .toBe(put(request.id));
      }
      if (!request.replay) continue;

      const headers = new Headers({ accept: "application/json" });
      if (request.signedIn) headers.set("authorization", `Bearer ${signIn.token}`);
      if (request.body !== undefined) headers.set("content-type", "application/json");
      const response = await handleApiV1(new Request(url, { method: request.method, headers, body: request.body }));
      expect(response.headers.get("content-type") ?? "", `${request.name} was not answered in JSON`)
        .toContain("application/json");
      const body: unknown = await response.json();

      // The ids the rest of the list refers to.
      const id = (body as { id?: unknown }).id;
      if (request.name === "createSave" && typeof id === "string") made.set("SAVE-ID", id);
      if (request.name === "publishMap" && typeof id === "string") made.set("MAP-ID", id);
      replies.push({ name: request.name, status: response.status, body });
    }

    // Recorded with the made-up ids swapped back for their stand-ins, so every run records the same thing.
    const ids = new Map([...made].map(([standIn, real]) => [real, standIn]));
    const recording = `${JSON.stringify({ replies: replies.map((reply) => normalised(reply, ids)) }, null, 2)}\n`;
    if (process.env.CRUCIBLE_WRITE_CONTRACT === "1") {
      writeFileSync(repliesFile, recording);
      return;
    }
    expect(
      recording,
      "The server now answers the phone differently. If that is meant, record it again (see the note at the top) and " +
        "run the phone's tests, which say whether the phone can still read it.",
    ).toBe(readFileSync(repliesFile, "utf8"));
  }, 60_000);
});
