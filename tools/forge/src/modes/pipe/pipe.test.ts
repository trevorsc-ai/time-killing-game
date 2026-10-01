import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../../validate.js";
import type { LevelFile, PoolFile } from "../../schema.js";
import { apply, flow, initialState, isSolved, maskOf, parseBoard, rotateMask, type PipePayload } from "./rules.js";
import { solvePipe } from "./solver.js";
import { generatePipe } from "./generator.js";

test("pipe: masks rotate clockwise", () => {
  assert.equal(rotateMask(1), 2); // N -> E
  assert.equal(rotateMask(8), 1); // W -> N
  assert.equal(maskOf("l", 1), 6); // N|E -> E|S
  assert.equal(maskOf("i", 1), 10);
  assert.equal(maskOf("i", 2), 5);
  assert.equal(maskOf("t", 0), 14);
  assert.equal(maskOf("t", 1), 13); // S|W|N
  assert.equal(maskOf("x", 3), 15);
});

const payload: PipePayload = {
  // S at (0,0) opens east; a straight in the middle; D at (0,2) opens north until turned.
  grid: [
    ["S1", "i0", "D0"],
    ["l0", ".0", "t0"],
  ],
  fixed: [[0, 0]],
};

test("pipe: taps rotate one step clockwise; empty and fixed tiles are illegal", () => {
  const b = parseBoard(payload);
  const s = initialState(b);
  assert.equal(apply(b, s, { r: 1, c: 1 }), null); // empty
  assert.equal(apply(b, s, { r: 0, c: 0 }), null); // fixed source
  assert.equal(apply(b, s, { r: 5, c: 0 }), null); // out of range
  const t = apply(b, s, { r: 0, c: 1 })!;
  assert.equal(t[1], 1);
  assert.equal(s[1], 0, "apply does not mutate");
  assert.equal(apply(b, [0, 3, 0, 0, 0, 0], { r: 0, c: 1 })![1], 0, "rotation wraps 3 -> 0");
});

test("pipe: connectivity needs matching openings on both sides; dangling ends are fine", () => {
  const b = parseBoard(payload);
  let s = initialState(b);
  // i0 = N|S does not open west toward the source.
  assert.equal(flow(b, s).reached[1], false);
  s = apply(b, s, { r: 0, c: 1 })!; // i1 = E|W: connected to S, leaks east
  assert.equal(flow(b, s).reached[1], true);
  assert.equal(isSolved(b, s), false, "D still opens north");
  for (let k = 0; k < 3; k++) s = apply(b, s, { r: 0, c: 2 })!; // D: N -> E -> S -> W
  assert.equal(isSolved(b, s), true);
  // The unused elbow and tee below are dangling/unreached and irrelevant.
  assert.equal(flow(b, s).reached[3], false);
});

test("pipe: a tee splits the flow to two destinations", () => {
  const b = parseBoard({
    grid: [
      ["D1", "t2", "D3"],
      [".0", "S0", ".0"],
    ],
    fixed: [
      [0, 0],
      [0, 2],
      [1, 1],
    ],
  });
  assert.equal(maskOf("t", 2), 11); // N|E|W: no southern opening toward the source
  let s = initialState(b);
  assert.equal(isSolved(b, s), false);
  s = apply(b, s, { r: 0, c: 1 })!;
  assert.equal(maskOf("t", 3), 7); // N|E|S reaches the right destination only? W missing -> left D dark
  assert.equal(isSolved(b, s), false);
  assert.equal(flow(b, s).reached[2], true);
  assert.equal(flow(b, s).reached[0], false);
  s = apply(b, s, { r: 0, c: 1 })!; // E|S|W
  assert.equal(isSolved(b, s), true);
});

test("pipe: solver finds the fewest taps", () => {
  const b = parseBoard({
    grid: [
      ["S1", "i0", "l2"],
      [".0", ".0", "D0"],
    ],
    fixed: [
      [0, 0],
      [1, 2],
    ],
  });
  const res = solvePipe(b);
  assert.ok(res.solution);
  assert.ok(res.exhaustive);
  assert.deepEqual(res.solution!.moves, [{ r: 0, c: 1 }]);
  assert.equal(res.solution!.cost, 1);
});

test("pipe: generator output is deterministic, starts unsolved, and the stored solution solves it", () => {
  const spec = { rows: 5, cols: 5, dests: 2, minPath: 7, maxPath: 12, minTaps: 8 };
  const a = generatePipe(5, spec)!;
  assert.deepEqual(a, generatePipe(5, spec));
  const b = parseBoard(a.payload);
  assert.equal(isSolved(b, initialState(b)), false);
  let s = initialState(b);
  for (const m of a.solution) s = apply(b, s, m)!;
  assert.equal(isSolved(b, s), true);
  assert.ok(a.par <= a.plantedTaps);
  assert.equal(a.payload.grid.flat().filter((t) => t[0] === "t").length >= 1, true, "two destinations need a tee");
});

test("pipe: bundled d4 levels ramp from 3x3 to 6x6, introduce the tee late, never start solved", () => {
  const file = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Levels", "d4-pipe.json"), "utf8")) as LevelFile;
  assert.equal(file.levels.length, 6);
  let prevPar = 0;
  file.levels.forEach((lvl, i) => {
    const p = lvl.payload as PipePayload;
    const b = parseBoard(p);
    assert.equal(isSolved(b, initialState(b)), false, lvl.id);
    assert.ok(lvl.par >= prevPar, `${lvl.id} par should not drop`);
    prevPar = lvl.par;
    const tees = p.grid.flat().filter((t) => t[0] === "t").length;
    if (i < 3) assert.equal(b.destIndices.length, 1, `${lvl.id} single destination`);
    else assert.ok(b.destIndices.length >= 2 && tees >= 1, `${lvl.id} multiple endpoints and a tee`);
  });
  assert.equal(file.levels[0].payload && (file.levels[0].payload as PipePayload).grid.length, 3);
  assert.equal((file.levels[5].payload as PipePayload).grid.length, 6);
  assert.equal(file.levels[0].tutorial, "pipe.rotate");
  assert.equal(file.levels[3].tutorial, "twist.tee");
});

test("pipe: relax pool has ~150 entries rising from 3x3 to 7x7, none starting solved", () => {
  const pool = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Pools", "relax-pipe.json"), "utf8")) as PoolFile;
  assert.ok(pool.entries.length >= 140);
  let prevSize = 0;
  let prevDiff = 0;
  for (const e of pool.entries) {
    const p = e.payload as PipePayload;
    const b = parseBoard(p);
    assert.equal(isSolved(b, initialState(b)), false, e.id);
    assert.ok(p.grid.length >= prevSize, `${e.id} size should not shrink`);
    assert.ok(e.difficulty >= prevDiff, `${e.id} difficulty should not drop`);
    prevSize = p.grid.length;
    prevDiff = e.difficulty;
  }
  assert.equal((pool.entries[0].payload as PipePayload).grid.length, 3);
  assert.equal(prevSize, 7);
});
