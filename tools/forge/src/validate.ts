import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { MODES } from "./modes/index.js";
import {
  MODE_IDS,
  ORDER_TABLE,
  type DestinationsFile,
  type LevelEnvelope,
  type LevelFile,
  type PaletteFile,
  type PoolFile,
} from "./schema.js";

const HERE = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_RESOURCES = resolve(HERE, "../../../PuzzleGetaway/Resources");

export const POOL_NAMES = ["relax-liquid", "relax-pixel", "relax-pipe", "daily"];

export interface Report {
  errors: string[];
  levelCount: number;
  poolEntryCount: number;
}

function readJson(path: string, errors: string[]): unknown {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    errors.push(`${path}: cannot parse JSON (${(e as Error).message})`);
    return undefined;
  }
}

function isInt(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x);
}

/** Validate envelope fields and dispatch to the per-mode validator. Returns error strings. */
export function validateLevel(level: LevelEnvelope, where: string): string[] {
  const e: string[] = [];
  const bad = (m: string) => e.push(`${where}: ${m}`);
  if (!level || typeof level !== "object") return [`${where}: level must be an object`];
  if (typeof level.id !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(level.id)) bad("id must match /^[a-z0-9][a-z0-9-]*$/");
  if (typeof level.mode !== "string") bad("mode must be a string");
  if (typeof level.destination !== "string" || !level.destination) bad("destination must be a non-empty string");
  if (!isInt(level.order) || level.order < 1) bad("order must be an integer >= 1");
  if (typeof level.title !== "string" || !level.title.trim()) bad("title must be a non-empty string");
  if (!isInt(level.difficulty) || level.difficulty < 1 || level.difficulty > 10) bad("difficulty must be an integer 1..10");
  if (level.tutorial !== undefined && typeof level.tutorial !== "string") bad("tutorial must be a string when present");
  if (!Array.isArray(level.twists) || !level.twists.every((t) => typeof t === "string")) bad("twists must be an array of strings");
  if (!Array.isArray(level.solution)) bad("solution must be an array");
  if (!isInt(level.par) || level.par < 1) bad("par must be an integer >= 1");
  else if (Array.isArray(level.solution) && level.par > level.solution.length) bad("par must be <= solution.length");
  if (level.payload === undefined || level.payload === null || typeof level.payload !== "object") bad("payload must be an object");
  if (e.length) return e;

  const handler = MODES[level.mode];
  if (!handler) {
    bad(`no mode handler registered for "${level.mode}" (src/modes/index.ts)`);
    return e;
  }
  for (const m of handler.validate(level)) bad(m);
  if (e.length) return e;
  const r = handler.replay(level);
  if (!r.ok) bad(`stored solution does not solve the level: ${r.error ?? "unknown"}`);
  return e;
}

export function validateAll(resources: string = DEFAULT_RESOURCES): Report {
  const errors: string[] = [];
  let levelCount = 0;
  let poolEntryCount = 0;
  const ids = new Set<string>();
  const dup = (id: string, where: string) => {
    if (ids.has(id)) errors.push(`${where}: duplicate level id "${id}"`);
    ids.add(id);
  };

  // Palette
  const paletteKeys = new Set<string>();
  const palettePath = join(resources, "Art", "palette.json");
  if (!existsSync(palettePath)) errors.push(`${palettePath}: missing`);
  else {
    const pal = readJson(palettePath, errors) as PaletteFile | undefined;
    if (pal) {
      if (!Array.isArray(pal.colors) || pal.colors.length === 0) errors.push("palette.json: colors must be a non-empty array");
      const symbols = new Set<string>();
      for (const c of pal.colors ?? []) {
        const w = `palette.json[${c?.id}]`;
        if (typeof c.id !== "string" || c.id.length !== 1 || c.id === "." || c.id === " " || c.id === "#" || c.id === "?")
          errors.push(`${w}: id must be a single character other than . # ? or space`);
        if (paletteKeys.has(c.id)) errors.push(`${w}: duplicate id`);
        paletteKeys.add(c.id);
        for (const k of ["hex", "highContrastHex"] as const)
          if (!/^#[0-9A-Fa-f]{6}$/.test(c[k] ?? "")) errors.push(`${w}: ${k} must be #RRGGBB`);
        if (!c.name || !c.symbol) errors.push(`${w}: name and symbol required`);
        if (symbols.has(c.symbol)) errors.push(`${w}: duplicate symbol ${c.symbol}`);
        symbols.add(c.symbol);
      }
    }
  }

  // Destinations
  const destIds = new Set<string>();
  const destPath = join(resources, "Destinations.json");
  if (!existsSync(destPath)) errors.push(`${destPath}: missing`);
  else {
    const d = readJson(destPath, errors) as DestinationsFile | undefined;
    if (d) {
      if (!isInt(d.unlockPercent)) errors.push("Destinations.json: unlockPercent must be an integer");
      for (const x of d.destinations ?? []) {
        const w = `Destinations.json[${x?.id}]`;
        if (!/^d\d+$/.test(x.id ?? "")) errors.push(`${w}: id must be d<N>`);
        destIds.add(x.id);
        for (const k of ["name", "tagline", "intro", "restorationTitle"] as const)
          if (typeof x[k] !== "string") errors.push(`${w}: ${k} must be a string`);
        if (typeof x.comingSoon !== "boolean") errors.push(`${w}: comingSoon must be boolean`);
        for (const k of ["primary", "secondary", "accent", "background"] as const)
          if (!/^#[0-9A-Fa-f]{6}$/.test(x.theme?.[k] ?? "")) errors.push(`${w}: theme.${k} must be #RRGGBB`);
        let prev = -1;
        for (const s of x.restorationStages ?? []) {
          if (!s.id || !s.title || !s.scrapbookArtId || !isInt(s.starsRequired)) errors.push(`${w}: bad restoration stage ${JSON.stringify(s)}`);
          if (s.starsRequired <= prev) errors.push(`${w}: starsRequired must increase`);
          prev = s.starsRequired;
        }
        if (!x.comingSoon && (x.restorationStages ?? []).length === 0) errors.push(`${w}: playable destination needs restoration stages`);
      }
      if (destIds.size !== (d.destinations ?? []).length) errors.push("Destinations.json: duplicate destination ids");
    }
  }

  // Levels
  const levelsDir = join(resources, "Levels");
  const destOrders = new Map<string, Set<number>>();
  if (existsSync(levelsDir)) {
    for (const f of readdirSync(levelsDir).filter((n) => n.endsWith(".json")).sort()) {
      const path = join(levelsDir, f);
      const file = readJson(path, errors) as LevelFile | undefined;
      if (!file) continue;
      const where = `Levels/${f}`;
      if (f !== `${file.destination}-${file.mode}.json`) errors.push(`${where}: file name must be <destination>-<mode>.json`);
      if (file.destination !== "demo" && !destIds.has(file.destination)) errors.push(`${where}: unknown destination "${file.destination}"`);
      if (file.destination !== "demo" && !(MODE_IDS as readonly string[]).includes(file.mode)) errors.push(`${where}: unknown mode "${file.mode}"`);
      if (!Array.isArray(file.levels)) {
        errors.push(`${where}: levels must be an array`);
        continue;
      }
      for (const [i, lvl] of file.levels.entries()) {
        const w = `${where}#${lvl?.id ?? i}`;
        levelCount++;
        dup(lvl?.id, w);
        errors.push(...validateLevel(lvl, w));
        if (lvl.destination !== file.destination) errors.push(`${w}: destination differs from file`);
        if (lvl.mode !== file.mode) errors.push(`${w}: mode differs from file`);
        const expectedId = `${lvl.destination}-${lvl.mode}-${String(lvl.order).padStart(2, "0")}`;
        if (lvl.id !== expectedId) errors.push(`${w}: id should be ${expectedId}`);
        const set = destOrders.get(lvl.destination) ?? new Set<number>();
        if (set.has(lvl.order)) errors.push(`${w}: duplicate order ${lvl.order} in ${lvl.destination}`);
        set.add(lvl.order);
        destOrders.set(lvl.destination, set);
        const table = ORDER_TABLE[lvl.destination];
        if (lvl.destination !== "demo") {
          if (!table) errors.push(`${w}: no ORDER_TABLE entry for destination ${lvl.destination}`);
          else if (!table[lvl.mode]?.includes(lvl.order)) errors.push(`${w}: order ${lvl.order} not assigned to mode ${lvl.mode} in ORDER_TABLE`);
        }
      }
    }
  } else errors.push(`${levelsDir}: missing`);

  // Pools
  const poolsDir = join(resources, "Pools");
  for (const name of POOL_NAMES) {
    const path = join(poolsDir, `${name}.json`);
    if (!existsSync(path)) {
      errors.push(`Pools/${name}.json: missing`);
      continue;
    }
    const pool = readJson(path, errors) as PoolFile | undefined;
    if (!pool) continue;
    if (pool.pool !== name) errors.push(`Pools/${name}.json: pool must equal "${name}"`);
    if (!Array.isArray(pool.entries)) {
      errors.push(`Pools/${name}.json: entries must be an array`);
      continue;
    }
    const orders = new Set<number>();
    for (const [i, lvl] of pool.entries.entries()) {
      const w = `Pools/${name}.json#${lvl?.id ?? i}`;
      poolEntryCount++;
      dup(lvl?.id, w);
      errors.push(...validateLevel(lvl, w));
      if (lvl.destination !== name) errors.push(`${w}: destination must equal pool name "${name}"`);
      if (orders.has(lvl.order)) errors.push(`${w}: duplicate order`);
      orders.add(lvl.order);
    }
  }

  return { errors, levelCount, poolEntryCount };
}

// CLI entry
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = process.argv[2] ? resolve(process.argv[2]) : DEFAULT_RESOURCES;
  const report = validateAll(root);
  if (report.errors.length) {
    for (const e of report.errors) console.error(`ERROR ${e}`);
    console.error(`\n${report.errors.length} error(s)`);
    process.exit(1);
  }
  console.log(`OK: ${report.levelCount} level(s), ${report.poolEntryCount} pool entr(ies) validated in ${root}`);
}
