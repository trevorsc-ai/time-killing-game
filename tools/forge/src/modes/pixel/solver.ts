import { apply, initialState, isSolved, legalMoves, stateKey, type PixelMove, type PixelPayload, type PixelState } from "./rules.js";

export interface Analysis {
  /** False if the state budget was exhausted before the search finished (all other fields are then partial). */
  complete: boolean;
  solvable: boolean;
  /** Lane taps of one winning line (the lexicographically first winning line). */
  solution: PixelMove[];
  /** Reachable states explored. */
  states: number;
  /** Reachable states from which the level can no longer be won (including dead ends that are stuck). */
  doomed: number;
  /** doomed / states. 0 means no sequence of taps can ever get stuck. */
  doomedFraction: number;
  /** Legal first taps. */
  firstMoves: number;
  /** First taps after which the level is lost for good. */
  firstTraps: number;
  /** Probability that uniformly random legal taps end in a stuck (jammed) state. */
  pStuck: number;
  /** Number of distinct winning tap sequences (capped at 1e9). */
  winningLines: number;
  /** Fewest taps that still keep the board winnable at the "most dangerous" moment: min over winning lines of
   * the maximum number of occupied slots. */
  minPeakSlots: number;
  /** Shallowest depth at which a doomed state is first reachable (Infinity if none). */
  trapDepth: number;
}

interface Node {
  solvable: boolean;
  pStuck: number;
  lines: number;
  peak: number; // min over winning continuations of the max occupied slots seen from here on
  depth: number; // min depth (taps from here) to reach a doomed state; Infinity if none
}

function occupied(s: PixelState): number {
  let n = 0;
  for (const c of s.slotColor) if (c !== 0) n++;
  return n;
}

/** Exhaustive memoized DFS over lane-tap sequences. */
export function analyze(p: PixelPayload, budget = 200_000): Analysis {
  const memo = new Map<string, Node>();
  let over = false;
  const bestMove = new Map<string, number>();

  const visit = (s: PixelState): Node => {
    const key = stateKey(s);
    const hit = memo.get(key);
    if (hit) return hit;
    if (memo.size >= budget) {
      over = true;
      return { solvable: false, pStuck: 1, lines: 0, peak: 99, depth: Infinity };
    }
    let node: Node;
    if (isSolved(s)) {
      node = { solvable: true, pStuck: 0, lines: 1, peak: occupied(s), depth: Infinity };
    } else {
      const moves = legalMoves(p, s);
      if (moves.length === 0) {
        node = { solvable: false, pStuck: 1, lines: 0, peak: 99, depth: 0 };
      } else {
        let solvable = false;
        let pSum = 0;
        let lines = 0;
        let peak = 99;
        let depth = Infinity;
        let first = -1;
        for (const m of moves) {
          const n = apply(p, s, m)!;
          const c = visit(n);
          pSum += c.pStuck;
          if (c.solvable) {
            if (first < 0) first = m.lane;
            solvable = true;
            lines = Math.min(1e9, lines + c.lines);
            peak = Math.min(peak, Math.max(occupied(n), c.peak));
          }
          depth = Math.min(depth, c.depth + 1);
        }
        if (first >= 0) bestMove.set(key, first);
        node = { solvable, pStuck: pSum / moves.length, lines, peak, depth: solvable ? depth : 0 };
        if (!solvable) node.depth = 0;
      }
    }
    memo.set(key, node);
    return node;
  };

  const start = initialState(p);
  const root = visit(start);

  // Recompute depth-to-doom correctly: a doomed (unsolvable) reachable state has depth 0 by definition above;
  // for solvable states depth is the min over children (+1). `visit` already encodes that.
  let doomed = 0;
  for (const n of memo.values()) if (!n.solvable) doomed++;

  // First-move analysis.
  const first = legalMoves(p, start);
  let traps = 0;
  for (const m of first) {
    const n = apply(p, start, m)!;
    if (!memo.get(stateKey(n))?.solvable) traps++;
  }

  // Reconstruct a winning line.
  const solution: PixelMove[] = [];
  if (root.solvable) {
    let s = start;
    for (let guard = 0; guard < 500 && !isSolved(s); guard++) {
      const lane = bestMove.get(stateKey(s));
      if (lane === undefined) break;
      solution.push({ lane });
      s = apply(p, s, { lane })!;
    }
  }

  return {
    complete: !over,
    solvable: root.solvable,
    solution,
    states: memo.size,
    doomed,
    doomedFraction: memo.size ? doomed / memo.size : 0,
    firstMoves: first.length,
    firstTraps: traps,
    pStuck: root.pStuck,
    winningLines: root.lines,
    minPeakSlots: root.peak,
    trapDepth: root.depth,
  };
}

/** Quick yes/no solvability with an early exit (used by generators and validation). */
export function solve(p: PixelPayload, budget = 200_000): PixelMove[] | null {
  const seen = new Set<string>();
  let count = 0;
  const path: PixelMove[] = [];
  const dfs = (s: PixelState): boolean => {
    if (isSolved(s)) return true;
    const key = stateKey(s);
    if (seen.has(key)) return false;
    seen.add(key);
    if (++count > budget) return false;
    for (const m of legalMoves(p, s)) {
      path.push(m);
      if (dfs(apply(p, s, m)!)) return true;
      path.pop();
    }
    return false;
  };
  return dfs(initialState(p)) ? path.slice() : null;
}
