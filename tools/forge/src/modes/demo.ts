import type { LevelEnvelope } from "../schema.js";
import type { ModeHandlers, ReplayResult } from "./types.js";

/** Placeholder counter puzzle. Payload: {start, target, deltas}. Move: {delta}. */
interface DemoPayload {
  start: number;
  target: number;
  deltas: number[];
}
interface DemoMove {
  delta: number;
}

function isInt(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x);
}

function validate(level: LevelEnvelope): string[] {
  const errs: string[] = [];
  const p = level.payload as Partial<DemoPayload> | null;
  if (!p || typeof p !== "object") return ["payload must be an object"];
  if (!isInt(p.start)) errs.push("payload.start must be an integer");
  if (!isInt(p.target)) errs.push("payload.target must be an integer");
  if (!Array.isArray(p.deltas) || p.deltas.length === 0 || !p.deltas.every((d) => isInt(d) && d > 0)) {
    errs.push("payload.deltas must be a non-empty array of positive integers");
  }
  for (const [i, m] of level.solution.entries()) {
    if (!m || typeof m !== "object" || !isInt((m as DemoMove).delta)) errs.push(`solution[${i}] must be {delta:int}`);
  }
  return errs;
}

function replay(level: LevelEnvelope): ReplayResult {
  const p = level.payload as DemoPayload;
  let value = p.start;
  for (const [i, raw] of level.solution.entries()) {
    const d = (raw as DemoMove).delta;
    if (!p.deltas.includes(d)) return { ok: false, error: `move ${i}: delta ${d} not allowed` };
    if (value + d > p.target) return { ok: false, error: `move ${i}: overshoots target` };
    value += d;
  }
  return value === p.target ? { ok: true } : { ok: false, error: `ended at ${value}, target ${p.target}` };
}

export const demo: ModeHandlers = { mode: "demo", validate, replay };
