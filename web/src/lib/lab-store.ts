/**
 * Every query the lab makes, and every rule about what may go into one.
 *
 * ## Why this exists separately from `lab-api.ts`
 *
 * There are two ways into this data now. The web app calls TanStack **server
 * functions** — an arrangement where the client is generated from the server's
 * types, so there are no URLs at all. The iOS app cannot use that; it needs
 * ordinary HTTP routes, which live under `src/routes/api/v1/`.
 *
 * Two callers, one set of queries. The obvious alternative — write the routes
 * out again alongside the server functions — means every column rename has to
 * be made twice, and the second one is the one that gets missed. Worse, so does
 * every `where user_id = …`: a route that forgets it returns somebody else's
 * saves, and nothing about that looks wrong from the outside.
 *
 * So: the SQL and the validation are here, once. `lab-api.ts` and the v1 routes
 * are both thin wrappers that establish *who is asking* and then call these.
 *
 * ## The rules travel with the queries
 *
 * The size limits below were previously enforced by the server function's
 * validator. A route does not go through that validator, so if the limits had
 * been left there, the HTTP path would have had none — and an eight-megabyte
 * limit that one of two callers ignores is not a limit. They are exported from
 * here and applied by both.
 *
 * Server-only: this imports the database.
 */
import { getSql } from "@/lib/db";
import { z } from "zod";

/** A short, sortable, unguessable-enough id. */
export function newId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

// MARK: - What may be sent

export const saveInput = z.object({
  name: z.string().min(1).max(80),
  mode: z.enum(["powder", "particle"]),
  // Eight megabytes. A world at the largest size anything offers is well under
  // this; it is here to stop a single row making the table unusable.
  data: z.string().min(1).max(8_000_000),
});
export type SaveInput = z.infer<typeof saveInput>;

export const mapInput = z.object({
  title: z.string().min(1).max(80),
  description: z.string().max(400).default(""),
  tags: z.string().max(120).default(""),
  thumbnail: z.string().max(400_000).default(""),
  gridData: z.string().min(1).max(8_000_000),
});
export type MapInput = z.infer<typeof mapInput>;

/** How the workshop may be ordered. */
export const mapSort = z.enum(["recent", "popular", "downloaded"]);
export type MapSort = z.infer<typeof mapSort>;

export const mapQuery = z.object({
  sort: mapSort.default("recent"),
  /** Matched anywhere in the tag list. Empty means everything. */
  tag: z.string().max(60).default(""),
  limit: z.coerce.number().int().min(1).max(60).default(60),
});
export type MapQuery = z.infer<typeof mapQuery>;

// MARK: - Rows, as they go out

export type SaveSummary = {
  id: string;
  name: string;
  mode: string;
  created_at: string;
};

export type SaveRow = SaveSummary & { data: string };

export type MapSummary = {
  id: string;
  title: string;
  author: string;
  description: string;
  tags: string;
  thumbnail: string;
  likes: number;
  downloads: number;
  created_at: string;
};

export type MapRow = { id: string; title: string; grid_data: string };

// MARK: - Saves

/**
 * Somebody's own saved worlds.
 *
 * Forty, newest first, matching the index on the table. Every query in this file
 * that touches `lab_saves` is scoped by `user_id` — there is no unscoped read of
 * it anywhere, which is the property worth keeping true.
 */
export async function listSavesFor(userId: string): Promise<SaveSummary[]> {
  const sql = await getSql();
  return sql<SaveSummary>`
    select id, name, mode, created_at
    from lab_saves
    where user_id = ${userId}
    order by created_at desc
    limit 40`;
}

export async function loadSaveFor(userId: string, id: string): Promise<SaveRow | null> {
  const sql = await getSql();
  const rows = await sql<SaveRow>`
    select id, name, mode, data, created_at
    from lab_saves
    where id = ${id} and user_id = ${userId}
    limit 1`;
  return rows[0] ?? null;
}

export async function createSaveFor(userId: string, input: SaveInput): Promise<{ id: string }> {
  const sql = await getSql();
  const id = newId();
  await sql`
    insert into lab_saves (id, user_id, name, mode, data)
    values (${id}, ${userId}, ${input.name}, ${input.mode}, ${input.data})`;
  return { id };
}

/**
 * Removes one of somebody's saves.
 *
 * - Returns: whether a row was actually theirs to delete. Reported rather than
 *   swallowed, so a caller can answer "not found" instead of claiming success
 *   for a deletion that did not happen.
 */
export async function deleteSaveFor(userId: string, id: string): Promise<boolean> {
  const sql = await getSql();
  const rows = await sql<{ id: string }>`
    delete from lab_saves
    where id = ${id} and user_id = ${userId}
    returning id`;
  return rows.length > 0;
}

// MARK: - The workshop

/**
 * Published worlds.
 *
 * The ordering cannot be a parameter — no database lets you bind a column name —
 * so it is chosen from a fixed set here. That is the whole reason `sort` is an
 * enum rather than a string: the alternative is pasting a caller's text into the
 * query, which is exactly how a listing endpoint becomes a way to read the
 * users table.
 */
export async function listMapsWith(query: MapQuery): Promise<MapSummary[]> {
  const sql = await getSql();
  const order =
    query.sort === "popular"
      ? "likes desc, created_at desc"
      : query.sort === "downloaded"
        ? "downloads desc, created_at desc"
        : "created_at desc";

  const columns =
    "id, title, author, description, tags, thumbnail, likes, downloads, created_at";

  if (query.tag) {
    // `position` rather than `like`, so a tag containing % or _ is matched as
    // written instead of being read as a pattern.
    return sql.query<MapSummary>(
      `select ${columns} from lab_maps
       where position(lower($1) in lower(tags)) > 0
       order by ${order} limit $2`,
      [query.tag, query.limit],
    );
  }
  return sql.query<MapSummary>(
    `select ${columns} from lab_maps order by ${order} limit $1`,
    [query.limit],
  );
}

export async function loadMapById(id: string): Promise<MapRow | null> {
  const sql = await getSql();
  const rows = await sql<MapRow>`
    select id, title, grid_data from lab_maps where id = ${id} limit 1`;
  return rows[0] ?? null;
}

export async function publishMapFor(userId: string, input: MapInput): Promise<{ id: string }> {
  const sql = await getSql();
  const id = newId();
  const authorRows = await sql<{ name: string | null }>`
    select name from "user" where id = ${userId} limit 1`;
  const author = authorRows[0]?.name?.trim() || "Physicist";
  await sql`
    insert into lab_maps (id, user_id, title, author, description, tags, thumbnail, grid_data)
    values (${id}, ${userId}, ${input.title}, ${author}, ${input.description},
            ${input.tags}, ${input.thumbnail}, ${input.gridData})`;
  return { id };
}

/**
 * Adds a like.
 *
 * - Returns: the new count, or `null` if there is no such world. Returning the
 *   count means a caller can show the new number without asking again — and
 *   returning `null` means it can tell "liked" from "that does not exist",
 *   which the previous version reported identically.
 */
export async function likeMapById(id: string): Promise<number | null> {
  const sql = await getSql();
  const rows = await sql<{ likes: number }>`
    update lab_maps set likes = likes + 1 where id = ${id} returning likes`;
  return rows[0]?.likes ?? null;
}

/**
 * Counts a download and hands back the world.
 *
 * One statement rather than an update followed by a read. Two statements can
 * disagree — the row can be removed in between — and then a download is counted
 * against something that is no longer there.
 */
export async function downloadMapById(id: string): Promise<MapRow | null> {
  const sql = await getSql();
  const rows = await sql<MapRow>`
    update lab_maps set downloads = downloads + 1
    where id = ${id}
    returning id, title, grid_data`;
  return rows[0] ?? null;
}
