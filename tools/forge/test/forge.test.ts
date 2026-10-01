import { test } from "node:test";
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import { createRng, fnv1a32 } from "../src/util/prng.js";
import { encodePng, renderCharGrid } from "../src/util/png.js";
import { DEFAULT_RESOURCES, validateAll, validateLevel } from "../src/validate.js";
import type { LevelEnvelope } from "../src/schema.js";

test("mulberry32 is deterministic and in range", () => {
  const a = createRng(42);
  const b = createRng(42);
  const xs = Array.from({ length: 20 }, () => a.next());
  const ys = Array.from({ length: 20 }, () => b.next());
  assert.deepEqual(xs, ys);
  assert.ok(xs.every((x) => x >= 0 && x < 1));
  assert.notDeepEqual(xs, Array.from({ length: 20 }, () => createRng(43).next()));
  assert.deepEqual(createRng(7).shuffle([1, 2, 3, 4, 5]), createRng(7).shuffle([1, 2, 3, 4, 5]));
});

test("fnv1a32 known vectors", () => {
  assert.equal(fnv1a32(""), 0x811c9dc5);
  assert.equal(fnv1a32("a"), 0xe40c292c);
  assert.equal(fnv1a32("foobar"), 0xbf9cf968);
});

test("png writer produces a valid PNG", () => {
  const png = encodePng(2, 2, new Uint8Array(16).fill(255));
  assert.equal(png.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  assert.equal(png.subarray(12, 16).toString("ascii"), "IHDR");
  const idatStart = png.indexOf("IDAT") + 4;
  const raw = inflateSync(png.subarray(idatStart, png.length - 12));
  assert.equal(raw.length, 2 * (1 + 8));
  assert.ok(renderCharGrid(["ab", "b."], { a: "#ff0000", b: "#00ff00" }, 4).length > 50);
});

test("bundled resources validate", () => {
  const report = validateAll(DEFAULT_RESOURCES);
  assert.deepEqual(report.errors, []);
  assert.ok(report.levelCount >= 1);
});

test("envelope validation catches problems", () => {
  const good: LevelEnvelope = {
    id: "demo-demo-01",
    mode: "demo",
    destination: "demo",
    order: 1,
    title: "t",
    difficulty: 1,
    twists: [],
    par: 1,
    solution: [{ delta: 2 }],
    payload: { start: 0, target: 2, deltas: [1, 2] },
  };
  assert.deepEqual(validateLevel(good, "x"), []);
  assert.ok(validateLevel({ ...good, difficulty: 11 }, "x").length > 0);
  assert.ok(validateLevel({ ...good, mode: "nope" }, "x").length > 0);
  assert.ok(validateLevel({ ...good, solution: [{ delta: 1 }] }, "x").length > 0);
  assert.ok(validateLevel({ ...good, par: 5 }, "x").length > 0);
});
