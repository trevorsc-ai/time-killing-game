/**
 * Generates PuzzleGetaway/Resources/Pools/daily.json: 730 solver-verified Daily Journey entries.
 * Weekly rotation (index % 7): liquid, pixel, pipe, bolt, parking, pixel, liquid. Difficulty cycles 3..6.
 * Deterministic: every entry derives from a seed computed from its index. Run: npm run gen:daily
 *   npm run gen:daily -- --count 40   (quick check, does not overwrite the real file unless --write is given)
 */
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import type { LevelEnvelope } from "../src/schema.js";
import { createRng } from "../src/util/prng.js";
import { candidates, type Candidate, type DealSpec } from "../src/generators/sortGen.js";
import { generateParking } from "../src/modes/parking/generator.js";
import { solveParking } from "../src/modes/parking/solver.js";
import { generatePipe, type PipeSpec } from "../src/modes/pipe/generator.js";
import { generate } from "../src/modes/pixel/generate.js";
import { TIERS, proceduralScene, addStones } from "../src/modes/pixel/pool.js";
import { SCENE_BY_ID } from "../src/modes/pixel/art/scenes.js";

const argCount = process.argv.indexOf("--count");
const COUNT = argCount > 0 ? Number(process.argv[argCount + 1]) : 730;
const WEEK = ["liquid", "pixel", "pipe", "bolt", "parking", "pixel", "liquid"] as const;
const COLORS = "roygtbipknws".split("");
const pal = (n: number, shift: number): string[] => {
  const out: string[] = [];
  for (let k = 0; out.length < n; k++) {
    const c = COLORS[(k * 5 + shift) % COLORS.length]!;
    if (!out.includes(c)) out.push(c);
    else if (k > 40) out.push(COLORS.find((x) => !out.includes(x))!);
  }
  return out;
};

const ADJ = ["Sunny", "Cozy", "Breezy", "Mellow", "Bright", "Gentle", "Merry", "Quiet", "Golden", "Rosy", "Minty", "Cheery", "Snug", "Sparkly", "Dewy", "Plucky"];
const PLACE = ["Morning", "Meadow", "Lantern", "Platform", "Siding", "Junction", "Carriage", "Whistle", "Timetable", "Journey", "Postcard", "Detour", "Ticket", "Valley", "Harbor", "Footbridge"];
const titleFor = (i: number): string => `${ADJ[i % ADJ.length]} ${PLACE[Math.floor(i / ADJ.length) % PLACE.length]} ${i + 1}`;

function pickByScore(cs: Candidate[], q: number): Candidate {
  const s = cs.slice().sort((a, b) => a.difficulty.score - b.difficulty.score || a.seed - b.seed);
  return s[Math.round(q * (s.length - 1))]!;
}

function sort(i: number, mode: "liquid" | "bolt", d: number): Partial<LevelEnvelope> {
  const seed = 2_000_000 + i * 1009;
  const q = [0.3, 0.5, 0.7, 0.85][d - 3]!;
  for (let attempt = 0; attempt < 6; attempt++) {
    let spec: DealSpec;
    let twists: string[] = [];
    if (mode === "liquid") {
      const colors = [5, 5, 6, 6][d - 3]!;
      spec = { mode, colors: pal(colors, (i * 7) % 12), count: 4, capacity: 4, empties: 2 };
      if (d >= 5 && i % 3 === 0) {
        spec.hidden = 2;
        twists = ["hidden"];
      }
    } else {
      const colors = [4, 4, 5, 5][d - 3]!;
      spec = { mode, colors: pal(colors, (i * 7) % 12), count: 5, capacity: 5, empties: d >= 6 ? 1 : 2 };
    }
    const cs = candidates(spec, seed + attempt * 331, { tries: 30, probe: false, budget: 120_000 });
    if (cs.length < 3) continue;
    const c = pickByScore(cs, q);
    return { twists, par: c.difficulty.par, solution: c.solution, payload: c.payload };
  }
  throw new Error(`no ${mode} candidate for entry ${i}`);
}

function pixel(i: number, d: number): Partial<LevelEnvelope> {
  const tier = TIERS[[1, 2, 3, 3][d - 3]!]!;
  const rng = createRng(0xda11_0000 + i);
  for (let attempt = 0; attempt < 14; attempt++) {
    let rows: string[];
    if (attempt >= 10 || i % 5 === 4) rows = SCENE_BY_ID[tier.hand[rng.int(tier.hand.length)]!]!.rows;
    else rows = proceduralScene(rng, tier, i).rows;
    let twists: string[] = [];
    if (rows.some((r) => r.includes("#"))) twists = ["stone"];
    else if (tier.stoneChance > 0 && rng.next() < tier.stoneChance) {
      rows = addStones(rows, rng, 3 + rng.int(3));
      twists = ["stone"];
    }
    const cand = generate({
      grid: rows,
      slots: tier.slots,
      lanes: 3,
      maxSplit: tier.maxSplit,
      minCrate: tier.minCrate,
      target: tier.target,
      seed: 4_000_000 + i * 53 + attempt,
      tries: 100,
      budget: 30_000,
    });
    if (!cand || cand.penalty > 0) continue;
    return { twists, par: cand.analysis.solution.length, solution: cand.analysis.solution, payload: cand.payload };
  }
  throw new Error(`no pixel candidate for entry ${i}`);
}

function pipe(i: number, d: number): Partial<LevelEnvelope> {
  const size = [4, 5, 5, 6][d - 3]!;
  const dests = [1, 2, 2, 2][d - 3]!;
  const area = size * size;
  const spec: PipeSpec = {
    rows: size,
    cols: size,
    dests,
    decoyTees: size >= 5,
    emptyFrac: 0.12,
    minPath: Math.floor(size * 1.5),
    maxPath: size * 3,
    minTaps: Math.floor(area * 0.4),
    maxTaps: Math.floor(area * 0.9),
    solveBudget: 60_000,
  };
  for (let k = 0; k < 60; k++) {
    const g = generatePipe(6_000_000 + i * 977 + k * 7919, spec);
    if (g) return { twists: dests > 1 ? ["tee"] : [], par: g.par, solution: g.solution, payload: g.payload };
  }
  throw new Error(`no pipe board for entry ${i}`);
}

function parking(i: number, d: number): Partial<LevelEnvelope> {
  const [lo, hi] = [[6, 9], [8, 11], [10, 13], [12, 15]][d - 3]!;
  const targets = d >= 6 && i % 2 === 0 ? 2 : 1;
  for (let k = 0; k < 8; k++) {
    const g = generateParking(8_000_000 + i * 613 + k * 1000, { targets: targets as 1 | 2, lo: lo!, hi: hi!, minVehicles: 7, maxVehicles: 10, attempts: 1500, stopAt: hi! });
    if (!g) continue;
    const solution = solveParking(g.payload)!;
    return { twists: targets === 2 ? ["second-gate"] : [], par: solution.length, solution, payload: g.payload };
  }
  throw new Error(`no parking board for entry ${i}`);
}

const entries: LevelEnvelope[] = [];
const seen = new Set<string>();
const t0 = Date.now();
for (let i = 0; i < COUNT; i++) {
  const mode = WEEK[i % 7]!;
  const tStart = Date.now();
  const d = 3 + ((i * 3 + Math.floor(i / 7)) % 4);
  const made = mode === "liquid" || mode === "bolt" ? sort(i, mode, d) : mode === "pixel" ? pixel(i, d) : mode === "pipe" ? pipe(i, d) : parking(i, d);
  const sig = mode + JSON.stringify(made.payload);
  if (seen.has(sig)) throw new Error(`duplicate payload at entry ${i}`);
  seen.add(sig);
  entries.push({
    id: `daily-${String(i + 1).padStart(3, "0")}`,
    mode,
    destination: "daily",
    order: i + 1,
    title: titleFor(i),
    difficulty: d,
    twists: made.twists ?? [],
    par: made.par!,
    solution: made.solution!,
    payload: made.payload!,
  });
  if (Date.now() - tStart > 6000) console.log(`slow entry ${i + 1} (${mode}): ${((Date.now() - tStart) / 1000).toFixed(1)}s`);
  if ((i + 1) % 20 === 0) console.log(`${i + 1}/${COUNT} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
}

const out = `{"pool":"daily","entries":[\n${entries.map((e) => JSON.stringify(e)).join(",\n")}\n]}\n`;
if (argCount < 0 || process.argv.includes("--write")) {
  writeFileSync(join(DEFAULT_RESOURCES, "Pools", "daily.json"), out);
  console.log(`wrote daily.json: ${entries.length} entries, ${(out.length / 1024).toFixed(0)} KB`);
} else console.log(`dry run: ${entries.length} entries, ${(out.length / 1024).toFixed(0)} KB`);
const by: Record<string, number[]> = {};
for (const e of entries) (by[e.mode] ??= []).push(e.par);
for (const [m, p] of Object.entries(by)) console.log(m, p.length, "par min/avg/max", Math.min(...p), (p.reduce((a, b) => a + b, 0) / p.length).toFixed(1), Math.max(...p));
