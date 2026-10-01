/**
 * Baggage Jam rules (docs/rules.md, "Baggage Jam"). Must match PuzzleGetaway/Modes/Parking/ParkingRules.swift.
 * State is the position of every vehicle along its own axis: the column for "h" vehicles, the row for "v" vehicles.
 */
export type Axis = "h" | "v";
export type Edge = "left" | "right" | "top" | "bottom";

export interface Vehicle {
  id: string;
  r: number;
  c: number;
  len: number;
  axis: Axis;
  target?: boolean;
}
export interface Gate {
  target: string;
  edge: Edge;
  index: number;
}
export interface ParkingPayload {
  size?: number;
  vehicles: Vehicle[];
  gates: Gate[];
}
export interface ParkingMove {
  id: string;
  delta: number;
}
/** Position along the axis, one entry per vehicle (payload order). */
export type PState = number[];

export const sizeOf = (p: ParkingPayload): number => p.size ?? 6;

export function initialState(p: ParkingPayload): PState {
  return p.vehicles.map((v) => (v.axis === "h" ? v.c : v.r));
}

/** Cell -> vehicle index (or -1), row-major. */
export function occupancy(p: ParkingPayload, s: PState): number[] {
  const n = sizeOf(p);
  const grid = new Array<number>(n * n).fill(-1);
  p.vehicles.forEach((v, i) => {
    for (let k = 0; k < v.len; k++) {
      const r = v.axis === "h" ? v.r : s[i] + k;
      const c = v.axis === "h" ? s[i] + k : v.c;
      grid[r * n + c] = i;
    }
  });
  return grid;
}

/** Inclusive range of legal deltas for vehicle i: [minDelta (<=0), maxDelta (>=0)]. */
export function slideRange(p: ParkingPayload, s: PState, i: number, occ?: number[]): [number, number] {
  const n = sizeOf(p);
  const v = p.vehicles[i];
  const grid = occ ?? occupancy(p, s);
  const pos = s[i];
  const cell = (q: number) => (v.axis === "h" ? grid[v.r * n + q] : grid[q * n + v.c]);
  let lo = 0;
  while (pos + lo - 1 >= 0 && cell(pos + lo - 1) === -1) lo--;
  let hi = 0;
  while (pos + v.len + hi < n && cell(pos + v.len + hi) === -1) hi++;
  return [lo, hi];
}

/** Deterministic order: vehicles in payload order, deltas ascending (-k..-1 then 1..k). */
export function legalMoves(p: ParkingPayload, s: PState): ParkingMove[] {
  const occ = occupancy(p, s);
  const out: ParkingMove[] = [];
  p.vehicles.forEach((v, i) => {
    const [lo, hi] = slideRange(p, s, i, occ);
    for (let d = lo; d <= hi; d++) if (d !== 0) out.push({ id: v.id, delta: d });
  });
  return out;
}

export function apply(p: ParkingPayload, s: PState, m: ParkingMove): PState | null {
  const i = p.vehicles.findIndex((v) => v.id === m.id);
  if (i < 0 || !Number.isInteger(m.delta) || m.delta === 0) return null;
  const [lo, hi] = slideRange(p, s, i);
  if (m.delta < lo || m.delta > hi) return null;
  const next = s.slice();
  next[i] += m.delta;
  return next;
}

export function isSolved(p: ParkingPayload, s: PState): boolean {
  const n = sizeOf(p);
  for (const g of p.gates) {
    const i = p.vehicles.findIndex((v) => v.id === g.target);
    if (i < 0) return false;
    const v = p.vehicles[i];
    const pos = s[i];
    switch (g.edge) {
      case "right":
        if (!(v.axis === "h" && pos + v.len === n)) return false;
        break;
      case "left":
        if (!(v.axis === "h" && pos === 0)) return false;
        break;
      case "bottom":
        if (!(v.axis === "v" && pos + v.len === n)) return false;
        break;
      case "top":
        if (!(v.axis === "v" && pos === 0)) return false;
        break;
    }
  }
  return true;
}

export function stateKey(s: PState): string {
  return s.join(",");
}

/** Payload with vehicles moved to the given state. */
export function withState(p: ParkingPayload, s: PState): ParkingPayload {
  return {
    ...p,
    vehicles: p.vehicles.map((v, i) => (v.axis === "h" ? { ...v, c: s[i] } : { ...v, r: s[i] })),
  };
}
