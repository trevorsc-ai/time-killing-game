/**
 * Generates PuzzleGetaway/Resources/Levels/d4-pipe.json (Rainy Platform, 6 levels) and
 * PuzzleGetaway/Resources/Pools/relax-pipe.json (150 entries, 3x3 rising to 7x7).
 * Deterministic: every level uses a recorded seed. Run: npx tsx scripts/gen-pipe.ts
 */
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import { generatePipe, type GeneratedPipe, type PipeSpec } from "../src/modes/pipe/generator.js";
import { parseBoard } from "../src/modes/pipe/rules.js";
import { solvePipe } from "../src/modes/pipe/solver.js";

function make(seed: number, spec: PipeSpec): GeneratedPipe {
  for (let k = 0; k < 50; k++) {
    const g = generatePipe(seed + k * 7919, spec);
    if (g) return g;
  }
  throw new Error(`no pipe board for seed ${seed} ${JSON.stringify(spec)}`);
}

interface Plan {
  order: number;
  title: string;
  difficulty: number;
  seed: number;
  tutorial?: string;
  twists: string[];
  spec: PipeSpec;
}

const PLANS: Plan[] = [
  { order: 1, title: "A Gentle Turn", difficulty: 1, seed: 401, tutorial: "pipe.rotate", twists: [], spec: { rows: 3, cols: 3, dests: 1, minPath: 4, maxPath: 5, minTaps: 3, maxTaps: 5 } },
  { order: 2, title: "Around the Planter", difficulty: 2, seed: 402, twists: [], spec: { rows: 4, cols: 4, dests: 1, minPath: 6, maxPath: 9, minTaps: 6, maxTaps: 9 } },
  { order: 3, title: "Long Way to the Roof", difficulty: 3, seed: 403, twists: [], spec: { rows: 5, cols: 5, dests: 1, minPath: 10, maxPath: 14, minTaps: 11, maxTaps: 17 } },
  { order: 4, title: "A Fork in the Gutter", difficulty: 5, seed: 404, tutorial: "twist.tee", twists: ["tee"], spec: { rows: 5, cols: 5, dests: 2, minPath: 7, maxPath: 12, minTaps: 13, maxTaps: 19 } },
  { order: 5, title: "Three Window Boxes", difficulty: 7, seed: 405, twists: ["tee"], spec: { rows: 6, cols: 6, dests: 3, decoyTees: true, minPath: 9, maxPath: 14, minTaps: 20, maxTaps: 28 } },
  { order: 6, title: "The Great Downpour", difficulty: 9, seed: 406, twists: ["tee"], spec: { rows: 6, cols: 6, dests: 4, decoyTees: true, minPath: 8, maxPath: 14, minTaps: 25, maxTaps: 36 } },
];

const levels = PLANS.map((p) => {
  const g = make(p.seed, p.spec);
  console.log(`d4 order ${p.order}: par ${g.par} (planted ${g.plantedTaps}, proven ${g.proven})`);
  return {
    id: `d4-pipe-${String(p.order).padStart(2, "0")}`,
    mode: "pipe",
    destination: "d4",
    order: p.order,
    title: p.title,
    difficulty: p.difficulty,
    ...(p.tutorial ? { tutorial: p.tutorial } : {}),
    twists: p.twists,
    par: g.par,
    solution: g.solution,
    payload: g.payload,
  };
});
writeFileSync(join(DEFAULT_RESOURCES, "Levels", "d4-pipe.json"), JSON.stringify({ destination: "d4", mode: "pipe", levels }, null, 1) + "\n");

// ---- Relax pool: 150 entries, 30 per size from 3x3 to 7x7, difficulty never decreasing. ----
const ADJ = ["Misty", "Drizzly", "Brassy", "Quiet", "Gentle", "Sparkling", "Mossy", "Humming", "Steady", "Silver", "Breezy", "Cosy", "Dewy", "Tidy", "Rusty"];
const NOUN = ["Gutter", "Downspout", "Drain", "Spout", "Channel", "Trickle", "Stream", "Runnel", "Pipeline", "Rill"];
const entries = [];
const TOTAL = 150;
for (let i = 0; i < TOTAL; i++) {
  const size = 3 + Math.floor(i / 30);
  const t = (i % 30) / 29; // progress inside the size tier
  const dests = size === 3 ? 1 : size === 4 ? (t < 0.5 ? 1 : 2) : size === 5 ? 2 : size === 6 ? (t < 0.5 ? 2 : 3) : 3;
  const area = size * size;
  const spec: PipeSpec = {
    rows: size,
    cols: size,
    dests,
    decoyTees: size >= 5,
    emptyFrac: size <= 4 ? 0.1 : 0.14,
    minPath: Math.max(3, Math.floor(size * (1.2 + t))),
    maxPath: Math.min(area, size * 3 + 2),
    minTaps: Math.floor(area * (0.35 + 0.15 * t)),
    maxTaps: 1e9,
    solveBudget: size >= 7 ? 60_000 : 120_000,
  };
  const g = make(9000 + i * 31, spec);
  const board = parseBoard(g.payload);
  void board;
  void solvePipe;
  entries.push({
    id: `relax-pipe-${String(i + 1).padStart(3, "0")}`,
    mode: "pipe",
    destination: "relax-pipe",
    order: i + 1,
    title: `${ADJ[i % ADJ.length]} ${NOUN[Math.floor(i / ADJ.length) % NOUN.length]} ${i + 1}`,
    difficulty: Math.min(10, 1 + Math.floor((i * 10) / TOTAL)),
    twists: dests > 1 ? ["tee"] : [],
    par: g.par,
    solution: g.solution,
    payload: g.payload,
  });
}
writeFileSync(join(DEFAULT_RESOURCES, "Pools", "relax-pipe.json"), JSON.stringify({ pool: "relax-pipe", entries }, null, 1) + "\n");
console.log(`relax-pipe: ${entries.length} entries`);
