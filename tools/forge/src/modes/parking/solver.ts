import { apply, initialState, isSolved, legalMoves, stateKey, type PState, type ParkingMove, type ParkingPayload } from "./rules.js";

/** Breadth-first search: a shortest solution (fewest slides) or null if none within `budget` expanded states. */
export function solveParking(p: ParkingPayload, budget = 2_000_000, from?: PState): ParkingMove[] | null {
  const start = from ?? initialState(p);
  if (isSolved(p, start)) return [];
  const states: PState[] = [start];
  const parent: number[] = [-1];
  const via: (ParkingMove | null)[] = [null];
  const seen = new Set<string>([stateKey(start)]);
  for (let head = 0; head < states.length; head++) {
    if (head >= budget) return null;
    const s = states[head];
    for (const m of legalMoves(p, s)) {
      const next = apply(p, s, m)!;
      const k = stateKey(next);
      if (seen.has(k)) continue;
      seen.add(k);
      states.push(next);
      parent.push(head);
      via.push(m);
      if (isSolved(p, next)) {
        const path: ParkingMove[] = [];
        for (let i = states.length - 1; i > 0; i = parent[i]) path.push(via[i]!);
        return path.reverse();
      }
    }
  }
  return null;
}
