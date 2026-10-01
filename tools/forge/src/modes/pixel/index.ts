import type { LevelEnvelope } from "../../schema.js";
import type { ModeHandlers, ReplayResult } from "../types.js";
import { solve } from "./solver.js";
import { colorCounts, crateTotals, replayMoves, type PixelMove, type PixelPayload, STONE } from "./rules.js";

function isInt(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x);
}

function validate(level: LevelEnvelope): string[] {
  const errs: string[] = [];
  const p = level.payload as Partial<PixelPayload> | null;
  if (!p || typeof p !== "object") return ["payload must be an object"];

  if (!Array.isArray(p.grid) || p.grid.length < 2 || !p.grid.every((r) => typeof r === "string")) {
    return ["payload.grid must be an array (>= 2) of strings"];
  }
  const w = p.grid[0]!.length;
  if (w < 2) errs.push("payload.grid rows must be at least 2 wide");
  for (const [i, row] of p.grid.entries()) {
    if (row.length !== w) errs.push(`payload.grid[${i}] has width ${row.length}, expected ${w}`);
    if (!/^[.#a-z]*$/.test(row)) errs.push(`payload.grid[${i}] contains characters other than . # and palette ids`);
  }
  if (!isInt(p.slots) || p.slots < 1 || p.slots > 8) errs.push("payload.slots must be an integer 1..8");
  if (!Array.isArray(p.lanes) || p.lanes.length < 2 || p.lanes.length > 4) {
    errs.push("payload.lanes must have 2 to 4 lanes");
    return errs;
  }
  for (const [li, lane] of p.lanes.entries()) {
    if (!Array.isArray(lane) || lane.length === 0) {
      errs.push(`payload.lanes[${li}] must be a non-empty array of crates`);
      continue;
    }
    for (const [ci, c] of lane.entries()) {
      if (!c || typeof c.color !== "string" || c.color.length !== 1 || !/[a-z]/.test(c.color)) errs.push(`payload.lanes[${li}][${ci}].color must be a palette id`);
      if (!c || !isInt(c.count) || c.count < 1) errs.push(`payload.lanes[${li}][${ci}].count must be an integer >= 1`);
      if (c && c.pattern !== undefined && typeof c.pattern !== "string") errs.push(`payload.lanes[${li}][${ci}].pattern must be a string`);
    }
  }
  if (errs.length) return errs;

  // Invariant: crate counts per color == pixel counts.
  const px = colorCounts(p.grid);
  const cr = crateTotals(p.lanes);
  for (const c of new Set([...Object.keys(px), ...Object.keys(cr)])) {
    if ((px[c] ?? 0) !== (cr[c] ?? 0)) errs.push(`color ${c}: grid has ${px[c] ?? 0} pixels but crates total ${cr[c] ?? 0}`);
  }

  for (const [i, m] of level.solution.entries()) {
    if (!m || typeof m !== "object" || !isInt((m as PixelMove).lane)) errs.push(`solution[${i}] must be {lane:int}`);
  }
  if (p.grid.some((r) => r.includes("#")) && !(level.twists ?? []).includes("stone")) {
    errs.push('levels with stones must list the "stone" twist');
  }
  return errs;
}

function replay(level: LevelEnvelope): ReplayResult {
  const p = level.payload as PixelPayload;
  const r = replayMoves(p, level.solution as PixelMove[]);
  if (!r.ok) return { ok: false, error: `move ${r.failedAt}: ${r.solvedAt >= 0 ? "move after the board was solved" : "illegal tap"}` };
  if (r.solvedAt < 0) return { ok: false, error: "ended with pixels left" };
  if (r.state.cells.includes(STONE)) return { ok: false, error: "solved but stones remain (a stone never crumbled)" };
  return { ok: true };
}

export const pixel: ModeHandlers = {
  mode: "pixel",
  validate,
  replay,
  solve(level, budget) {
    return solve(level.payload as PixelPayload, budget);
  },
};
