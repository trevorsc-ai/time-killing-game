import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES, validateLevel } from "../src/validate.js";
import type { LevelEnvelope, LevelFile, PoolFile } from "../src/schema.js";
import { SortRules, fingerprint, replaySort, type SortPayload } from "../src/modes/sortcore.js";
import { isDeadlockFree, solveFrom } from "../src/solvers/sortSolver.js";
import { deal, type DealSpec } from "../src/generators/sortGen.js";
import { createRng } from "../src/util/prng.js";

function level(payload: SortPayload, solution: unknown[], twists: string[] = [], mode = "liquid"): LevelEnvelope {
  return { id: "d1-liquid-01", mode, destination: "d1", order: 1, title: "t", difficulty: 1, twists, par: Math.max(1, solution.length), solution, payload };
}
const mv = (from: number, to: number) => ({ from, to });
const st = (p: SortPayload) => SortRules.initialState(p);

test("pour moves the top run limited by free space", () => {
  const p: SortPayload = { capacity: 4, tubes: [["r", "b", "b"], ["r", "b"], []] };
  const rules = new SortRules(p);
  // tube0 top run is 2 blues; tube1 has 2 free: both move.
  const a = rules.apply(mv(0, 1), st(p));
  assert.ok(a);
  assert.equal(fingerprint(a), "r|rbbb|#,,");
  // tube1 -> tube0 : top b matches? tube0 top b. tube0 has 3 layers (1 free): only 1 b moves
  const b = rules.apply(mv(1, 0), st(p));
  assert.ok(b);
  assert.equal(fingerprint(b), "rbbb|r|#,,");
  // illegal: non-matching top, from empty, same tube
  assert.equal(rules.apply(mv(2, 0), st(p)), null);
  assert.equal(rules.apply(mv(0, 0), st(p)), null);
  const q: SortPayload = { capacity: 4, tubes: [["r", "b"], ["b", "r"], []] };
  assert.equal(new SortRules(q).apply(mv(0, 1), st(q)), null);
  assert.ok(new SortRules(q).apply(mv(0, 2), st(q)));
});

test("pointless pours into empty tubes are legal; solved needs one tube per color", () => {
  const p: SortPayload = { capacity: 2, tubes: [["r", "r"], ["b", "b"], []] };
  const rules = new SortRules(p);
  assert.ok(rules.isSolved(st(p)));
  assert.ok(rules.apply(mv(0, 2), st(p)));
  const split: SortPayload = { capacity: 2, tubes: [["r"], ["r"], ["b", "b"]] };
  assert.equal(new SortRules(split).isSolved(st(split)), false);
});

test("hidden layers are not part of a run and reveal when they become the top", () => {
  const p: SortPayload = { capacity: 4, tubes: [["r", "r", "r"], ["b", "b"], []], hidden: [[0, 0], [0, 1]] };
  const rules = new SortRules(p);
  let s = st(p);
  assert.equal(fingerprint(s), "r?r?r|bb|#,,");
  s = rules.apply(mv(0, 2), s) as typeof s; // moves only the revealed top r
  assert.equal(fingerprint(s), "r?r|bb|r#,,");
  s = rules.apply(mv(0, 2), s) as typeof s; // new top was revealed, matches
  assert.equal(fingerprint(s), "r|bb|rr#,,"); // the last hidden layer became the top and was revealed
  s = rules.apply(mv(0, 2), s) as typeof s;
  assert.equal(fingerprint(s), "|bb|rrr#,,");
});

test("locked tubes cannot be source or target until their color is completed", () => {
  const p: SortPayload = { capacity: 2, tubes: [["b", "r"], ["r", "b"], [], ["g", "g"]], locks: [{ tube: 3, color: "r" }] };
  const rules = new SortRules(p);
  let s = st(p);
  assert.equal(s.locks[3], "r");
  assert.equal(rules.apply(mv(3, 2), s), null);
  assert.equal(rules.apply(mv(0, 3), s), null);
  assert.equal(rules.canSource(s, 3), false);
  s = rules.apply(mv(0, 1 + 1), s) as typeof s; // b -> empty tube
  s = rules.apply(mv(1, 0), s) as typeof s; // r onto the lone... top of tube0 is now r
  assert.equal(s.locks[3], "r");
  s = rules.apply(mv(1, 2), s) as typeof s;
  assert.equal(fingerprint(s), "bb||rr|gg#,,,");
  assert.equal(s.locks[3], "", "red is complete, so the lock opened");
  assert.equal(rules.canSource(s, 3), true);
});

test("bolt capacities cap a bolt; rusty nuts block moves until their color is completed", () => {
  const p: SortPayload = {
    capacity: 3,
    capacities: [3, 3, 2, 3],
    tubes: [["b", "g", "g"], ["g", "b"], [], ["y"]],
    rusty: [{ bolt: 1, index: 0, color: "b" }],
  };
  const rules = new SortRules(p);
  let s = st(p);
  assert.equal(fingerprint(s), "bgg|g~bb||y#,,,");
  assert.equal(rules.canSource(s, 1), true); // top nut b is not rusty
  s = rules.apply(mv(0, 2), s) as typeof s; // both g move into the capped bolt (2 high)
  assert.equal(fingerprint(s), "b|g~bb|gg|y#,,,");
  assert.equal(rules.apply(mv(3, 2), s), null); // y does not match g
  assert.equal(rules.apply(mv(1, 2), s), null); // b does not match g
  s = rules.apply(mv(1, 0), s) as typeof s; // b joins b: blue is now completed, rust clears
  assert.equal(fingerprint(s), "bb|g|gg|y#,,,");
  assert.equal(rules.canSource(s, 1), true);
  // capacity: bolt 2 is full now, so g from bolt 1 cannot go there
  assert.equal(rules.apply(mv(1, 2), s), null);
});

test("rust blocks a rusty top nut until the tagged color is completed", () => {
  const p: SortPayload = { capacity: 3, tubes: [["y", "g"], ["b", "y"], ["g"], []], rusty: [{ bolt: 0, index: 1, color: "y" }] };
  const rules = new SortRules(p);
  let s = st(p);
  assert.equal(fingerprint(s), "yg~y|by|g|#,,,");
  assert.equal(rules.canSource(s, 0), false);
  assert.deepEqual(rules.legalMoves(s).filter((m) => m.from === 0), []);
  // a matching nut may still be poured ONTO a rusty top
  assert.ok(rules.apply(mv(2, 0), s));
  s = rules.apply(mv(1, 3), s) as typeof s; // y -> empty
  assert.equal(fingerprint(s), "yg~y|b|g|y#,,,");
  s = rules.apply(mv(2, 0), s) as typeof s;
  assert.equal(fingerprint(s), "yg~yg|b||y#,,,");
});

test("rust clears once the tagged color is completed", () => {
  const p: SortPayload = { capacity: 2, tubes: [["g", "y"], ["y", "b"], ["g", "b"], []], rusty: [{ bolt: 0, index: 0, color: "b" }] };
  const rules = new SortRules(p);
  let s = st(p);
  assert.equal(s.tubes[0][0].r, "b");
  s = rules.apply(mv(1, 3), s) as typeof s; // b -> empty
  assert.equal(s.tubes[0][0].r, "b");
  s = rules.apply(mv(2, 3), s) as typeof s; // second b joins: blue complete
  assert.equal(s.tubes[0][0].r, "");
});

test("replay rejects moves after solved and illegal moves", () => {
  const p: SortPayload = { capacity: 2, tubes: [["r", "b"], ["b", "r"], []] };
  assert.equal(replaySort(level(p, [mv(0, 1)])).ok, false); // illegal
  assert.equal(replaySort(level(p, [mv(0, 2)])).ok, false); // legal but unsolved
  const solved = solveFrom(new SortRules(p), st(p)).solution as { from: number; to: number }[];
  assert.equal(replaySort(level(p, solved)).ok, true);
  assert.equal(replaySort(level(p, [...solved, mv(0, 2)])).ok, false);
});

test("deal() is deterministic for a seed", () => {
  const spec: DealSpec = { mode: "liquid", colors: ["r", "g", "b", "y"], count: 4, capacity: 4, empties: 2 };
  const a = deal(spec, createRng(5));
  const b = deal(spec, createRng(5));
  assert.deepEqual(a, b);
  assert.notDeepEqual(a, deal(spec, createRng(6)));
});

function load(file: string): LevelFile {
  return JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Levels", file), "utf8")) as LevelFile;
}

test("bundled liquid levels: curve, twists, tutorials, early levels cannot dead-end", () => {
  const f = load("d1-liquid.json");
  assert.equal(f.levels.length, 10);
  assert.deepEqual(f.levels.map((l) => l.order), [1, 3, 5, 7, 9, 11, 13, 15, 18, 21]);
  assert.equal(f.levels[0].tutorial, "liquid.pour");
  const diffs = f.levels.map((l) => l.difficulty);
  assert.deepEqual(diffs, diffs.slice().sort((a, b) => a - b));
  const firstTwist = (t: string) => f.levels.findIndex((l) => l.twists.includes(t));
  assert.equal(firstTwist("hidden"), 6, "hidden is introduced on the 7th liquid level");
  assert.equal(firstTwist("lock"), 8, "lock is introduced on the 9th liquid level");
  assert.ok(f.levels.slice(0, 6).every((l) => l.twists.length === 0));
  const p1 = f.levels[0].payload as SortPayload;
  assert.equal(p1.tubes.length, 5);
  assert.equal(p1.tubes.filter((t) => t.length === 0).length, 2);
  assert.equal(new Set(p1.tubes.flat()).size, 3);
  for (const l of f.levels.slice(0, 3)) {
    const p = l.payload as SortPayload;
    const rules = new SortRules(p);
    assert.equal(isDeadlockFree(rules, SortRules.initialState(p)), true, `${l.id} must never trap the player`);
    assert.ok(p.tubes.filter((t) => t.length === 0).length >= 2);
  }
  const colors = f.levels.map((l) => new Set((l.payload as SortPayload).tubes.flat()).size);
  assert.equal(colors[9], 7);
  assert.ok(colors.every((c, i) => i === 0 || c >= colors[i - 1] - 0));
});

test("bundled bolt levels", () => {
  const d1 = load("d1-bolt.json");
  const d2 = load("d2-bolt.json");
  assert.deepEqual(d1.levels.map((l) => l.order), [16, 19, 22, 24, 25]);
  assert.deepEqual(d2.levels.map((l) => l.order), [1, 2, 3, 4, 5]);
  assert.equal(d1.levels[0].tutorial, "bolt.move");
  assert.ok(d1.levels.every((l) => l.twists.length === 0));
  assert.deepEqual(d2.levels.map((l) => l.twists.join("+")), ["", "capped", "capped", "rusty", "capped+rusty"]);
  const all = [...d1.levels, ...d2.levels].map((l) => l.difficulty);
  assert.deepEqual(all, all.slice().sort((a, b) => a - b));
  const colorCounts = d1.levels.map((l) => new Set((l.payload as SortPayload).tubes.flat()).size);
  assert.equal(colorCounts[0], 3);
  assert.equal(colorCounts[4], 5);
});

test("relax-liquid pool: size, color cycle, gentle rise", () => {
  const path = join(DEFAULT_RESOURCES, "Pools", "relax-liquid.json");
  assert.ok(existsSync(path));
  const pool = JSON.parse(readFileSync(path, "utf8")) as PoolFile;
  assert.equal(pool.entries.length, 150);
  const colors = pool.entries.map((e) => new Set((e.payload as SortPayload).tubes.flat()).size);
  assert.deepEqual(new Set(colors), new Set([3, 4, 5, 6, 7]));
  assert.deepEqual(colors.slice(0, 10), [3, 4, 5, 6, 7, 3, 4, 5, 6, 7]);
  const d = pool.entries.map((e) => e.difficulty);
  assert.deepEqual(d, d.slice().sort((a, b) => a - b));
  const avg = (xs: number[]) => xs.reduce((a, b) => a + b, 0) / xs.length;
  const pars = pool.entries.map((e) => e.par);
  assert.ok(avg(pars.slice(120)) > avg(pars.slice(0, 30)) + 3);
  for (const e of pool.entries) assert.deepEqual(validateLevel(e, e.id), []);
});
