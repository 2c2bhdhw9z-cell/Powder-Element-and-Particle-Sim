/**
 * The web app's way in: TanStack server functions.
 *
 * Deliberately thin. Every query and every limit lives in `lab-store.ts`,
 * because the iOS app reaches the same data over ordinary HTTP routes
 * (`src/routes/api/v1/`) and two copies of a `where user_id = …` is one copy
 * that eventually gets forgotten — with no outward sign except somebody seeing
 * another person's saves.
 *
 * So what is left here is the part that is genuinely specific to this caller:
 * establishing who is asking, via `authMiddleware`.
 */
import { createServerFn } from "@tanstack/react-start";
import { authMiddleware } from "@/lib/auth/middleware";
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

export const listSaves = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .handler(({ context }) => listSavesFor(context.userId));

export const loadSave = createServerFn({ method: "GET" })
  .middleware([authMiddleware])
  .validator((id: string) => id)
  .handler(({ context, data: id }) => loadSaveFor(context.userId, id));

export const createSave = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((input: unknown) => saveInput.parse(input))
  .handler(({ context, data }) => createSaveFor(context.userId, data));

export const deleteSave = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((id: string) => id)
  .handler(async ({ context, data: id }) => {
    const deleted = await deleteSaveFor(context.userId, id);
    return { ok: deleted };
  });

export const listMaps = createServerFn({ method: "GET" }).handler(() =>
  listMapsWith(mapQuery.parse({})),
);

export const loadMap = createServerFn({ method: "GET" })
  .validator((id: string) => id)
  .handler(({ data: id }) => loadMapById(id));

export const publishMap = createServerFn({ method: "POST" })
  .middleware([authMiddleware])
  .validator((input: unknown) => mapInput.parse(input))
  .handler(({ context, data }) => publishMapFor(context.userId, data));

export const likeMap = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(async ({ data: id }) => {
    const likes = await likeMapById(id);
    return { ok: likes !== null, likes };
  });

export const downloadMap = createServerFn({ method: "POST" })
  .validator((id: string) => id)
  .handler(({ data: id }) => downloadMapById(id));
