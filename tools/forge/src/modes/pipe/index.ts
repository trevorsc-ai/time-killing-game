import type { LevelEnvelope } from "../../schema.js";
import type { ModeHandlers, ReplayResult } from "../types.js";
import { apply, initialState, isSolved, parseBoard, parseToken, type PipeMove, type PipePayload } from "./rules.js";
import { solvePipe } from "./solver.js";

function isInt(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x);
}

function validate(level: LevelEnvelope): string[] {
  const errs: string[] = [];
  const p = level.payload as Partial<PipePayload> | null;
  if (!p || typeof p !== "object") return ["payload must be an object"];
  if (!Array.isArray(p.grid) || p.grid.length < 2 || p.grid.length > 9) return ["payload.grid must be an array of 2..9 rows"];
  const cols = Array.isArray(p.grid[0]) ? p.grid[0].length : 0;
  if (cols < 2 || cols > 9) return ["payload.grid rows must have 2..9 tiles"];
  let sources = 0;
  let dests = 0;
  for (const [r, row] of p.grid.entries()) {
    if (!Array.isArray(row) || row.length !== cols) {
      errs.push(`grid row ${r} must have ${cols} tiles`);
      continue;
    }
    for (const [c, tok] of row.entries()) {
      const t = parseToken(tok);
      if (!t) {
        errs.push(`grid[${r}][${c}]: bad tile token ${JSON.stringify(tok)}`);
        continue;
      }
      if (t.kind === "S") sources++;
      if (t.kind === "D") dests++;
    }
  }
  if (sources !== 1) errs.push(`grid must contain exactly one source (found ${sources})`);
  if (dests < 1) errs.push("grid must contain at least one destination");
  for (const f of p.fixed ?? []) {
    if (!Array.isArray(f) || f.length !== 2 || !isInt(f[0]) || !isInt(f[1]) || f[0] < 0 || f[1] < 0 || f[0] >= p.grid.length || f[1] >= cols) errs.push(`bad fixed entry ${JSON.stringify(f)}`);
  }
  if (errs.length) return errs;
  for (const [i, m] of level.solution.entries()) {
    const mv = m as PipeMove;
    if (!mv || !isInt(mv.r) || !isInt(mv.c)) errs.push(`solution[${i}] must be {r:int, c:int}`);
  }
  if (!errs.length) {
    const b = parseBoard(p as PipePayload);
    if (isSolved(b, initialState(b))) errs.push("level starts solved");
  }
  return errs;
}

function replay(level: LevelEnvelope): ReplayResult {
  const b = parseBoard(level.payload as PipePayload);
  let s = initialState(b);
  for (const [i, raw] of level.solution.entries()) {
    if (isSolved(b, s)) return { ok: false, error: `move ${i}: solution continues after the level is solved` };
    const next = apply(b, s, raw as PipeMove);
    if (!next) return { ok: false, error: `move ${i}: illegal ${JSON.stringify(raw)}` };
    s = next;
  }
  return isSolved(b, s) ? { ok: true } : { ok: false, error: "final state is not solved" };
}

export const pipe: ModeHandlers = {
  mode: "pipe",
  validate,
  replay,
  solve: (level, budget) => solvePipe(parseBoard(level.payload as PipePayload), budget).solution?.moves ?? null,
};
