import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import { SCRAPBOOK_EXTRA_PALETTE, validateScrapbook, validateScrapbookArt, type ScrapbookArt } from "../src/scrapbook.js";
import { PIECES, buildPiece } from "../scripts/make-scrapbook.js";
import type { DestinationsFile, PaletteFile } from "../src/schema.js";

function sharedIds(): Set<string> {
  const pal = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Art", "palette.json"), "utf8")) as PaletteFile;
  return new Set(pal.colors.map((c) => c.id));
}

test("every restoration stage has well-formed scrapbook art", () => {
  const dest = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Destinations.json"), "utf8")) as DestinationsFile;
  const ids = dest.destinations.flatMap((d) => d.restorationStages.map((s) => s.scrapbookArtId));
  assert.ok(ids.length >= 15);
  assert.deepEqual(validateScrapbook(DEFAULT_RESOURCES, ids, sharedIds()), []);
});

test("scrapbook generator is in sync with the committed JSON", () => {
  for (const p of PIECES) {
    const built = buildPiece(p);
    const onDisk = JSON.parse(readFileSync(join(DEFAULT_RESOURCES, "Art", "scrapbook", `${p.id}.json`), "utf8"));
    assert.deepEqual(onDisk, built, `${p.id} differs: run npx tsx scripts/make-scrapbook.ts`);
  }
});

test("extra palette keys never collide with the shared palette", () => {
  const shared = sharedIds();
  for (const k of Object.keys(SCRAPBOOK_EXTRA_PALETTE)) assert.ok(!shared.has(k), `extra key ${k} collides`);
});

test("scrapbook validator catches bad art", () => {
  const good: ScrapbookArt = { id: "x", title: "T", caption: "C", width: 2, height: 2, rows: ["ab", ".."], palette: { b: "#112233" } };
  assert.deepEqual(validateScrapbookArt(good, new Set(["a"]), "x"), []);
  assert.ok(validateScrapbookArt({ ...good, rows: ["ab"] }, new Set(["a"]), "x").length > 0);
  assert.ok(validateScrapbookArt({ ...good, rows: ["az", ".."] }, new Set(["a"]), "x").length > 0);
  assert.ok(validateScrapbookArt({ ...good, rows: ["a", ".."] }, new Set(["a"]), "x").length > 0);
});
