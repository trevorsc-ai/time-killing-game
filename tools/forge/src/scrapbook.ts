import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Extra single-character colors the scrapbook art may use on top of the shared palette (Art/palette.json).
 * Each art file carries the extras it uses in its own `palette` map, so the app needs no knowledge of this list.
 */
export const SCRAPBOOK_EXTRA_PALETTE: Record<string, string> = {
  d: "#4A3B52", // outline
  c: "#FFF6E2", // cream
  m: "#8A6A4E", // mid brown
  l: "#E4C79B", // light wood
  e: "#F2C14E", // brass / gold
  x: "#B5704A", // rust
  h: "#FFFFFF", // highlight
  G: "#3F8F55", // deep green
  R: "#B83B35", // deep red
  B: "#3C78B8", // deep blue
  O: "#C77A22", // deep orange
  N: "#7C5636", // deep cocoa
  Y: "#FFE9A8", // pale glow
  a: "#CFEFF0", // pale sky
  u: "#B9AEA3", // dust grey
};

export interface ScrapbookArt {
  id: string;
  title: string;
  caption: string;
  width: number;
  height: number;
  rows: string[];
  palette?: Record<string, string>;
}

/** Validates one scrapbook art object. `shared` is the set of shared palette ids. Returns error strings. */
export function validateScrapbookArt(art: ScrapbookArt, shared: Set<string>, where: string): string[] {
  const e: string[] = [];
  const bad = (m: string) => e.push(`${where}: ${m}`);
  if (typeof art.id !== "string" || !art.id) bad("id required");
  if (typeof art.title !== "string" || !art.title.trim()) bad("title required");
  if (typeof art.caption !== "string" || !art.caption.trim()) bad("caption required");
  if (!Number.isInteger(art.width) || art.width < 1 || art.width > 64) bad("width must be an integer 1..64");
  if (!Number.isInteger(art.height) || art.height < 1 || art.height > 64) bad("height must be an integer 1..64");
  if (!Array.isArray(art.rows)) {
    bad("rows must be an array");
    return e;
  }
  if (art.rows.length !== art.height) bad(`rows.length ${art.rows.length} != height ${art.height}`);
  const known = new Set<string>(shared);
  for (const [k, v] of Object.entries(art.palette ?? {})) {
    if (k.length !== 1 || k === ".") bad(`palette key "${k}" must be a single character other than "."`);
    if (!/^#[0-9A-Fa-f]{6}$/.test(v)) bad(`palette ${k}: ${v} must be #RRGGBB`);
    known.add(k);
  }
  let opaque = 0;
  for (const [i, row] of art.rows.entries()) {
    if (row.length !== art.width) bad(`row ${i} has length ${row.length}, expected ${art.width}`);
    for (const ch of row) {
      if (ch === ".") continue;
      opaque++;
      if (!known.has(ch)) bad(`row ${i}: unknown palette key "${ch}"`);
    }
  }
  if (opaque === 0) bad("art is empty");
  return e;
}

/**
 * Checks that every restoration stage has its scrapbook art file and that every file is well formed.
 * `stageArtIds` are all `scrapbookArtId` values from Destinations.json.
 */
export function validateScrapbook(resources: string, stageArtIds: string[], sharedPalette: Set<string>): string[] {
  const errors: string[] = [];
  for (const id of stageArtIds) {
    const path = join(resources, "Art", "scrapbook", `${id}.json`);
    if (!existsSync(path)) {
      errors.push(`Art/scrapbook/${id}.json: missing (referenced by Destinations.json)`);
      continue;
    }
    try {
      const art = JSON.parse(readFileSync(path, "utf8")) as ScrapbookArt;
      if (art.id !== id) errors.push(`Art/scrapbook/${id}.json: id "${art.id}" does not match file name`);
      errors.push(...validateScrapbookArt(art, sharedPalette, `Art/scrapbook/${id}.json`));
    } catch (err) {
      errors.push(`Art/scrapbook/${id}.json: cannot parse (${(err as Error).message})`);
    }
  }
  return errors;
}
