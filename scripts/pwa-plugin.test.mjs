import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import {
  appNameFromHost,
  createHeadInjector,
  injectPwaHead,
  isDocumentPath,
  isInstallQuery,
  renderWebManifest,
  snapshotOgIdentity,
  stripInstallParams,
  xCreatorHeadTags,
} from "./pwa-shared.mjs";
import { renderInstallPage } from "./pwa-plugin.mjs";

const TEMPLATE_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");

test("injects before </head>", () => {
  const out = injectPwaHead("<html><head><title>x</title></head><body></body></html>");
  assert.match(out, /rel="manifest"/);
  assert.match(out, /apple-touch-icon/);
  assert.ok(out.indexOf("manifest") < out.indexOf("</head>"));
});

test("emits the PWA head under /__pwa/", () => {
  const out = injectPwaHead("<html><head></head></html>", { appName: "Demo", site: {} });
  assert.match(out, /rel="manifest" href="\/__pwa\/manifest\.webmanifest"/);
  assert.match(out, /rel="apple-touch-icon" href="\/__pwa\/icon-180\.png"/);
  assert.match(out, /name="apple-mobile-web-app-title" content="Demo"/);
  assert.match(out, /name="apple-mobile-web-app-status-bar-style" content="black"/);
  assert.match(out, /name="theme-color" content="#000000"/);
});

test("does not inject any third-party beacon", () => {
  const out = injectPwaHead("<html><head></head></html>", {
    appName: "Demo",
    projectId: "",
  });
  assert.doesNotMatch(out, /extensions\.js/);
  assert.doesNotMatch(out, /project-id/);
  assert.doesNotMatch(out, /data-project-id/);
  assert.doesNotMatch(out, /property="[a-z-]*:app_id"/);
});

test("ignores a project id and still emits no beacon", () => {
  const out = injectPwaHead("<html><head></head></html>", {
    appName: "Demo",
    projectId: "proj-123",
  });
  assert.doesNotMatch(out, /extensions\.js/);
  assert.doesNotMatch(out, /project-id/);
  assert.doesNotMatch(out, /data-project-id/);
  assert.doesNotMatch(out, /property="[a-z-]*:app_id"/);
});

test("omits x:creator tags without both creator values", () => {
  assert.deepEqual(xCreatorHeadTags("", "42"), []);
  assert.deepEqual(xCreatorHeadTags("@alice", ""), []);
  const out = injectPwaHead("<html><head></head></html>", {
    appName: "Demo",
    projectId: "",
    creator: "@alice",
    creatorId: "",
  });
  assert.doesNotMatch(out, /property="x:creator"/);
});

test("injects x:creator tags when both creator values are set", () => {
  const out = injectPwaHead("<html><head></head></html>", {
    appName: "Demo",
    projectId: "",
    creator: "@alice",
    creatorId: "42",
  });
  assert.match(out, /property="x:creator" content="@alice"/);
  assert.match(out, /property="x:creator:id" content="42"/);
});

test("escapes x:creator values", () => {
  const tags = xCreatorHeadTags('"><script>', '1" onclick="alert(1)');
  assert.equal(tags[0], '<meta property="x:creator" content="&quot;&gt;&lt;script&gt;">');
  assert.equal(tags[1], '<meta property="x:creator:id" content="1&quot; onclick=&quot;alert(1)">');
});

test("does not duplicate x:creator tags", () => {
  const ctx = { appName: "Demo", projectId: "", creator: "@alice", creatorId: "42" };
  const once = injectPwaHead("<html><head></head></html>", ctx);
  const twice = injectPwaHead(once, ctx);
  assert.equal(once, twice);
  assert.equal(twice.split('property="x:creator" content=').length - 1, 1);
  assert.equal(twice.split('property="x:creator:id"').length - 1, 1);
});

test("head chrome overwrites share-card metas and always sets og:title", () => {
  const html =
    '<html><head><title>Hello World</title><meta property="og:title" content="Old"><meta name="twitter:card" content="summary"></head></html>';
  // site: {} isolates this test from the repo's own src/lib/og/site.json
  const out = injectPwaHead(html, { appName: "Wild Race", site: {} });
  assert.match(out, /name="twitter:card" content="summary_large_image"/);
  assert.match(out, /property="og:title" content="Hello World"/);
  assert.doesNotMatch(out, /content="Old"/);
  assert.doesNotMatch(out, /content="summary"/);
  assert.equal(out.split('name="twitter:card"').length - 1, 1);
  assert.equal(out.split('property="og:title"').length - 1, 1);
  assert.doesNotMatch(out, /property="og:image"/);
});

test("does not duplicate twitter:card or og:title", () => {
  const once = injectPwaHead("<html><head><title>Hello World</title></head></html>");
  const twice = injectPwaHead(once);
  assert.equal(once, twice);
  assert.equal(twice.split('name="twitter:card"').length - 1, 1);
  assert.equal(twice.split('property="og:title"').length - 1, 1);
});

test("baked identity does not need a workspace filesystem", () => {
  const empty = mkdtempSync(join(tmpdir(), "og-empty-"));
  const out = injectPwaHead("<html><head></head></html>", {
    host: "app.example.com",
    cwd: empty,
    site: { title: "Pixel Nova", type: "x:game", card: "custom" },
  });
  assert.match(out, /property="og:title" content="Pixel Nova"/);
  assert.match(out, /property="og:type" content="x:game"/);
  assert.match(out, /property="og:image" content="https:\/\/app\.example\.com\/og\.jpg"/);
  // og:image must resolve to the app's OWN host — never an external image service.
  const ogImages = [...out.matchAll(/property="og:image" content="https:\/\/([^/"]+)/g)];
  assert.ok(ogImages.every((m) => m[1] === "app.example.com"));
});

test("explicit site without card=custom emits no og:image and no external card", () => {
  const root = mkdtempSync(join(tmpdir(), "og-card-"));
  mkdirSync(join(root, "public"));
  writeFileSync(join(root, "public/og.jpg"), "x");
  const out = injectPwaHead("<html><head></head></html>", {
    host: "app.example.com",
    cwd: root,
    site: {},
  });
  assert.doesNotMatch(out, /property="og:image"/);
  assert.doesNotMatch(out, /app\.example\.com\/og\.jpg/);
});

test("snapshotOgIdentity stamps card=custom from a public card file", () => {
  const root = mkdtempSync(join(tmpdir(), "og-snap-"));
  mkdirSync(join(root, "public"));
  writeFileSync(join(root, "public/og.jpg"), "x");
  const { site } = snapshotOgIdentity(root);
  assert.equal(site.card, "custom");
  assert.equal(site.image, "/og.jpg");
  assert.equal(site.banner, undefined);
});

test("snapshotOgIdentity stamps banner from public/x-banner.jpg", () => {
  const root = mkdtempSync(join(tmpdir(), "og-banner-"));
  mkdirSync(join(root, "public"));
  writeFileSync(join(root, "public/x-banner.jpg"), "x");
  const { site } = snapshotOgIdentity(root);
  assert.equal(site.banner, "/x-banner.jpg");
});

test("emits x:game:image for a public host when site.banner is set", () => {
  const html = '<html><head><meta property="x:game:image" content="old"></head></html>';
  const out = injectPwaHead(html, {
    host: "app.example.com",
    site: { title: "Wild Race", type: "x:game", card: "custom", banner: "/x-banner.jpg" },
  });
  assert.match(out, /property="x:game:image" content="https:\/\/app\.example\.com\/x-banner\.jpg"/);
  assert.match(out, /property="x:game:image:width" content="1200"/);
  assert.match(out, /property="x:game:image:height" content="264"/);
  assert.doesNotMatch(out, /content="old"/);
  assert.equal(out.split('property="x:game:image"').length - 1, 1);
});

test("does not emit x:game:image without a public host or banner", () => {
  const noHost = injectPwaHead("<html><head></head></html>", {
    site: { banner: "/x-banner.jpg" },
  });
  assert.doesNotMatch(noHost, /x:game:image/);
  const noBanner = injectPwaHead("<html><head></head></html>", {
    host: "app.example.com",
    site: { type: "x:game", card: "custom" },
  });
  assert.doesNotMatch(noBanner, /x:game:image/);
});

test("a site title is used verbatim as og:title", () => {
  const out = injectPwaHead("<html><head></head></html>", {
    host: "app.example.com",
    site: { title: "Some App" },
  });
  assert.match(out, /property="og:title" content="Some App"/);
});

test("document title entities are not double-escaped on og:title", () => {
  // site: {} isolates this test from the repo's own src/lib/og/site.json
  const out = injectPwaHead("<html><head><title>Cats &amp; Dogs</title></head></html>", {
    site: {},
  });
  assert.match(out, /property="og:title" content="Cats &amp; Dogs"/);
  assert.doesNotMatch(out, /Cats &amp;amp; Dogs/);
});

test("site.json title wins over the document title", () => {
  const out = injectPwaHead("<html><head><title>Doc Title</title></head></html>", {
    host: "app.example.com",
    site: { title: "Pixel Nova" },
  });
  assert.match(out, /property="og:title" content="Pixel Nova"/);
});

test("emits og:image only for a custom card on the app's own host", () => {
  // Without a custom card there is no placeholder card anymore: emit none.
  const noCard = injectPwaHead("<html><head></head></html>", {
    appName: "Wild Race",
    host: "app.example.com",
    site: { title: "Wild Race" },
  });
  assert.doesNotMatch(noCard, /property="og:image"/);

  const custom = injectPwaHead("<html><head></head></html>", {
    appName: "Wild Race",
    host: "app.example.com",
    site: { title: "Wild Race", card: "custom", type: "x:game" },
  });
  assert.match(custom, /property="og:image" content="https:\/\/app\.example\.com\/og\.jpg"/);
  assert.match(custom, /property="og:image:width" content="1200"/);
  assert.match(custom, /property="og:type" content="x:game"/);
});

test("injects into documents with no head element", () => {
  // site: {} isolates this test from the repo's own src/lib/og/site.json
  const out = injectPwaHead("<html><body>hi</body></html>", { appName: "Solo", site: {} });
  assert.match(out, /<head>/);
  assert.match(out, /property="og:title" content="Solo"/);
  assert.match(out, /<\/head>/);
});

test("streaming injector matches </HEAD> case-insensitively", () => {
  // site: {} isolates this test from the repo's own src/lib/og/site.json
  const injector = createHeadInjector({ appName: "Wild Race", site: {} });
  const chunks = [
    ...injector.push("<html><HEAD><title>x</title></HE"),
    ...injector.push("AD><body>hello</body></html>"),
  ];
  const out = Buffer.concat(chunks).toString("utf8");
  assert.match(out, /property="og:title" content="x"/);
  assert.match(out, /<body>hello<\/body>/);
});

test("re-injection never introduces a beacon", () => {
  const ctx = { appName: "Demo", projectId: "proj-123" };
  const once = injectPwaHead("<html><head></head></html>", ctx);
  const twice = injectPwaHead(once, ctx);
  assert.equal(once, twice);
  assert.equal(twice.split("extensions.js").length - 1, 0);
});

test("is idempotent", () => {
  const once = injectPwaHead("<html><head></head></html>");
  const twice = injectPwaHead(once);
  assert.equal(once, twice);
});

test("uses the app name in the injected title tag", () => {
  // site: {} isolates this test from the repo's own src/lib/og/site.json
  const out = injectPwaHead("<html><head></head></html>", { appName: "Wild Race", site: {} });
  assert.match(out, /apple-mobile-web-app-title" content="Wild Race"/);
});

test("streaming injector handles </head> split across chunks", () => {
  const injector = createHeadInjector({ appName: "Wild Race" });
  const chunks = [
    ...injector.push("<html><head><title>x</title></he"),
    ...injector.push("ad><body>hello</body></html>"),
  ];
  const out = Buffer.concat(chunks).toString("utf8");
  assert.match(out, /rel="manifest"/);
  assert.ok(out.indexOf("manifest") < out.indexOf("</head>"));
  assert.match(out, /<body>hello<\/body>/);
  assert.deepEqual(injector.flush(), []);
});

test("streaming injector passes post-head chunks through untouched", () => {
  const injector = createHeadInjector();
  injector.push("<html><head></head>");
  const [tail] = injector.push("<body>tail</body>");
  assert.equal(tail.toString("utf8"), "<body>tail</body>");
});

test("streaming injector falls back when no </head> is seen", () => {
  const injector = createHeadInjector();
  assert.deepEqual(injector.push("<html><head>"), []);
  const out = Buffer.concat(injector.flush()).toString("utf8");
  assert.match(out, /rel="manifest"/);
});

test("detects install query", () => {
  assert.equal(isInstallQuery("/?install=1&platform=ios"), true);
  assert.equal(isInstallQuery("/app?foo=1&install=true&platform=ios"), true);
  assert.equal(isInstallQuery("/?install=1"), false);
  assert.equal(isInstallQuery("/?install=1&platform=android"), false);
  assert.equal(isInstallQuery("/?install=0&platform=ios"), false);
  assert.equal(isInstallQuery("/"), false);
});

test("filters non-document paths", () => {
  assert.equal(isDocumentPath("/"), true);
  assert.equal(isDocumentPath("/app"), true);
  assert.equal(isDocumentPath("/api/thing"), false);
  assert.equal(isDocumentPath("/__pwa/install/styles.css"), false);
  assert.equal(isDocumentPath("/logo.png"), false);
});

test("strips install params from the app link", () => {
  assert.equal(stripInstallParams("/?install=1&platform=ios"), "/");
  assert.equal(stripInstallParams("/app?install=1&platform=ios&tab=2"), "/app?tab=2");
});

test("names the install page from the default app name", () => {
  assert.equal(appNameFromHost("localhost:8080"), "Crucible");
  assert.equal(appNameFromHost("172.17.154.217:8080"), "Crucible");
  assert.equal(appNameFromHost("app.example.com"), "Crucible");
});

test("host-derived names never inject markup", () => {
  assert.equal(appNameFromHost("<script>alert(1)</script>"), "Crucible");
  assert.equal(appNameFromHost('"><img src=x onerror=1>.example.com'), "Crucible");
});

test("renders install page markup", () => {
  const html = renderInstallPage("app.example.com", "/?install=1&platform=ios");
  assert.match(html, /Add Crucible to your/);
  assert.match(html, /\/__pwa\/install\/styles\.css/);
  assert.match(html, /href="\/"/);
  assert.equal(html.includes("{{APP_NAME}}"), false);
  assert.equal(html.includes("{{APP_URL}}"), false);
});

test("escapes host-derived values in the install page", () => {
  const html = renderInstallPage("<script>alert(1)</script>", "/?install=1&platform=ios");
  assert.equal(html.includes("<script>alert(1)</script>"), false);
});

test("renders the manifest with the app name and /__pwa/ icon", () => {
  const manifest = JSON.parse(renderWebManifest("app.example.com"));
  assert.equal(manifest.name, "Crucible");
  assert.equal(manifest.short_name, "Crucible");
  assert.equal(manifest.icons[0].src, "/__pwa/icon-180.png");
});

// Tripwires: the deployed-app path only works if Nitro scans server/ — an
// accidental edit that drops serverDir or the middleware file would otherwise
// fail silently (published apps would just render the app for ?install=1).
test("vite config keeps the nitro serverDir wiring", () => {
  const viteConfig = readFileSync(join(TEMPLATE_ROOT, "vite.config.ts"), "utf8");
  assert.match(viteConfig, /serverDir:\s*"\.\/server"/);
  assert.match(viteConfig, /pwaPlugin\(\)/);
});

test("nitro middleware and its bundled assets exist", () => {
  const middleware = readFileSync(join(TEMPLATE_ROOT, "server/middleware/pwa.ts"), "utf8");
  assert.match(middleware, /install-page\.html\?raw/);
  assert.match(middleware, /virtual:og-identity/);
  readFileSync(join(TEMPLATE_ROOT, "scripts/install-page.html"));
  readFileSync(join(TEMPLATE_ROOT, "public/__pwa/icon-180.png"));
  readFileSync(join(TEMPLATE_ROOT, "public/__pwa/install/styles.css"));
});

test("vite plugin bakes og identity as a virtual module", () => {
  const plugin = readFileSync(join(TEMPLATE_ROOT, "scripts/pwa-plugin.mjs"), "utf8");
  assert.match(plugin, /virtual:og-identity/);
  assert.match(plugin, /snapshotOgIdentity/);
});
