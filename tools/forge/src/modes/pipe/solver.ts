import { DC, DR, isSolved, maskOf, type PipeBoard, type PipeMove, type PipeState } from "./rules.js";

export interface PipeSolution {
  /** Target rotation for every tile (unassigned tiles keep their initial rotation). */
  rots: number[];
  /** Total clockwise taps from the initial state. */
  cost: number;
  /** Tap list, row-major, repeated taps for tiles needing several turns. */
  moves: PipeMove[];
  /** True when the search finished within budget (cost is then the proven minimum below `upperBound`). */
  exhaustive: boolean;
}

/** Fewest clockwise taps for tile i to show a mask containing `needMask`, with the resulting rotation. */
function options(b: PipeBoard, cur: number[], i: number, needMask: number): { rot: number; cost: number }[] {
  const kind = b.kinds[i];
  const out: { rot: number; cost: number; mask: number }[] = [];
  const maxK = b.fixed[i] ? 1 : 4;
  for (let k = 0; k < maxK; k++) {
    const rot = (cur[i] + k) % 4;
    const mask = maskOf(kind, rot);
    if ((mask & needMask) !== needMask) continue;
    // Keep the cheapest rotation for each distinct mask.
    if (out.some((o) => o.mask === mask)) continue;
    out.push({ rot, cost: k, mask });
  }
  return out;
}

/**
 * Backtracking search for a minimum-tap solved configuration. Tiles outside the flow tree are never turned
 * (cost 0), connectivity is the only requirement (dangling ends are allowed), and the search grows the flow
 * outward from the source in breadth-first order, branching on each open side: join the neighbor (every
 * rotation that opens back toward us) or leave it alone. Cost-bounded; `upperBound` is the best known cost
 * (for example from the generator's planted solution) and only strictly cheaper solutions are returned.
 */
export function solvePipe(b: PipeBoard, budget = 400_000, upperBound = Infinity): { solution: PipeSolution | null; exhaustive: boolean } {
  const n = b.kinds.length;
  const assigned = new Array<number>(n).fill(-1);
  const queue: [number, number][] = []; // (tile, direction index of the open side)
  let best = upperBound;
  let bestRots: number[] | null = null;
  let nodes = 0;
  let aborted = false;
  let destsLeft = b.destIndices.length;

  const assign = (i: number, rot: number, enteredFrom: number): number => {
    assigned[i] = rot;
    const m = maskOf(b.kinds[i], rot);
    const before = queue.length;
    for (let d = 0; d < 4; d++) {
      if (d === enteredFrom || !(m & (1 << d))) continue;
      queue.push([i, d]);
    }
    return queue.length - before;
  };

  const rec = (qi: number, cost: number): void => {
    if (aborted) return;
    if (++nodes > budget) {
      aborted = true;
      return;
    }
    if (cost >= best) return;
    if (destsLeft === 0) {
      best = cost;
      bestRots = assigned.map((a, i) => (a < 0 ? b.rots[i] : a));
      return;
    }
    if (qi >= queue.length) return;
    const [a, d] = queue[qi];
    const ar = Math.floor(a / b.cols);
    const ac = a % b.cols;
    const nr = ar + DR[d];
    const nc = ac + DC[d];
    const inside = nr >= 0 && nc >= 0 && nr < b.rows && nc < b.cols;
    const t = inside ? nr * b.cols + nc : -1;
    if (t < 0 || b.kinds[t] === "." || assigned[t] >= 0) {
      rec(qi + 1, cost);
      return;
    }
    const opts = options(b, b.rots, t, 1 << ((d + 2) % 4)).sort((x, y) => x.cost - y.cost);
    for (const o of opts) {
      const isDest = b.kinds[t] === "D";
      const pushed = assign(t, o.rot, (d + 2) % 4);
      if (isDest) destsLeft--;
      rec(qi + 1, cost + o.cost);
      if (isDest) destsLeft++;
      queue.length -= pushed;
      assigned[t] = -1;
      if (aborted) return;
    }
    rec(qi + 1, cost); // leave the neighbor alone
  };

  const s = b.sourceIndex;
  if (s < 0) return { solution: null, exhaustive: true };
  const srcOpts = b.fixed[s] ? [{ rot: b.rots[s], cost: 0 }] : options(b, b.rots, s, 0);
  for (const o of srcOpts.sort((x, y) => x.cost - y.cost)) {
    const pushed = assign(s, o.rot, -1);
    rec(0, o.cost);
    queue.length -= pushed;
    assigned[s] = -1;
    if (aborted) break;
  }
  if (!bestRots) return { solution: null, exhaustive: !aborted };
  const rots = bestRots as number[];
  const moves: PipeMove[] = [];
  let cost = 0;
  for (let i = 0; i < n; i++) {
    if (b.kinds[i] === ".") continue;
    const k = (rots[i] - b.rots[i] + 4) % 4;
    for (let j = 0; j < k; j++) moves.push({ r: Math.floor(i / b.cols), c: i % b.cols });
    cost += k;
  }
  const state: PipeState = rots;
  if (!isSolved(b, state)) throw new Error("internal error: pipe solver produced an unsolved configuration");
  return { solution: { rots, cost, moves, exhaustive: !aborted }, exhaustive: !aborted };
}
