import { readFile } from "node:fs/promises";
import path from "node:path";
import {
  type ShowCatalogClipEntry,
  type ShowCatalogStaticEntry,
  type ShowMediaCatalog,
  type ShowSceneKey
} from "@conductor/protocol";
import { logger } from "../utils/logger";

const showSceneKeys: ShowSceneKey[] = [
  "interstitial",
  "preshow",
  "introduction",
  "mainStatic",
  "mainDynamic",
  "ending"
];

const isRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const toFiniteNumber = (value: unknown): number | null => {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
};

const normalizeString = (value: unknown): string | null => {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const resolveUrl = (value: string | null, baseUrl: string | null): string | null => {
  if (!value) {
    return null;
  }
  if (/^https?:\/\//i.test(value)) {
    return value;
  }
  if (baseUrl && /^https?:\/\//i.test(baseUrl)) {
    try {
      return new URL(value, baseUrl).toString();
    } catch {
      return value;
    }
  }
  return value;
};

const toSceneKey = (value: unknown): ShowSceneKey | undefined => {
  if (typeof value !== "string") {
    return undefined;
  }
  if (showSceneKeys.includes(value as ShowSceneKey)) {
    return value as ShowSceneKey;
  }
  const normalized = value.trim().toLowerCase();
  if (normalized === "main" || normalized === "main-01" || normalized === "main-1" || normalized === "mainstatic") {
    return "mainStatic";
  }
  if (normalized === "maindynamic" || normalized === "dynamic") {
    return "mainDynamic";
  }
  if (normalized === "preshow" || normalized === "introduction" || normalized === "ending" || normalized === "interstitial") {
    return normalized as ShowSceneKey;
  }
  return undefined;
};

const parseCatalogClipEntries = (
  value: unknown,
  baseUrl: string | null,
  fallbackDomain: "interstitial" | "dynamic"
): ShowCatalogClipEntry[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((entry, index): ShowCatalogClipEntry | null => {
      if (!isRecord(entry)) {
        return null;
      }
      const clipId =
        normalizeString(entry.clipId) ??
        normalizeString(entry.id) ??
        normalizeString(entry.key) ??
        `${fallbackDomain}-${index + 1}`;
      const masterUrlRaw =
        normalizeString(entry.masterUrl) ??
        normalizeString(entry.url) ??
        normalizeString(entry.master) ??
        normalizeString(entry.masterPlaylist);
      const masterUrl = resolveUrl(masterUrlRaw, baseUrl);
      if (!clipId || !masterUrl) {
        return null;
      }

      const durationMs =
        Math.max(
          1,
          Math.round(
            toFiniteNumber(entry.durationMs) ??
              ((toFiniteNumber(entry.durationSeconds) ?? toFiniteNumber(entry.durationSec) ?? 0) * 1000)
          )
        ) || 1;
      const weight = Math.max(0, toFiniteNumber(entry.weight) ?? 1);
      const tags = Array.isArray(entry.tags)
        ? entry.tags.filter((tag): tag is string => typeof tag === "string" && tag.trim().length > 0)
        : undefined;

      return {
        clipId,
        masterUrl,
        durationMs,
        weight,
        tags
      };
    })
    .filter((entry): entry is ShowCatalogClipEntry => Boolean(entry));
};

const parseCatalogStaticEntries = (value: unknown, baseUrl: string | null): ShowCatalogStaticEntry[] => {
  if (Array.isArray(value)) {
    return value
      .map((entry): ShowCatalogStaticEntry | null => {
        if (!isRecord(entry)) {
          return null;
        }
        const slot = normalizeString(entry.slot) ?? normalizeString(entry.id) ?? normalizeString(entry.laneId);
        const scene = toSceneKey(entry.scene ?? entry.sceneKey ?? slot);
        const masterUrlRaw =
          normalizeString(entry.masterUrl) ??
          normalizeString(entry.url) ??
          normalizeString(entry.master) ??
          normalizeString(entry.masterPlaylist);
        const masterUrl = resolveUrl(masterUrlRaw, baseUrl);
        if (!slot || !masterUrl) {
          return null;
        }
        const clipId = normalizeString(entry.clipId) ?? undefined;
        return {
          slot,
          scene,
          masterUrl,
          clipId
        };
      })
      .filter((entry): entry is ShowCatalogStaticEntry => Boolean(entry));
  }

  if (isRecord(value)) {
    const entries: ShowCatalogStaticEntry[] = [];
    for (const [slot, masterValue] of Object.entries(value)) {
      const masterUrl = resolveUrl(normalizeString(masterValue), baseUrl);
      if (!masterUrl) {
        continue;
      }
      entries.push({
        slot,
        scene: toSceneKey(slot),
        masterUrl
      });
    }
    return entries;
  }

  return [];
};

export const inferCatalogUrlFromBaseUrl = (baseUrl: string): string => {
  const trimmed = baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`;
  return new URL("catalog.json", trimmed).toString();
};

export const parseShowMediaCatalog = (
  value: unknown,
  options: {
    baseUrl?: string | null;
    sourceLabel?: string;
  } = {}
): ShowMediaCatalog | null => {
  if (!isRecord(value)) {
    return null;
  }

  const baseUrl = options.baseUrl ?? null;
  const interstitial = parseCatalogClipEntries(value.interstitial, baseUrl, "interstitial");
  const dynamic = parseCatalogClipEntries(value.dynamic, baseUrl, "dynamic");
  const staticEntries = parseCatalogStaticEntries(value.static, baseUrl);

  const version = normalizeString(value.version) ?? `catalog-${Date.now()}`;
  const generatedAtMs = Math.max(0, Math.round(toFiniteNumber(value.generatedAtMs ?? value.generatedAt) ?? Date.now()));

  return {
    version,
    generatedAtMs,
    interstitial,
    dynamic,
    static: staticEntries
  };
};

const readCatalogFromFile = async (filePath: string): Promise<unknown | null> => {
  try {
    const raw = await readFile(filePath, "utf8");
    return JSON.parse(raw) as unknown;
  } catch (error) {
    logger.warn("failed to read media catalog file", {
      filePath,
      message: error instanceof Error ? error.message : String(error)
    });
    return null;
  }
};

const readCatalogFromHttp = async (url: string): Promise<unknown | null> => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6_000);
  timeout.unref();
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        accept: "application/json"
      },
      signal: controller.signal
    });
    if (!response.ok) {
      logger.warn("failed to fetch media catalog", {
        url,
        status: response.status
      });
      return null;
    }
    return (await response.json()) as unknown;
  } catch (error) {
    logger.warn("failed to fetch media catalog", {
      url,
      message: error instanceof Error ? error.message : String(error)
    });
    return null;
  } finally {
    clearTimeout(timeout);
  }
};

export const loadShowMediaCatalog = async (catalogUrlOrPath: string): Promise<ShowMediaCatalog | null> => {
  const normalized = catalogUrlOrPath.trim();
  if (normalized.length === 0) {
    return null;
  }

  let parsed: unknown | null = null;
  let baseUrl: string | null = null;

  if (/^https?:\/\//i.test(normalized)) {
    parsed = await readCatalogFromHttp(normalized);
    try {
      baseUrl = new URL(".", normalized).toString();
    } catch {
      baseUrl = null;
    }
  } else if (normalized.startsWith("file://")) {
    const fileUrl = new URL(normalized);
    const filePath = fileUrl.pathname;
    parsed = await readCatalogFromFile(filePath);
    baseUrl = null;
  } else {
    const filePath = path.resolve(normalized);
    parsed = await readCatalogFromFile(filePath);
    baseUrl = null;
  }

  const catalog = parseShowMediaCatalog(parsed, {
    baseUrl,
    sourceLabel: normalized
  });
  if (!catalog) {
    return null;
  }

  logger.info("loaded media catalog", {
    source: normalized,
    version: catalog.version,
    interstitialCount: catalog.interstitial.length,
    dynamicCount: catalog.dynamic.length,
    staticCount: catalog.static.length
  });

  return catalog;
};

export const streamMapFromCatalogStaticEntries = (catalog: ShowMediaCatalog): Partial<Record<ShowSceneKey, string>> => {
  const fromSceneEntries = catalog.static.reduce<Partial<Record<ShowSceneKey, string>>>((acc, entry) => {
    const scene = entry.scene ?? toSceneKey(entry.slot);
    if (scene && !acc[scene]) {
      acc[scene] = entry.masterUrl;
    }
    return acc;
  }, {});

  if (!fromSceneEntries.interstitial && catalog.interstitial.length > 0) {
    fromSceneEntries.interstitial = catalog.interstitial[0]?.masterUrl;
  }
  if (!fromSceneEntries.mainDynamic && catalog.dynamic.length > 0) {
    fromSceneEntries.mainDynamic = catalog.dynamic[0]?.masterUrl;
  }
  if (!fromSceneEntries.mainStatic) {
    const staticMain = catalog.static.find((entry) => entry.slot.startsWith("main-"));
    if (staticMain) {
      fromSceneEntries.mainStatic = staticMain.masterUrl;
    }
  }

  return fromSceneEntries;
};

export const pickCatalogClip = (
  clips: ShowCatalogClipEntry[],
  recentClipIds: string[],
  noRepeatWindow: number,
  random: () => number = Math.random
): ShowCatalogClipEntry | null => {
  if (clips.length === 0) {
    return null;
  }

  const blocked = new Set(recentClipIds.slice(-Math.max(0, noRepeatWindow)));
  const eligible = clips.filter((clip) => !blocked.has(clip.clipId));
  const pool = eligible.length > 0 ? eligible : clips;

  const weighted = pool
    .map((clip) => ({ clip, weight: Math.max(0, clip.weight) }))
    .filter((candidate) => candidate.weight > 0);

  const samplingPool = weighted.length > 0 ? weighted : pool.map((clip) => ({ clip, weight: 1 }));
  const totalWeight = samplingPool.reduce((sum, candidate) => sum + candidate.weight, 0);
  if (totalWeight <= 0) {
    return samplingPool[0]?.clip ?? null;
  }

  let threshold = random() * totalWeight;
  for (const candidate of samplingPool) {
    threshold -= candidate.weight;
    if (threshold <= 0) {
      return candidate.clip;
    }
  }

  return samplingPool[samplingPool.length - 1]?.clip ?? null;
};

export const findCatalogClipById = (
  clips: ShowCatalogClipEntry[],
  clipId: string | null | undefined
): ShowCatalogClipEntry | null => {
  if (!clipId) {
    return null;
  }
  return clips.find((clip) => clip.clipId === clipId) ?? null;
};
