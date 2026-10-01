import { Rng } from "../../util/prng.js";
import { apply, initialState, isSolved, legalMoves, stateKey, withState, type Edge, type ParkingPayload, type PState, type Vehicle } from "./rules.js";
import { solveParking } from "./solver.js";

export interface ParkingSpec {
  /** 1 or 2 target vehicles. */
  targets: 1 | 2;
  /** Desired optimal (fewest slides) length range, inclusive. */
  lo: number;
  hi: number;
  minVehicles: number;
  maxVehicles: number;
  /** Max boards to try before giving up. */
  attempts?: number;
  /** Stop searching once a board at least this long is found (default hi). */
  stopAt?: number;
}

const IDS = "ABCDEFGHJKLMNPQRSVWXYZ";

/** Random board: target(s) on their gate lines plus random fill. */
function randomBoard(rng: Rng, spec: ParkingSpec): ParkingPayload {
  const n = 6;
  const vehicles: Vehicle[] = [];
  const gates: ParkingPayload["gates"] = [];
  const occ = new Set<number>();
  const fits = (v: Vehicle) => {
    for (let k = 0; k < v.len; k++) {
      const r = v.axis === "h" ? v.r : v.r + k;
      const c = v.axis === "h" ? v.c + k : v.c;
      if (r < 0 || c < 0 || r >= n || c >= n || occ.has(r * n + c)) return false;
    }
    return true;
  };
  const put = (v: Vehicle) => {
    vehicles.push(v);
    for (let k = 0; k < v.len; k++) occ.add((v.axis === "h" ? v.r : v.r + k) * n + (v.axis === "h" ? v.c + k : v.c));
  };
  // Target 1: horizontal in a random row, gate on the right (or left).
  const row = 1 + rng.int(4);
  const edge1: Edge = rng.next() < 0.7 ? "right" : "left";
  put({ id: "T", r: row, c: edge1 === "right" ? rng.int(3) : 2 + rng.int(3), len: 2, axis: "h", target: true });
  gates.push({ target: "T", edge: edge1, index: row });
  if (spec.targets === 2) {
    for (let tries = 0; tries < 40; tries++) {
      const col = 1 + rng.int(4);
      const edge2: Edge = rng.next() < 0.6 ? "bottom" : "top";
      const v: Vehicle = { id: "U", r: edge2 === "bottom" ? rng.int(3) : 2 + rng.int(3), c: col, len: 2, axis: "v", target: true };
      if (fits(v)) {
        put(v);
        gates.push({ target: "U", edge: edge2, index: col });
        break;
      }
    }
  }
  const total = spec.minVehicles + rng.int(spec.maxVehicles - spec.minVehicles + 1);
  let idx = 0;
  for (let tries = 0; tries < 200 && vehicles.length < total; tries++) {
    const axis = rng.next() < 0.5 ? "h" : "v";
    const len = rng.next() < 0.3 ? 3 : 2;
    const v: Vehicle = { id: IDS[idx], r: rng.int(n), c: rng.int(n), len, axis };
    if (fits(v)) {
      put(v);
      idx++;
    }
  }
  return { size: n, vehicles, gates };
}

/** Enumerate the component reachable from the initial state (capped) and BFS distances to solved states. */
function distancesToSolved(p: ParkingPayload, cap: number): { states: PState[]; dist: number[] } | null {
  const states: PState[] = [initialState(p)];
  const index = new Map<string, number>([[stateKey(states[0]), 0]]);
  const adj: number[][] = [];
  for (let head = 0; head < states.length; head++) {
    if (states.length > cap) return null;
    const nb: number[] = [];
    for (const m of legalMoves(p, states[head])) {
      const next = apply(p, states[head], m)!;
      const k = stateKey(next);
      let j = index.get(k);
      if (j === undefined) {
        j = states.length;
        index.set(k, j);
        states.push(next);
      }
      nb.push(j);
    }
    adj.push(nb);
  }
  // Slides are reversible (d then -d), so the graph is undirected: multi-source BFS from the solved states.
  const dist = new Array<number>(states.length).fill(-1);
  const queue: number[] = [];
  states.forEach((s, i) => {
    if (isSolved(p, s)) {
      dist[i] = 0;
      queue.push(i);
    }
  });
  for (let h = 0; h < queue.length; h++) {
    for (const j of adj[queue[h]]) {
      if (dist[j] < 0) {
        dist[j] = dist[queue[h]] + 1;
        queue.push(j);
      }
    }
  }
  return { states, dist };
}

export interface GeneratedParking {
  payload: ParkingPayload;
  optimal: number;
}

/** Generate a board whose optimal solution length lies in [spec.lo, spec.hi]. Deterministic for a seed. */
export function generateParking(seed: number, spec: ParkingSpec): GeneratedParking | null {
  const rng = new Rng(seed);
  const attempts = spec.attempts ?? 4000;
  let best: GeneratedParking | null = null;
  for (let a = 0; a < attempts; a++) {
    const board = randomBoard(rng, spec);
    if (spec.targets === 2 && board.gates.length < 2) continue;
    const res = distancesToSolved(board, 120_000);
    if (!res) continue;
    let top = -1;
    for (const d of res.dist) if (d >= spec.lo && d <= spec.hi && d > top) top = d;
    if (top < 0) continue;
    if (best && top <= best.optimal) continue;
    const cands: number[] = [];
    res.dist.forEach((d, i) => {
      if (d === top) cands.push(i);
    });
    const payload = withState(board, res.states[cands[rng.int(cands.length)]]);
    if (isSolved(payload, initialState(payload))) continue;
    best = { payload, optimal: top };
    if (top >= (spec.stopAt ?? spec.hi)) break;
  }
  if (best) {
    const sol = solveParking(best.payload);
    if (!sol || sol.length !== best.optimal) return null;
  }
  return best;
}
