export declare const DEFAULT_APP_NAME: string;
export declare const OG_SITE_REL_PATH: string;
export declare function escapeHtml(value: unknown): string;
export declare function appNameFromHost(hostHeader: string | null | undefined): string;
export declare function publicAppHost(hostHeader: string | null | undefined): string;
export declare function resolvePublicHost(hostHeader: string | null | undefined): string;
export declare function isInstallQuery(url: string | null | undefined): boolean;
export declare function isDocumentPath(pathname: string | null | undefined): boolean;
export declare function acceptsHtml(accept: string | null | undefined): boolean;
export declare function stripInstallParams(url: string | null | undefined): string;
export declare function renderInstallPageHtml(
  template: string,
  context?: { host?: string | null; url?: string | null },
): string;
export declare function renderWebManifest(hostHeader: string | null | undefined): string;
export declare function grokPwaHeadTags(appName?: string): Array<[string, string]>;
export declare function readXCreator(): string;
export declare function readXCreatorId(): string;
export declare function grokXCreatorHeadTags(creator?: string, creatorId?: string): string[];

export type OgSite = {
  title?: string;
  description?: string;
  type?: string;
  card?: string;
  image?: string;
  banner?: string;
  color?: string;
};

export type GrokHeadContext = {
  appName?: string;
  creator?: string;
  creatorId?: string;
  host?: string | null;
  cwd?: string;
  site?: OgSite;
};

export declare function readOgSite(cwd?: string): OgSite;
export declare function snapshotOgIdentity(cwd?: string): { site: OgSite };
export declare function customOgAssetPath(cwd?: string): string;
export declare function titleFromDocument(html: string): string;
export declare function resolveOgTitle(
  site?: OgSite,
  appName?: string,
  host?: string,
  documentTitle?: string,
): string;
export declare function siteHasCustomCard(site?: OgSite): boolean;
export declare function grokOgHeadTags(ctx?: {
  host?: string;
  appName?: string;
  site?: OgSite;
  documentTitle?: string;
}): string[];
export declare function stripShareMetaTags(html: string): string;
export declare function normalizeHeadContext(ctx?: GrokHeadContext): {
  appName: string;
  creator: string;
  creatorId: string;
  host: string;
  cwd: string;
  site: OgSite;
};
export declare function injectGrokPwaHead(html: string, ctx?: GrokHeadContext): string;
export declare function createHeadInjector(ctx?: GrokHeadContext): {
  push(chunk: Uint8Array | string): Uint8Array[];
  flush(): Uint8Array[];
};
