import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES, validateLevel } from "../../validate.js";
import type { LevelEnvelope } from "../../schema.js";
import { SCENES } from "./art/scenes.js";
import { buildGolden } from "./golden.js";
import { pixel } from "./index.js";
import { analyze } from "./solver.js";
import {
  apply,
  applyDetailed,
  colorCounts,
  gridRows,
  initialState,
  isExposed,
  isSolved,
  isStuck,
  legalMoves,
  slotStrings,
  type PixelPayload,
} from "./rules.js";

function payload(grid: string[], slots: number, lanes: { color: string; count: number }[][]): PixelPayload {
  return { grid, slots, lanes };
}

function level(p: PixelPayload, solution: number[], twists: string[] = []): LevelEnvelope {
  return {
    id: "d1-pixel-02",
    mode: "pixel",
    destination: "d1",
    order: 2,
    title: "t",
    difficulty: 1,
    twists,
    par: Math.max(1, solution.length),
    solution: solution.map((lane) => ({ lane })),
    payload: p,
  };
}

test("exposure: edge, transparent neighbors, cleared cells", () => {
  const p = payload(["rrr", "rgr", "rrr"], 2, [[{ color: "g", count: 1 }], [{ color: "r", count: 8 }]]);
  const s = initialState(p);
  assert.equal(isExposed(s, 0), true); // corner
  assert.equal(isExposed(s, 4), false); // centre, buried
  const p2 = payload(["rrrr", "r.gr", "rrrr"], 2, [[{ color: "g", count: 1 }], [{ color: "r", count: 10 }]]);
  const s2 = initialState(p2);
  assert.equal(isExposed(s2, 6), true); // g touches the "." cell
});

test("chaining walks inward through same-color neighbors in BFS order", () => {
  // Row of 5 r; only the left end touches the edge row... use a 3x5 block of r with a hole of g in the middle.
  const p = payload(["rrrrr", "rrgrr", "rrrrr"], 3, [[{ color: "r", count: 3 }], [{ color: "r", count: 11 }], [{ color: "g", count: 1 }]]);
  let s = initialState(p);
  // First crate: 3 of r. Exposed r in row-major: whole border; first three row-major are cells 0,1,2.
  const t = applyDetailed(p, s, { lane: 0 })!;
  assert.deepEqual(t.events[0]!.cells, [0, 1, 2]);
  assert.equal(t.events[0]!.departed, true);
  s = t.state;
  assert.deepEqual(gridRows(s), ["...rr", "rrgrr", "rrrrr"]);
});

test("a crate waits for buried targets and resumes automatically", () => {
  const p = payload(["rrr", "rgr", "rrr"], 2, [[{ color: "g", count: 1 }], [{ color: "r", count: 8 }]]);
  let s = initialState(p);
  s = apply(p, s, { lane: 0 })!; // g crate: g is buried, waits
  assert.deepEqual(slotStrings(s), ["g:1", ""]);
  s = apply(p, s, { lane: 1 })!; // r crate packs all 8 -> exposes g -> g crate resumes and departs
  assert.deepEqual(slotStrings(s), ["", ""]);
  assert.equal(isSolved(s), true);
});

test("illegal moves and stuck detection", () => {
  const p = payload(["rrr", "rgr", "rrr"], 1, [[{ color: "g", count: 1 }], [{ color: "r", count: 8 }]]);
  let s = initialState(p);
  s = apply(p, s, { lane: 0 })!; // g waits in the only slot
  assert.equal(legalMoves(p, s).length, 0);
  assert.equal(isStuck(p, s), true);
  assert.equal(apply(p, s, { lane: 1 }), null);
  assert.equal(apply(p, initialState(p), { lane: 5 }), null);
});

test("stones crumble at the end of the visit that packed a neighbor, and count as cleared afterwards", () => {
  const p = payload(["rrrr", "r#gr", "rrrr"], 3, [[{ color: "r", count: 1 }], [{ color: "g", count: 1 }], [{ color: "r", count: 9 }]]);
  let s = initialState(p);
  // g touches only the stone and r pixels: buried. r (1 crate) packs cell 0 -> stone is not adjacent to cell 0.
  s = apply(p, s, { lane: 0 })!;
  assert.equal(s.cells[5], 35); // stone still there
  s = apply(p, s, { lane: 1 })!; // g waits
  assert.deepEqual(slotStrings(s), ["g:1", "", ""]);
  s = apply(p, s, { lane: 2 })!; // big r crate: packs, stone (adjacent to packed r at cell 4/..) crumbles, g resumes
  assert.equal(isSolved(s), true);
  assert.equal(s.cells.includes(35), false);
});

test("hand-authored scenes are clean char grids", () => {
  assert.equal(SCENES.length, 10);
  const palette = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Art/palette.json"), "utf8")) as { colors: { id: string }[] };
  const ids = new Set(palette.colors.map((c) => c.id));
  for (const sc of SCENES) {
    const w = sc.rows[0]!.length;
    assert.ok(sc.rows.every((r) => r.length === w), `${sc.id}: ragged`);
    for (const r of sc.rows) for (const ch of r) assert.ok(ch === "." || ch === "#" || ids.has(ch), `${sc.id}: bad char ${ch}`);
    assert.ok(Object.keys(colorCounts(sc.rows)).length >= 3);
  }
});

function readLevels(file: string, key: string): LevelEnvelope[] {
  return (JSON.parse(readFileSync(join(DEFAULT_RESOURCES, file), "utf8")) as Record<string, LevelEnvelope[]>)[key]!;
}

test("d1 pixel levels: 10 levels, curve, slots, twists", () => {
  const levels = readLevels("Levels/d1-pixel.json", "levels");
  assert.deepEqual(levels.map((l) => l.order), [2, 4, 6, 8, 10, 12, 14, 17, 20, 23]);
  assert.equal(levels[0]!.tutorial, "pixel.tap");
  const colors = levels.map((l) => Object.keys(colorCounts((l.payload as PixelPayload).grid)).length);
  assert.equal(colors[0], 3);
  assert.equal((levels[0]!.payload as PixelPayload).slots, 5);
  assert.ok(colors[9]! >= 7);
  assert.equal((levels[9]!.payload as PixelPayload).slots, 3);
  // stones first appear at the 7th level
  const stoneAt = levels.findIndex((l) => (l.payload as PixelPayload).grid.some((r) => r.includes("#")));
  assert.equal(stoneAt, 6);
  assert.deepEqual(levels[6]!.twists, ["stone"]);
  for (let i = 1; i < levels.length; i++) assert.ok(levels[i]!.difficulty >= levels[i - 1]!.difficulty);
  for (const l of levels) assert.deepEqual(validateLevel(l, l.id), []);
});

test("d1 pixel difficulty: L1-3 cannot jam, later levels can, late levels jam often", () => {
  const levels = readLevels("Levels/d1-pixel.json", "levels");
  const stats = levels.map((l) => analyze(l.payload as PixelPayload, 100_000));
  for (const [i, a] of stats.entries()) {
    assert.ok(a.complete && a.solvable, `level ${i + 1} must be solvable`);
    assert.equal(a.solution.length, levels[i]!.par);
  }
  for (let i = 0; i < 3; i++) assert.equal(stats[i]!.doomed, 0, `level ${i + 1} must be impossible to get stuck`);
  for (let i = 3; i < 10; i++) assert.ok(stats[i]!.doomed > 0, `level ${i + 1} should have traps`);
  assert.ok(stats[9]!.pStuck > stats[3]!.pStuck, "last level harder than the 4th");
});

test("relax-pixel pool: 150 verified entries with gently rising difficulty", () => {
  const entries = readLevels("Pools/relax-pixel.json", "entries");
  assert.equal(entries.length, 150);
  for (let i = 1; i < entries.length; i++) assert.ok(entries[i]!.difficulty >= entries[i - 1]!.difficulty);
  assert.ok(entries[0]!.difficulty <= 2 && entries[149]!.difficulty <= 6);
  for (const e of entries) {
    const r = pixel.replay(e);
    assert.ok(r.ok, `${e.id}: ${r.error}`);
    assert.deepEqual(pixel.validate(e), []);
  }
  // easy tier cannot jam
  for (const e of entries.slice(0, 60)) assert.equal(analyze(e.payload as PixelPayload, 100_000).doomed, 0, e.id);
});

test("golden fixture file is up to date with the forge rules", () => {
  const levels = readLevels("Levels/d1-pixel.json", "levels");
  const fresh = buildGolden(levels);
  const file = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "../../PuzzleGetawayTests/Fixtures/pixel-golden.json"), "utf8")) as typeof fresh;
  assert.deepEqual(JSON.parse(JSON.stringify(fresh)), file);
  assert.ok(file.cases.length >= 20);
  assert.ok(file.cases.some((c) => c.steps.some((s) => s.stuck)), "a jam trace exists");
  assert.ok(file.cases.some((c) => c.steps.some((s) => s.events.some((e) => e.crumbled.length > 0))), "a stone-crumble trace exists");
});
