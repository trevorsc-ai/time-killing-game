/**
 * A* solver for Liquid / Bolt Sort with canonical state hashing (tube order is irrelevant).
 * Swift mirror: PuzzleGetaway/Modes/Sort/SortSolver.swift.
 */
import type { LevelEnvelope } from "../schema.js";
import { SortRules, type Layer, type SortMove, type SortPayload, type SortState } from "../modes/sortcore.js";

export interface SolveOptions {
  /** Heuristic weight. 1 = optimal (admissible, consistent heuristic); >1 = faster, longer paths. */
  weight?: number;
  /** Maximum expanded nodes. */
  budget?: number;
}

export interface SolveResult {
  solution: SortMove[] | null;
  expanded: number;
  /** True when the whole reachable space was searched (so `solution === null` proves unsolvable). */
  exhausted: boolean;
}

function layerKey(l: Layer): string {
  return l.c + (l.h ? "?" : "") + (l.r ? "~" + l.r : "");
}

/** Canonical key: tubes described by (capacity, lock, layers) and sorted. */
export function canonicalKey(rules: SortRules, s: SortState): string {
  const parts: string[] = new Array(s.tubes.length);
  for (let i = 0; i < s.tubes.length; i++) {
    let str = rules.caps[i] + (s.locks[i] ? "L" + s.locks[i] : "") + ":";
    for (const l of s.tubes[i]) str += layerKey(l);
    parts[i] = str;
  }
  parts.sort();
  return parts.join("|");
}

/** Number of color boundaries (adjacent differing layers) over all tubes: an admissible lower bound on moves. */
export function boundaries(s: SortState): number {
  let n = 0;
  for (const t of s.tubes) for (let i = 1; i < t.length; i++) if (t[i].c !== t[i - 1].c) n++;
  return n;
}

/** Legal moves minus provably pointless ones (a plain relabeling: whole uniform tube into an equal-capacity empty tube). */
export function prunedMoves(rules: SortRules, s: SortState): SortMove[] {
  const out: SortMove[] = [];
  for (const m of rules.legalMoves(s)) {
    const src = s.tubes[m.from];
    const dst = s.tubes[m.to];
    if (dst.length === 0 && rules.caps[m.from] === rules.caps[m.to] && isPlainUniform(src)) continue;
    out.push(m);
  }
  return out;
}

function isPlainUniform(t: readonly Layer[]): boolean {
  const c = t[0].c;
  for (const l of t) if (l.c !== c || l.h || l.r) return false;
  return true;
}

interface Node {
  s: SortState;
  g: number;
  f: number;
  parent: Node | null;
  move: SortMove | null;
}

class MinHeap {
  private a: Node[] = [];
  get size(): number {
    return this.a.length;
  }
  private less(x: Node, y: Node): boolean {
    return x.f < y.f || (x.f === y.f && x.g > y.g);
  }
  push(n: Node): void {
    const a = this.a;
    a.push(n);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (!this.less(a[i], a[p])) break;
      [a[i], a[p]] = [a[p], a[i]];
      i = p;
    }
  }
  pop(): Node | undefined {
    const a = this.a;
    if (a.length === 0) return undefined;
    const top = a[0];
    const last = a.pop() as Node;
    if (a.length > 0) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < a.length && this.less(a[l], a[m])) m = l;
        if (r < a.length && this.less(a[r], a[m])) m = r;
        if (m === i) break;
        [a[i], a[m]] = [a[m], a[i]];
        i = m;
      }
    }
    return top;
  }
}

export function solveFrom(rules: SortRules, start: SortState, opts: SolveOptions = {}): SolveResult {
  const weight = opts.weight ?? 1;
  const budget = opts.budget ?? 200_000;
  if (rules.isSolved(start)) return { solution: [], expanded: 0, exhausted: true };
  const heap = new MinHeap();
  const best = new Map<string, number>();
  const root: Node = { s: start, g: 0, f: weight * boundaries(start), parent: null, move: null };
  heap.push(root);
  best.set(canonicalKey(rules, start), 0);
  let expanded = 0;
  while (heap.size > 0) {
    const node = heap.pop() as Node;
    const key = canonicalKey(rules, node.s);
    if ((best.get(key) ?? Infinity) < node.g) continue;
    if (rules.isSolved(node.s)) {
      const path: SortMove[] = [];
      for (let n: Node | null = node; n && n.move; n = n.parent) path.push(n.move);
      return { solution: path.reverse(), expanded, exhausted: false };
    }
    if (expanded >= budget) return { solution: null, expanded, exhausted: false };
    expanded++;
    for (const m of prunedMoves(rules, node.s)) {
      const next = rules.apply(m, node.s);
      if (!next) continue;
      const g = node.g + 1;
      const k = canonicalKey(rules, next);
      if ((best.get(k) ?? Infinity) <= g) continue;
      best.set(k, g);
      heap.push({ s: next, g, f: g + weight * boundaries(next), parent: node, move: m });
    }
  }
  return { solution: null, expanded, exhausted: true };
}

/** Solver entry used by the mode handlers. */
export function solveForLevel(level: LevelEnvelope, budget = 200_000): SortMove[] | null {
  const p = level.payload as SortPayload;
  const rules = new SortRules(p);
  return solveFrom(rules, SortRules.initialState(p), { weight: 1, budget }).solution;
}

/** Optimal if possible within `budget`, otherwise a best-known solution via weighted search. */
export function solveBest(rules: SortRules, start: SortState, budget = 200_000): { solution: SortMove[] | null; optimal: boolean; exhausted: boolean } {
  const exact = solveFrom(rules, start, { weight: 1, budget });
  if (exact.solution) return { solution: exact.solution, optimal: true, exhausted: false };
  if (exact.exhausted) return { solution: null, optimal: false, exhausted: true };
  for (const w of [2, 4, 8]) {
    const r = solveFrom(rules, start, { weight: w, budget: Math.max(budget, 100_000) });
    if (r.solution) return { solution: r.solution, optimal: false, exhausted: false };
    if (r.exhausted) return { solution: null, optimal: false, exhausted: true };
  }
  return { solution: null, optimal: false, exhausted: false };
}

export interface Difficulty {
  par: number;
  optimal: boolean;
  /** Mean number of pruned legal moves over the states along the solution. */
  branching: number;
  /** Fraction of pruned moves along the solution that lead to a provably unsolvable state (probed with a small budget). */
  deadEnd: number;
  /** Combined score: higher is harder. */
  score: number;
}

/** Scores a solved candidate. `probe` enables the (slower) dead-end ratio. */
export function scoreDifficulty(rules: SortRules, start: SortState, solution: SortMove[], optimal: boolean, probe: boolean): Difficulty {
  let s = start;
  let branchSum = 0;
  let dead = 0;
  let total = 0;
  for (const m of solution) {
    const moves = prunedMoves(rules, s);
    branchSum += moves.length;
    if (probe) {
      for (const alt of moves) {
        const next = rules.apply(alt, s);
        if (!next) continue;
        total++;
        const r = solveFrom(rules, next, { weight: 3, budget: 1500 });
        if (r.solution === null && r.exhausted) dead++;
      }
    }
    s = rules.apply(m, s) as SortState;
  }
  const branching = solution.length ? branchSum / solution.length : 0;
  const deadEnd = total ? dead / total : 0;
  return { par: solution.length, optimal, branching, deadEnd, score: solution.length + 1.5 * branching + 30 * deadEnd };
}

/**
 * True iff from every state reachable from `start` a solved state is reachable (no deadlocks).
 * Returns null if the reachable space exceeds `limit` states.
 */
export function isDeadlockFree(rules: SortRules, start: SortState, limit = 200_000): boolean | null {
  const index = new Map<string, number>();
  const states: SortState[] = [];
  const preds: number[][] = [];
  const solved: number[] = [];
  const add = (s: SortState): number => {
    const k = canonicalKey(rules, s);
    const got = index.get(k);
    if (got !== undefined) return got;
    index.set(k, states.length);
    states.push(s);
    preds.push([]);
    if (rules.isSolved(s)) solved.push(states.length - 1);
    return states.length - 1;
  };
  add(start);
  for (let i = 0; i < states.length; i++) {
    if (states.length > limit) return null;
    const s = states[i];
    if (rules.isSolved(s)) continue;
    for (const m of prunedMoves(rules, s)) {
      const next = rules.apply(m, s);
      if (!next) continue;
      const j = add(next);
      preds[j].push(i);
    }
  }
  const good = new Uint8Array(states.length);
  const stack = solved.slice();
  for (const x of stack) good[x] = 1;
  while (stack.length) {
    const x = stack.pop() as number;
    for (const p of preds[x]) {
      if (!good[p]) {
        good[p] = 1;
        stack.push(p);
      }
    }
  }
  return good.every((v) => v === 1);
}
