import { createServerFn } from "@tanstack/react-start";
import { getSql } from "@/lib/db";
import { authMiddleware } from "@/lib/auth/middleware";
import { z } from "zod";

function newId() {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

const saveInput = z.object({
  name: z.string().min(1).max(80),
  mode: z.enum(["powder", "particle"]),
  data: z.string().min(1).max(8_000_000),
});

export const listSaves = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(async ({ context }) => {
    const sql = await getSql();
    return sql<{
      id: string;
      name: string;
      mode: string;
      created_at: string;
    }>`select id, name, mode, created_at from lab_saves where user_id = ${context.userId} order by created_at desc limit 40`;
  });

export const loadSave = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((id: string) => id)
  .handler(async ({ context, data: id }) => {
    const sql = await getSql();
    const rows = await sql<{
      id: string;
      name: string;
      mode: string;
      data: string;
    }>`select id, name, mode, data from lab_saves where id = ${id} and user_id = ${context.userId} limit 1`;
    return rows[0] ?? null;
  });

export const createSave = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((input: unknown) => saveInput.parse(input))
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const id = newId();
    await sql`insert into lab_saves (id, user_id, name, mode, data) values (${id}, ${context.userId}, ${data.name}, ${data.mode}, ${data.data})`;
    return { id };
  });

export const deleteSave = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((id: string) => id)
  .handler(async ({ context, data: id }) => {
    const sql = await getSql();
    await sql`delete from lab_saves where id = ${id} and user_id = ${context.userId}`;
    return { ok: true };
  });

const mapInput = z.object({
  title: z.string().min(1).max(80),
  description: z.string().max(400).default(""),
  tags: z.string().max(120).default(""),
  thumbnail: z.string().max(400_000).default(""),
  gridData: z.string().min(1).max(8_000_000),
});

export const listMaps = createServerFn({ method: "GET" }).handler(async () => {
  const sql = await getSql();
  return sql<{
    id: string;
    title: string;
    author: string;
    description: string;
    tags: string;
    thumbnail: string;
    likes: number;
    downloads: number;
    created_at: string;
  }>`select id, title, author, description, tags, thumbnail, likes, downloads, created_at from lab_maps order by created_at desc limit 60`;
});

export const loadMap = createServerFn({ method: "GET" })
  .validator((id: string) => id)
  .handler(async ({ data: id }) => {
    const sql = await getSql();
    const rows = await sql<{
      id: string;
      title: string;
      grid_data: string;
    }>`select id, title, grid_data from lab_maps where id = ${id} limit 1`;
    return rows[0] ?? null;
  });

export const publishMap = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((input: unknown) => mapInput.parse(input))
  .handler(async ({ context, data }) => {
    const sql = await getSql();
    const id = newId();
    const authorRows = await sql<{ name: string | null }>`select name from "user" where id = ${context.userId} limit 1`;
    const author = authorRows[0]?.name?.trim() || "Physicist";
    await sql`insert into lab_maps (id, user_id, title, author, description, tags, thumbnail, grid_data)
      values (${id}, ${context.userId}, ${data.title}, ${author}, ${data.description}, ${data.tags}, ${data.thumbnail}, ${data.gridData})`;
    return { id };
  });

export const likeMap = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(async ({ data: id }) => {
    const sql = await getSql();
    await sql`update lab_maps set likes = likes + 1 where id = ${id}`;
    return { ok: true };
  });

export const downloadMap = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(async ({ data: id }) => {
    const sql = await getSql();
    await sql`update lab_maps set downloads = downloads + 1 where id = ${id}`;
    const rows = await sql<{ grid_data: string }>`select grid_data from lab_maps where id = ${id} limit 1`;
    return rows[0] ?? null;
  });
