/**
 * Seeded Liquid / Bolt deal generator. All randomness comes from mulberry32 (`Rng`) so regenerating
 * with the same seeds reproduces the same payloads.
 */
import { createRng, type Rng } from "../util/prng.js";
import { SortRules, type SortMove, type SortPayload } from "../modes/sortcore.js";
import { isDeadlockFree, scoreDifficulty, solveBest, type Difficulty } from "../solvers/sortSolver.js";

export interface DealSpec {
  mode: "liquid" | "bolt";
  /** Palette ids used (one entry per color). */
  colors: string[];
  /** Nuts/layers per color. */
  count: number;
  /** Base capacity of a tube/bolt. */
  capacity: number;
  /** Empty spare tubes appended after the filled ones. */
  empties: number;
  /** Hidden layers to place (liquid twist `hidden`). */
  hidden?: number;
  /** Number of locked tubes (liquid twist `lock`). */
  locks?: number;
  /** Bolt mode: explicit capacity per bolt (overrides `capacity` for those bolts; length = total bolts). */
  capacities?: number[];
  /** Bolt mode: bolts that start with nuts (default: all bolts that are not trailing empties). */
  startBolts?: number;
  /** Bolt twist `rusty`: number of rusty nuts. */
  rusty?: number;
  /** Require that no reachable state is a dead end (used for the first few levels). */
  deadlockFree?: boolean;
}

export interface Candidate {
  payload: SortPayload;
  solution: SortMove[];
  difficulty: Difficulty;
  seed: number;
}

function shuffleLayers(rng: Rng, spec: DealSpec): string[] {
  const all: string[] = [];
  for (const c of spec.colors) for (let i = 0; i < spec.count; i++) all.push(c);
  return rng.shuffle(all);
}

/** One random deal, or null when it fails basic quality checks. */
export function deal(spec: DealSpec, rng: Rng): SortPayload | null {
  const layers = shuffleLayers(rng, spec);
  let tubes: string[][];
  let capacities: number[] | undefined;
  if (spec.mode === "liquid" || !spec.capacities) {
    const filled = Math.ceil(layers.length / spec.capacity);
    tubes = [];
    for (let i = 0; i < filled; i++) tubes.push(layers.slice(i * spec.capacity, (i + 1) * spec.capacity));
    for (let i = 0; i < spec.empties; i++) tubes.push([]);
    if (spec.capacities) capacities = spec.capacities.slice();
  } else {
    capacities = spec.capacities.slice();
    const total = capacities.length;
    const start = spec.startBolts ?? total - spec.empties;
    tubes = Array.from({ length: total }, () => []);
    for (const c of layers) {
      const open: number[] = [];
      for (let i = 0; i < start; i++) if (tubes[i].length < capacities[i]) open.push(i);
      if (open.length === 0) return null;
      tubes[rng.pick(open)].push(c);
    }
  }
  const payload: SortPayload = { capacity: spec.capacity, tubes };
  if (capacities) payload.capacities = capacities;
  const caps = capacities ?? tubes.map(() => spec.capacity);

  // Quality: no tube starts finished (a full uniform tube would be a free win).
  for (const [i, t] of tubes.entries()) {
    if (t.length > 0 && t.length === caps[i] && t.every((c) => c === t[0])) return null;
  }
  if (spec.mode === "bolt") {
    // Also avoid already-uniform multi-nut bolts of a complete color.
    for (const t of tubes) if (t.length >= spec.count && t.every((c) => c === t[0])) return null;
  }

  const nonEmpty = tubes.map((t, i) => (t.length > 0 ? i : -1)).filter((i) => i >= 0);

  if ((spec.hidden ?? 0) > 0) {
    const spots: [number, number][] = [];
    for (const i of nonEmpty) for (let j = 0; j < tubes[i].length - 1; j++) spots.push([i, j]);
    const pick = rng.shuffle(spots).slice(0, spec.hidden);
    if (pick.length < (spec.hidden ?? 0)) return null;
    payload.hidden = pick.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  }
  if ((spec.locks ?? 0) > 0) {
    const chosen = rng.shuffle(nonEmpty).slice(0, spec.locks);
    const used = new Set<string>();
    payload.locks = [];
    for (const ti of chosen.sort((a, b) => a - b)) {
      const options = spec.colors.filter((c) => !tubes[ti].includes(c) && !used.has(c));
      if (options.length === 0) return null;
      const color = rng.pick(options);
      used.add(color);
      payload.locks.push({ tube: ti, color });
    }
  }
  if ((spec.rusty ?? 0) > 0) {
    const rusty: { bolt: number; index: number; color: string }[] = [];
    const candidates = rng.shuffle(nonEmpty.filter((i) => tubes[i].length >= 2));
    for (const bi of candidates) {
      if (rusty.length >= (spec.rusty ?? 0)) break;
      const nutColor = tubes[bi][0];
      const tags = spec.colors.filter((c) => c !== nutColor && !tubes[bi].includes(c) && !rusty.some((r) => r.color === c));
      if (tags.length === 0) continue;
      rusty.push({ bolt: bi, index: 0, color: rng.pick(tags) });
    }
    if (rusty.length < (spec.rusty ?? 0)) return null;
    payload.rusty = rusty.sort((a, b) => a.bolt - b.bolt);
  }
  return payload;
}

export interface SearchOptions {
  budget?: number;
  probe?: boolean;
  /** Number of random deals to try. */
  tries: number;
}

/** Generates solved candidates for `spec` from seeds `baseSeed .. baseSeed+tries-1`. */
export function candidates(spec: DealSpec, baseSeed: number, opts: SearchOptions): Candidate[] {
  const out: Candidate[] = [];
  for (let k = 0; k < opts.tries; k++) {
    const seed = baseSeed + k;
    const rng = createRng(seed);
    const payload = deal(spec, rng);
    if (!payload) continue;
    const rules = new SortRules(payload);
    const start = SortRules.initialState(payload);
    if (rules.isSolved(start)) continue;
    const r = solveBest(rules, start, opts.budget ?? 120_000);
    if (!r.solution) continue;
    if (spec.deadlockFree) {
      const ok = isDeadlockFree(rules, start, 150_000);
      if (ok !== true) continue;
    }
    const difficulty = scoreDifficulty(rules, start, r.solution, r.optimal, opts.probe ?? false);
    out.push({ payload, solution: r.solution, difficulty, seed });
  }
  return out;
}
