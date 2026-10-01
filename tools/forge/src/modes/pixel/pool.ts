/**
 * Relax pool generator: ~150 solver-verified Pixel Picnic puzzles with gently rising difficulty.
 * Mixes the ten hand-authored Snack Cart scenes (new crate splits) with seeded procedural patterns.
 */
import type { LevelEnvelope } from "../../schema.js";
import { createRng, type Rng } from "../../util/prng.js";
import { SCENE_BY_ID } from "./art/scenes.js";
import { bullseye, diamonds, icon, ICON_COUNT, mosaic, pinwheel, quilt, stripes, type PatternScene } from "./art/procedural.js";
import { generate, type Target } from "./generate.js";

export const POOL_SIZE = 150;

export interface Tier {
  upTo: number; // exclusive end index
  difficulty: number;
  slots: number;
  lanes: [number, number];
  maxSplit: number;
  minCrate: number;
  target: Target;
  /** Chance a procedural scene gets stone blockers. */
  stoneChance: number;
  hand: string[];
  sizes: [number, number];
  colors: [number, number];
}

export const TIERS: Tier[] = [
  { upTo: 30, difficulty: 1, slots: 5, lanes: [2, 3], maxSplit: 2, minCrate: 2, target: { crates: [4, 7], doomedFraction: [0, 0], pStuck: [0, 0] }, stoneChance: 0, hand: ["fruit-cup"], sizes: [8, 10], colors: [3, 3] },
  { upTo: 60, difficulty: 2, slots: 5, lanes: [3, 3], maxSplit: 2, minCrate: 2, target: { crates: [6, 9], doomedFraction: [0, 0], pStuck: [0, 0] }, stoneChance: 0, hand: ["tea-tray", "donut-box", "fruit-cup"], sizes: [9, 12], colors: [3, 4] },
  { upTo: 90, difficulty: 3, slots: 4, lanes: [3, 3], maxSplit: 3, minCrate: 2, target: { crates: [7, 11], doomedFraction: [0.01, 0.5], pStuck: [0.03, 0.3] }, stoneChance: 0, hand: ["sandwich", "tea-tray", "donut-box"], sizes: [10, 12], colors: [4, 5] },
  { upTo: 120, difficulty: 4, slots: 4, lanes: [3, 4], maxSplit: 3, minCrate: 2, target: { crates: [8, 12], doomedFraction: [0.02, 0.6], pStuck: [0.1, 0.45] }, stoneChance: 0.15, hand: ["ramen-bowl", "strawberry-tart", "sandwich"], sizes: [11, 14], colors: [4, 5] },
  { upTo: 150, difficulty: 5, slots: 3, lanes: [3, 4], maxSplit: 3, minCrate: 2, target: { crates: [8, 13], doomedFraction: [0.03, 0.7], pStuck: [0.15, 0.55] }, stoneChance: 0.3, hand: ["pretzel-stand", "strawberry-tart", "ramen-bowl", "onigiri-bento"], sizes: [11, 15], colors: [4, 6] },
];

function between(rng: Rng, [a, b]: [number, number]): number {
  return a + rng.int(b - a + 1);
}

export function addStones(rows: string[], rng: Rng, count: number): string[] {
  const g = rows.map((r) => r.split(""));
  const h = g.length;
  const w = g[0]!.length;
  let placed = 0;
  for (let tries = 0; tries < 200 && placed < count; tries++) {
    const x = 1 + rng.int(w - 2);
    const y = 1 + rng.int(h - 2);
    if (g[y]![x] === "." || g[y]![x] === "#") continue;
    const nbrs = [g[y - 1]![x], g[y + 1]![x], g[y]![x - 1], g[y]![x + 1]];
    if (!nbrs.some((c) => c !== "." && c !== "#")) continue;
    g[y]![x] = "#";
    placed++;
  }
  return g.map((r) => r.join(""));
}

export function proceduralScene(rng: Rng, tier: Tier, i: number): PatternScene {
  const w = between(rng, tier.sizes);
  const h = Math.max(8, w - rng.int(3));
  const k = between(rng, tier.colors);
  const kind = rng.int(7);
  switch (kind) {
    case 0:
      return quilt(rng, w, h, k);
    case 1:
      return diamonds(rng, w, h, k);
    case 2:
      return bullseye(rng, w, w, k);
    case 3:
      return stripes(rng, w, h, Math.min(k, 4));
    case 4:
      return mosaic(rng, w, h, k);
    case 5:
      return pinwheel(rng, w, h, k);
    default:
      return icon(rng, i + rng.int(ICON_COUNT), tier.difficulty >= 3 ? 1 : 0);
  }
}

export function buildPool(): LevelEnvelope[] {
  const rng = createRng(0x51a7ed);
  const entries: LevelEnvelope[] = [];
  const seen = new Set<string>();
  const counters: Record<string, number> = {};
  for (let i = 0; i < POOL_SIZE; i++) {
    const tier = TIERS.find((t) => i < t.upTo)!;
    let made: LevelEnvelope | null = null;
    for (let attempt = 0; attempt < 14 && !made; attempt++) {
      // Every 4th entry (and every attempt >= 8) reuses a hand-authored scene with fresh crates.
      const useHand = i % 4 === 3 || attempt >= 10;
      let title: string;
      let rows: string[];
      if (useHand) {
        const sc = SCENE_BY_ID[tier.hand[rng.int(tier.hand.length)]!]!;
        title = sc.title;
        rows = sc.rows;
      } else {
        const ps = proceduralScene(rng, tier, i);
        title = ps.title;
        rows = ps.rows;
      }
      let twists: string[] = [];
      if (!rows.some((r) => r.includes("#")) && tier.stoneChance > 0 && rng.next() < tier.stoneChance) {
        rows = addStones(rows, rng, 3 + rng.int(4));
        twists = ["stone"];
      } else if (rows.some((r) => r.includes("#"))) {
        twists = ["stone"];
      }
      const lanes = between(rng, tier.lanes);
      const cand = generate({
        grid: rows,
        slots: tier.slots,
        lanes,
        maxSplit: tier.maxSplit,
        minCrate: tier.minCrate,
        target: tier.target,
        seed: 9000 + i * 31 + attempt,
        tries: 120,
        budget: 30_000,
      });
      if (!cand || cand.penalty > 0) continue;
      const sig = JSON.stringify(cand.payload);
      if (seen.has(sig)) continue;
      seen.add(sig);
      counters[title] = (counters[title] ?? 0) + 1;
      const order = i + 1;
      made = {
        id: `relax-pixel-${String(order).padStart(3, "0")}`,
        mode: "pixel",
        destination: "relax-pixel",
        order,
        title: `${title} ${counters[title]}`,
        difficulty: tier.difficulty,
        twists,
        par: cand.analysis.solution.length,
        solution: cand.analysis.solution,
        payload: cand.payload,
      };
    }
    if (!made) throw new Error(`pool entry ${i}: no scene met its target`);
    entries.push(made);
  }
  return entries;
}
