import type { LevelEnvelope } from "../../schema.js";
import type { ModeHandlers, ReplayResult } from "../types.js";
import { apply, initialState, isSolved, type ParkingMove, type ParkingPayload } from "./rules.js";
import { solveParking } from "./solver.js";

function isInt(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x);
}

function validate(level: LevelEnvelope): string[] {
  const errs: string[] = [];
  const p = level.payload as Partial<ParkingPayload> | null;
  if (!p || typeof p !== "object") return ["payload must be an object"];
  if (p.size !== undefined && !(isInt(p.size) && p.size >= 4 && p.size <= 8)) errs.push("payload.size must be an integer 4..8");
  if (!Array.isArray(p.vehicles) || p.vehicles.length === 0) return [...errs, "payload.vehicles must be a non-empty array"];
  if (!Array.isArray(p.gates) || p.gates.length === 0) return [...errs, "payload.gates must be a non-empty array"];
  const n = p.size ?? 6;
  const ids = new Set<string>();
  const grid = new Set<number>();
  for (const [i, v] of p.vehicles.entries()) {
    const w = `vehicles[${i}]`;
    if (typeof v.id !== "string" || !v.id) errs.push(`${w}.id must be a non-empty string`);
    else if (ids.has(v.id)) errs.push(`${w}: duplicate id ${v.id}`);
    else ids.add(v.id);
    if (!isInt(v.r) || !isInt(v.c) || !isInt(v.len)) {
      errs.push(`${w}: r, c, len must be integers`);
      continue;
    }
    if (v.len < 2 || v.len > 3) errs.push(`${w}: len must be 2 or 3`);
    if (v.axis !== "h" && v.axis !== "v") {
      errs.push(`${w}: axis must be "h" or "v"`);
      continue;
    }
    for (let k = 0; k < v.len; k++) {
      const r = v.axis === "h" ? v.r : v.r + k;
      const c = v.axis === "h" ? v.c + k : v.c;
      if (r < 0 || c < 0 || r >= n || c >= n) {
        errs.push(`${w}: out of bounds`);
        break;
      }
      if (grid.has(r * n + c)) {
        errs.push(`${w}: overlaps another vehicle at (${r},${c})`);
        break;
      }
      grid.add(r * n + c);
    }
  }
  const gateTargets = new Set<string>();
  for (const [i, g] of p.gates.entries()) {
    const w = `gates[${i}]`;
    const v = p.vehicles.find((x) => x.id === g.target);
    if (!v) {
      errs.push(`${w}: unknown target ${g.target}`);
      continue;
    }
    if (gateTargets.has(g.target)) errs.push(`${w}: duplicate gate for ${g.target}`);
    gateTargets.add(g.target);
    if (!v.target) errs.push(`${w}: vehicle ${g.target} must be flagged target:true`);
    const horizontal = g.edge === "left" || g.edge === "right";
    if (!horizontal && g.edge !== "top" && g.edge !== "bottom") errs.push(`${w}: bad edge`);
    else if (horizontal && !(v.axis === "h" && v.r === g.index)) errs.push(`${w}: ${g.target} must be horizontal in row ${g.index}`);
    else if (!horizontal && !(v.axis === "v" && v.c === g.index)) errs.push(`${w}: ${g.target} must be vertical in column ${g.index}`);
  }
  for (const v of p.vehicles) if (v.target && !gateTargets.has(v.id)) errs.push(`vehicle ${v.id} is a target without a gate`);
  if (errs.length) return errs;
  for (const [i, m] of level.solution.entries()) {
    const mv = m as ParkingMove;
    if (!mv || typeof mv.id !== "string" || !isInt(mv.delta)) errs.push(`solution[${i}] must be {id:string, delta:int}`);
  }
  if (!errs.length && isSolved(p as ParkingPayload, initialState(p as ParkingPayload))) errs.push("level starts solved");
  return errs;
}

function replay(level: LevelEnvelope): ReplayResult {
  const p = level.payload as ParkingPayload;
  let s = initialState(p);
  for (const [i, raw] of level.solution.entries()) {
    if (isSolved(p, s)) return { ok: false, error: `move ${i}: solution continues after the level is solved` };
    const next = apply(p, s, raw as ParkingMove);
    if (!next) return { ok: false, error: `move ${i}: illegal ${JSON.stringify(raw)}` };
    s = next;
  }
  return isSolved(p, s) ? { ok: true } : { ok: false, error: "final state is not solved" };
}

export const parking: ModeHandlers = {
  mode: "parking",
  validate,
  replay,
  solve: (level, budget) => solveParking(level.payload as ParkingPayload, budget),
};
