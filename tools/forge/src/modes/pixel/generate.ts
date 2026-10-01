import { createRng, type Rng } from "../../util/prng.js";
import { analyze, type Analysis } from "./solver.js";
import { colorCounts, type Crate, type PixelPayload } from "./rules.js";

/** What a generated level must look like. Every bound is inclusive; omitted = unconstrained. */
export interface Target {
  /** Allowed range of crates in total. */
  crates?: [number, number];
  doomedFraction?: [number, number];
  pStuck?: [number, number];
  firstTraps?: [number, number];
  winningLines?: [number, number];
  /** Preferred pStuck (candidates closest to it win ties inside the allowed ranges). */
  prefer?: { pStuck?: number; firstTraps?: number };
}

export interface GenSpec {
  grid: string[];
  slots: number;
  lanes: number;
  /** Max crates one color may be split into (1..3). */
  maxSplit: number;
  /** Smallest crate size when splitting. */
  minCrate: number;
  target: Target;
  seed: number;
  tries: number;
  budget?: number;
}

export interface Candidate {
  payload: PixelPayload;
  analysis: Analysis;
  /** 0 = inside every bound; larger = further away. */
  penalty: number;
}

function splitCount(n: number, k: number, minSize: number, rng: Rng): number[] {
  if (k <= 1) return [n];
  // random composition of n into k parts, each >= minSize
  const spare = n - k * minSize;
  if (spare < 0) return splitCount(n, k - 1, minSize, rng);
  const cuts: number[] = [];
  for (let i = 0; i < k - 1; i++) cuts.push(rng.int(spare + 1));
  cuts.sort((a, b) => a - b);
  const parts: number[] = [];
  let prev = 0;
  for (const c of cuts) {
    parts.push(minSize + c - prev);
    prev = c;
  }
  parts.push(minSize + spare - prev);
  return parts;
}

function rangePenalty(v: number, r?: [number, number]): number {
  if (!r) return 0;
  if (v < r[0]) return r[0] - v;
  if (v > r[1]) return v - r[1];
  return 0;
}

export function makeLanes(grid: string[], lanes: number, maxSplit: number, minCrate: number, rng: Rng, crateRange?: [number, number]): Crate[][] | null {
  const counts = colorCounts(grid);
  const crates: Crate[] = [];
  for (const color of Object.keys(counts).sort()) {
    const n = counts[color]!;
    const k = 1 + rng.int(maxSplit);
    for (const part of splitCount(n, k, minCrate, rng)) crates.push({ color, count: part });
  }
  if (crateRange && (crates.length < crateRange[0] || crates.length > crateRange[1])) return null;
  const order = rng.shuffle(crates);
  const out: Crate[][] = Array.from({ length: lanes }, () => []);
  // Deal so that every lane gets at least one crate.
  order.forEach((c, i) => {
    const lane = i < lanes ? i : rng.int(lanes);
    out[lane]!.push(c);
  });
  return out;
}

export function evaluate(payload: PixelPayload, target: Target, budget: number): Candidate {
  const analysis = analyze(payload, budget);
  let penalty = 0;
  if (!analysis.complete || !analysis.solvable) penalty = 1e6;
  else {
    penalty += 10 * rangePenalty(analysis.doomedFraction, target.doomedFraction);
    penalty += 10 * rangePenalty(analysis.pStuck, target.pStuck);
    penalty += rangePenalty(analysis.firstTraps, target.firstTraps);
    penalty += 0.01 * rangePenalty(analysis.winningLines, target.winningLines);
    const total = payload.lanes.reduce((n, l) => n + l.length, 0);
    penalty += rangePenalty(total, target.crates);
  }
  return { payload, analysis, penalty };
}

/** Deterministic search. Returns the best candidate found (penalty 0 when a perfect one exists). */
export function generate(spec: GenSpec): Candidate | null {
  const rng = createRng(spec.seed);
  const budget = spec.budget ?? 60_000;
  let best: Candidate | null = null;
  let bestScore = Infinity;
  const prefer = spec.target.prefer;
  for (let t = 0; t < spec.tries; t++) {
    const lanes = makeLanes(spec.grid, spec.lanes, spec.maxSplit, spec.minCrate, rng, spec.target.crates);
    if (!lanes) continue;
    const payload: PixelPayload = { grid: spec.grid, slots: spec.slots, lanes };
    const cand = evaluate(payload, spec.target, budget);
    let score = cand.penalty;
    if (cand.penalty < 1e5 && prefer) {
      if (prefer.pStuck !== undefined) score += 0.5 * Math.abs(cand.analysis.pStuck - prefer.pStuck);
      if (prefer.firstTraps !== undefined) score += 0.05 * Math.abs(cand.analysis.firstTraps - prefer.firstTraps);
    }
    if (score < bestScore) {
      best = cand;
      bestScore = score;
    }
    if (!prefer && cand.penalty === 0) break;
  }
  return best;
}
