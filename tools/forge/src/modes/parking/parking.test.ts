import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES, validateLevel } from "../../validate.js";
import type { LevelEnvelope, LevelFile } from "../../schema.js";
import { apply, initialState, isSolved, legalMoves, slideRange, type ParkingPayload } from "./rules.js";
import { solveParking } from "./solver.js";
import { generateParking } from "./generator.js";

const board: ParkingPayload = {
  size: 6,
  vehicles: [
    { id: "T", r: 2, c: 0, len: 2, axis: "h", target: true },
    { id: "A", r: 0, c: 3, len: 3, axis: "v" },
    { id: "B", r: 4, c: 1, len: 2, axis: "h" },
  ],
  gates: [{ target: "T", edge: "right", index: 2 }],
};

test("parking: slides stop at walls and other vehicles", () => {
  const s = initialState(board);
  assert.deepEqual(slideRange(board, s, 0), [0, 1]); // T blocked by A at column 3
  assert.equal(apply(board, s, { id: "T", delta: 2 }), null);
  assert.equal(apply(board, s, { id: "T", delta: -1 }), null);
  assert.equal(apply(board, s, { id: "T", delta: 0 }), null);
  assert.equal(apply(board, s, { id: "Z", delta: 1 }), null);
  assert.deepEqual(apply(board, s, { id: "T", delta: 1 }), [1, 0, 1]);
  assert.deepEqual(apply(board, s, { id: "A", delta: 3 }), [0, 3, 1]);
  assert.equal(apply(board, s, { id: "A", delta: 4 }), null); // off the board
  assert.equal(apply(board, s, { id: "A", delta: -1 }), null); // already at the top wall
  // A vertical vehicle is stopped by a horizontal one in its column.
  const s2 = apply(board, s, { id: "B", delta: 2 })!; // B now covers columns 3..4 of row 4
  assert.deepEqual(slideRange(board, s2, 1), [0, 1], "A may only drop one row before B");
});

test("parking: a slide of any length is one move, solved when target touches its gate edge", () => {
  let s = initialState(board);
  assert.equal(isSolved(board, s), false);
  s = apply(board, s, { id: "A", delta: 3 })!; // A now rows 3..5 col 3
  assert.equal(isSolved(board, s), false);
  s = apply(board, s, { id: "T", delta: 4 })!;
  assert.equal(isSolved(board, s), true);
  assert.deepEqual(solveParking(board), [
    { id: "A", delta: 3 },
    { id: "T", delta: 4 },
  ]);
});

test("parking: legalMoves lists every slide in deterministic order", () => {
  const moves = legalMoves(board, initialState(board));
  assert.deepEqual(moves.slice(0, 2), [
    { id: "T", delta: 1 },
    { id: "A", delta: 1 },
  ]);
  assert.ok(moves.every((m) => apply(board, initialState(board), m) !== null));
});

test("parking: two targets must both reach their gates", () => {
  const two: ParkingPayload = {
    size: 6,
    vehicles: [
      { id: "T", r: 0, c: 0, len: 2, axis: "h", target: true },
      { id: "U", r: 2, c: 5, len: 2, axis: "v", target: true },
    ],
    gates: [
      { target: "T", edge: "right", index: 0 },
      { target: "U", edge: "bottom", index: 5 },
    ],
  };
  let s = initialState(two);
  s = apply(two, s, { id: "T", delta: 4 })!;
  assert.equal(isSolved(two, s), false);
  s = apply(two, s, { id: "U", delta: 2 })!;
  assert.equal(isSolved(two, s), true);
});

test("parking: validate rejects bad payloads", () => {
  const level = (payload: unknown): LevelEnvelope => ({ id: "x", mode: "parking", destination: "d3", order: 1, title: "t", difficulty: 1, twists: [], par: 1, solution: [{ id: "A", delta: 1 }], payload });
  const bad = { ...board, vehicles: [...board.vehicles, { id: "C", r: 2, c: 1, len: 2, axis: "h" }] };
  assert.ok(validateLevel(level(bad), "w").some((e) => e.includes("overlaps")));
  const noGate = { ...board, gates: [{ target: "A", edge: "right", index: 0 }] };
  assert.ok(validateLevel(level(noGate), "w").length > 0);
});

test("parking: generator is deterministic and hits its target length", () => {
  const spec = { targets: 1 as const, lo: 5, hi: 6, minVehicles: 6, maxVehicles: 8 };
  const a = generateParking(11, spec)!;
  const b = generateParking(11, spec)!;
  assert.deepEqual(a, b);
  assert.ok(a.optimal >= 5 && a.optimal <= 6);
  assert.equal(solveParking(a.payload)!.length, a.optimal);
});

test("parking: bundled d3 levels solve, rise in optimal length, and use both targets late", () => {
  const file = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Levels", "d3-parking.json"), "utf8")) as LevelFile;
  assert.equal(file.levels.length, 6);
  let prev = 0;
  for (const lvl of file.levels) {
    const p = lvl.payload as ParkingPayload;
    const opt = solveParking(p)!.length;
    assert.equal(lvl.par, opt, `${lvl.id} par is optimal`);
    assert.ok(opt >= prev, `${lvl.id} optimal ${opt} should not drop below ${prev}`);
    prev = opt;
    assert.equal(p.gates.length, lvl.order >= 5 ? 2 : 1, `${lvl.id} target count`);
  }
  assert.ok(prev >= 20, `final level optimal ${prev} should be 20+`);
  assert.ok(file.levels[0].solution.length <= 2);
  assert.equal(file.levels[0].tutorial, "parking.slide");
});
