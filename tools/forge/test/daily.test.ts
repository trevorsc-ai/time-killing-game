import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import type { PoolFile } from "../src/schema.js";
import { MODES } from "../src/modes/index.js";

test("daily pool: 730 verified entries rotating across all five modes", () => {
  const pool = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Pools", "daily.json"), "utf8")) as PoolFile;
  assert.equal(pool.pool, "daily");
  assert.equal(pool.entries.length, 730);
  const week = ["liquid", "pixel", "pipe", "bolt", "parking", "pixel", "liquid"];
  const sigs = new Set<string>();
  pool.entries.forEach((e, i) => {
    assert.equal(e.id, `daily-${String(i + 1).padStart(3, "0")}`);
    assert.equal(e.destination, "daily");
    assert.equal(e.order, i + 1);
    assert.equal(e.mode, week[i % 7]);
    assert.ok(e.difficulty >= 3 && e.difficulty <= 6, `${e.id} difficulty`);
    assert.ok(e.par <= e.solution.length);
    const r = MODES[e.mode]!.replay(e);
    assert.ok(r.ok, `${e.id}: ${r.error}`);
    sigs.add(e.mode + JSON.stringify(e.payload));
  });
  assert.equal(sigs.size, 730, "payloads are unique");
  // Parking stays short so generation and play stay quick.
  for (const e of pool.entries) if (e.mode === "parking") assert.ok(e.par <= 16, `${e.id} par ${e.par}`);
});
