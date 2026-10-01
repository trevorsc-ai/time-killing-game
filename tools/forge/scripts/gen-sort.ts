/**
 * Regenerates all Liquid / Bolt content deterministically:
 *   Levels/d1-liquid.json, Levels/d1-bolt.json, Levels/d2-bolt.json, Pools/relax-liquid.json
 * Usage: npm run gen:sort            (writes into PuzzleGetaway/Resources)
 *        npm run gen:sort -- --report  (prints the difficulty curve only)
 * Every random choice comes from mulberry32 seeded by the constants below, so reruns reproduce the same files.
 */
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import type { LevelEnvelope } from "../src/schema.js";
import { candidates, type Candidate, type DealSpec } from "../src/generators/sortGen.js";

const COLORS = "roygtbipknws".split("");
const REPORT_ONLY = process.argv.includes("--report");

interface LevelSpec {
  order: number;
  title: string;
  difficulty: number;
  deal: DealSpec;
  /** 0 = easiest candidate, 1 = hardest candidate (by combined score). */
  q: number;
  tutorial?: string;
  twists: string[];
  seed: number;
  tries?: number;
  probe?: boolean;
}

/** Rotates the palette so neighboring levels do not always use the same colors. */
function pal(n: number, shift = 0): string[] {
  const out: string[] = [];
  for (let i = 0; i < n; i++) out.push(COLORS[(i * 5 + shift) % COLORS.length]);
  return uniq(out, shift);
}
function uniq(list: string[], shift: number): string[] {
  const seen = new Set<string>();
  const res: string[] = [];
  for (const c of list) if (!seen.has(c)) (seen.add(c), res.push(c));
  let k = shift;
  while (res.length < list.length) {
    const c = COLORS[k++ % COLORS.length];
    if (!seen.has(c)) (seen.add(c), res.push(c));
  }
  return res;
}

function pick(cs: Candidate[], q: number): Candidate {
  const sorted = cs.slice().sort((a, b) => a.difficulty.score - b.difficulty.score || a.seed - b.seed);
  return sorted[Math.round(q * (sorted.length - 1))];
}

function gather(spec: DealSpec, seed: number, want: number, maxTries: number, probe: boolean): Candidate[] {
  const out: Candidate[] = [];
  const chunk = 40;
  for (let done = 0; done < maxTries && out.length < want; done += chunk) {
    out.push(...candidates(spec, seed + done, { tries: chunk, probe, budget: 150_000 }));
  }
  if (out.length === 0) throw new Error(`no candidates for seed ${seed} ${JSON.stringify(spec)}`);
  return out;
}

function buildLevel(destination: string, mode: "liquid" | "bolt", s: LevelSpec): { level: LevelEnvelope; c: Candidate } {
  const cs = gather(s.deal, s.seed, 8, s.tries ?? 400, s.probe ?? true);
  const c = pick(cs, s.q);
  const level: LevelEnvelope = {
    id: `${destination}-${mode}-${String(s.order).padStart(2, "0")}`,
    mode,
    destination,
    order: s.order,
    title: s.title,
    difficulty: s.difficulty,
    ...(s.tutorial ? { tutorial: s.tutorial } : {}),
    twists: s.twists,
    par: c.difficulty.par,
    solution: c.solution,
    payload: c.payload,
  };
  return { level, c };
}

// ---------------------------------------------------------------- d1 liquid (snack cart)
const L = (colors: number, empties: number, extra: Partial<DealSpec> = {}, shift = 0): DealSpec => ({
  mode: "liquid",
  colors: pal(colors, shift),
  count: 4,
  capacity: 4,
  empties,
  ...extra,
});

const D1_LIQUID: LevelSpec[] = [
  { order: 1, title: "Lemonade Line-up", difficulty: 1, deal: L(3, 2, { deadlockFree: true }, 0), q: 0.0, tutorial: "liquid.pour", twists: [], seed: 11000 },
  { order: 3, title: "Teapot Shuffle", difficulty: 1, deal: L(3, 2, { deadlockFree: true }, 1), q: 1.0, twists: [], seed: 12000 },
  { order: 5, title: "Berry Soda Fizz", difficulty: 2, deal: L(4, 2, { deadlockFree: true }, 2), q: 0.4, twists: [], seed: 13000 },
  { order: 7, title: "Mint Condition", difficulty: 3, deal: L(5, 2, {}, 3), q: 0.2, twists: [], seed: 14000 },
  { order: 9, title: "Cocoa Corner", difficulty: 4, deal: L(5, 2, {}, 4), q: 0.8, twists: [], seed: 15000 },
  { order: 11, title: "Cart Rush Hour", difficulty: 4, deal: L(6, 2, {}, 5), q: 0.5, twists: [], seed: 16000 },
  { order: 13, title: "Mystery Cups", difficulty: 5, deal: L(6, 2, { hidden: 3 }, 6), q: 0.5, twists: ["hidden"], seed: 17000 },
  { order: 15, title: "Syrup Sorting", difficulty: 6, deal: L(6, 1, {}, 7), q: 0.7, twists: [], seed: 18000, tries: 800 },
  { order: 18, title: "The Locked Cooler", difficulty: 7, deal: L(7, 2, { locks: 1 }, 8), q: 1.0, twists: ["lock"], seed: 19000 },
  { order: 21, title: "Grand Rainbow Spritzer", difficulty: 8, deal: L(7, 2, { hidden: 2, locks: 1 }, 9), q: 1.0, twists: ["hidden", "lock"], seed: 20000 },
];

// ---------------------------------------------------------------- bolt
const B = (colors: number, empties: number, extra: Partial<DealSpec> = {}, shift = 0): DealSpec => ({
  mode: "bolt",
  colors: pal(colors, shift),
  count: 5,
  capacity: 5,
  empties,
  ...extra,
});

const D1_BOLT: LevelSpec[] = [
  { order: 16, title: "Bench Warm-up", difficulty: 2, deal: B(3, 2, { deadlockFree: true }, 2), q: 0.0, tutorial: "bolt.move", twists: [], seed: 31000 },
  { order: 19, title: "Spanner Shuffle", difficulty: 2, deal: B(4, 2, {}, 4), q: 0.3, twists: [], seed: 32000 },
  { order: 22, title: "Nuts About Colors", difficulty: 3, deal: B(4, 2, {}, 6), q: 0.9, twists: [], seed: 33000 },
  { order: 24, title: "Tidy the Toolbox", difficulty: 3, deal: B(5, 2, {}, 1), q: 0.4, twists: [], seed: 34000 },
  { order: 25, title: "Workshop Rush", difficulty: 4, deal: B(5, 1, {}, 3), q: 0.8, twists: [], seed: 35000, tries: 800 },
];

const D2_BOLT: LevelSpec[] = [
  { order: 1, title: "Garden Gate Nuts", difficulty: 4, deal: B(4, 2, {}, 7), q: 0.5, twists: [], seed: 41000 },
  {
    order: 2,
    title: "Short Stack",
    difficulty: 5,
    deal: B(4, 1, { capacities: [5, 5, 5, 5, 3, 3, 5], startBolts: 6 }, 8),
    q: 0.5,
    twists: ["capped"],
    seed: 42000,
  },
  {
    order: 3,
    title: "Trellis Tangle",
    difficulty: 6,
    deal: B(5, 1, { capacities: [5, 5, 5, 5, 5, 3, 4, 5], startBolts: 7 }, 9),
    q: 0.7,
    twists: ["capped"],
    seed: 43000,
  },
  { order: 4, title: "Rusty Watering Can", difficulty: 7, deal: B(4, 1, { rusty: 1 }, 10), q: 0.9, twists: ["rusty"], seed: 44000, tries: 800 },
  {
    order: 5,
    title: "Greenhouse Fix-up",
    difficulty: 8,
    deal: B(5, 1, { capacities: [5, 5, 5, 5, 5, 3, 4, 5], startBolts: 7, rusty: 2 }, 11),
    q: 0.8,
    twists: ["capped", "rusty"],
    seed: 45000,
  },
];

// ---------------------------------------------------------------- relax pool
const ADJ = ["Sunny", "Cozy", "Fizzy", "Frosty", "Minty", "Honeyed", "Velvet", "Zesty", "Dreamy", "Breezy", "Toasty", "Golden", "Misty", "Sugared", "Sparkling"];
const NOUN = ["Spritz", "Cooler", "Float", "Punch", "Tonic", "Cordial", "Soda", "Slush", "Nectar", "Cup"];
const POOL_SIZE = 150;
const TIERS = POOL_SIZE / 5;

function poolSpec(i: number): { spec: DealSpec; q: number } {
  const c = 3 + (i % 5);
  const tier = Math.floor(i / 5);
  const q = tier / (TIERS - 1);
  let empties = 2;
  if (c >= 6 && tier >= 18) empties = 1;
  if (c === 5 && tier >= 26) empties = 1;
  const extra: Partial<DealSpec> = {};
  if (c >= 5 && tier >= 8 && i % 7 === 3) extra.hidden = tier >= 20 ? 3 : 2;
  return { spec: L(c, empties, extra, (i * 7) % 12), q };
}

function buildPool(): LevelEnvelope[] {
  const entries: LevelEnvelope[] = [];
  for (let i = 0; i < POOL_SIZE; i++) {
    const { spec, q } = poolSpec(i);
    const cs = gather(spec, 900_000 + i * 997, 12, 1500, false);
    const c = pick(cs, q);
    entries.push({
      id: `relax-liquid-${String(i + 1).padStart(3, "0")}`,
      mode: "liquid",
      destination: "relax-liquid",
      order: i + 1,
      title: `${ADJ[i % ADJ.length]} ${NOUN[Math.floor(i / ADJ.length) % NOUN.length]}`,
      difficulty: 1 + Math.floor((i * 7) / POOL_SIZE),
      twists: spec.hidden ? ["hidden"] : [],
      par: c.difficulty.par,
      solution: c.solution,
      payload: c.payload,
    });
  }
  return entries;
}

// ---------------------------------------------------------------- writing
const j = (v: unknown) => JSON.stringify(v);

function fmtLevel(l: LevelEnvelope, indent: string): string {
  const lines = [
    `"id": ${j(l.id)}`,
    `"mode": ${j(l.mode)}, "destination": ${j(l.destination)}, "order": ${l.order}, "title": ${j(l.title)}, "difficulty": ${l.difficulty}`,
    ...(l.tutorial ? [`"tutorial": ${j(l.tutorial)}`] : []),
    `"twists": ${j(l.twists)}, "par": ${l.par}`,
    `"solution": ${j(l.solution)}`,
    `"payload": ${j(l.payload)}`,
  ];
  return `${indent}{\n${lines.map((x) => `${indent}  ${x}`).join(",\n")}\n${indent}}`;
}

function write(rel: string, head: string, key: string, levels: LevelEnvelope[]): void {
  const path = join(DEFAULT_RESOURCES, rel);
  const body = `{\n  ${head},\n  "${key}": [\n${levels.map((l) => fmtLevel(l, "    ")).join(",\n")}\n  ]\n}\n`;
  if (REPORT_ONLY) return;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, body);
  console.log(`wrote ${rel} (${levels.length})`);
}

function report(name: string, levels: LevelEnvelope[], cs: Candidate[]): void {
  console.log(`\n${name}`);
  levels.forEach((l, i) => {
    const d = cs[i].difficulty;
    const p = l.payload as { tubes: string[][] };
    console.log(
      `  #${String(l.order).padStart(2)} ${l.title.padEnd(24)} tubes=${p.tubes.length} par=${d.par}${d.optimal ? "" : "*"} branch=${d.branching.toFixed(1)} dead=${d.deadEnd.toFixed(2)} score=${d.score.toFixed(1)} seed=${cs[i].seed}`,
    );
  });
}

function runFile(destination: string, mode: "liquid" | "bolt", specs: LevelSpec[]): void {
  const built = specs.map((s) => buildLevel(destination, mode, s));
  const levels = built.map((b) => b.level);
  report(`${destination}-${mode}`, levels, built.map((b) => b.c));
  write(`Levels/${destination}-${mode}.json`, `"destination": ${j(destination)}, "mode": ${j(mode)}`, "levels", levels);
}

runFile("d1", "liquid", D1_LIQUID);
runFile("d1", "bolt", D1_BOLT);
runFile("d2", "bolt", D2_BOLT);
if (!process.argv.includes("--no-pool")) {
  const pool = buildPool();
  console.log("\nrelax-liquid pool:");
  for (let i = 0; i < pool.length; i += 10) {
    console.log("  " + pool.slice(i, i + 10).map((e) => `${e.par}`).join(" "));
  }
  write("Pools/relax-liquid.json", `"pool": "relax-liquid"`, "entries", pool);
}
