/**
 * `npm run build:pixel` — regenerates every Pixel Picnic content file from the hand-authored scenes:
 *   Resources/Levels/d1-pixel.json, Resources/Pools/relax-pixel.json,
 *   PuzzleGetawayTests/Fixtures/pixel-golden.json (Swift parity fixtures).
 * All randomness is seeded, so rerunning produces identical files.
 */
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { LevelEnvelope } from "../../schema.js";
import { SCENE_BY_ID } from "./art/scenes.js";
import { generate, type Candidate } from "./generate.js";
import { D1_PLAN } from "./levels.js";
import { buildPool } from "./pool.js";
import { buildGolden } from "./golden.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../../../..");
const RES = join(REPO, "PuzzleGetaway/Resources");

/** One level/entry per line keeps the files small and diffs readable. */
function linesJson(head: Record<string, string>, key: string, items: unknown[]): string {
  const h = Object.entries(head).map(([k, v]) => `${JSON.stringify(k)}:${JSON.stringify(v)}`).join(",");
  return `{${h},${JSON.stringify(key)}:[\n${items.map((i) => JSON.stringify(i)).join(",\n")}\n]}\n`;
}

function describe(c: Candidate): string {
  const a = c.analysis;
  return `crates=${c.payload.lanes.reduce((n, l) => n + l.length, 0)} states=${a.states} doomed=${a.doomedFraction.toFixed(2)} pStuck=${a.pStuck.toFixed(2)} traps=${a.firstTraps}/${a.firstMoves} lines=${a.winningLines} penalty=${c.penalty.toFixed(2)}`;
}

export function buildD1(): LevelEnvelope[] {
  const out: LevelEnvelope[] = [];
  for (const plan of D1_PLAN) {
    const scene = SCENE_BY_ID[plan.scene];
    if (!scene) throw new Error(`unknown scene ${plan.scene}`);
    const cand = generate({
      grid: scene.rows,
      slots: plan.slots,
      lanes: plan.lanes,
      maxSplit: plan.maxSplit,
      minCrate: plan.minCrate,
      target: plan.target,
      seed: plan.seed,
      tries: plan.tries,
      budget: 60_000,
    });
    if (!cand || cand.penalty > 0) {
      console.error(`WARNING: ${plan.scene} did not meet its target: ${cand ? describe(cand) : "no candidate"}`);
    }
    if (!cand) throw new Error(`no candidate for ${plan.scene}`);
    console.log(`${String(plan.order).padStart(2)} ${plan.scene.padEnd(16)} ${describe(cand)}`);
    out.push({
      id: `d1-pixel-${String(plan.order).padStart(2, "0")}`,
      mode: "pixel",
      destination: "d1",
      order: plan.order,
      title: plan.title,
      difficulty: plan.difficulty,
      ...(plan.tutorial ? { tutorial: plan.tutorial } : {}),
      twists: plan.twists,
      par: cand.analysis.solution.length,
      solution: cand.analysis.solution,
      payload: cand.payload,
    });
  }
  return out;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const only = process.argv[2] ?? "all";
  if (only === "all" || only === "d1") {
    const levels = buildD1();
    writeFileSync(join(RES, "Levels/d1-pixel.json"), linesJson({ destination: "d1", mode: "pixel" }, "levels", levels));
  }
  if (only === "all" || only === "pool") {
    const entries = buildPool();
    writeFileSync(join(RES, "Pools/relax-pixel.json"), linesJson({ pool: "relax-pixel" }, "entries", entries));
    console.log(`pool: ${entries.length} entries`);
  }
  if (only === "all" || only === "golden") {
    const fixtures = join(REPO, "PuzzleGetawayTests/Fixtures");
    mkdirSync(fixtures, { recursive: true });
    const levels = JSON.parse(readFileSync(join(RES, "Levels/d1-pixel.json"), "utf8")) as { levels: LevelEnvelope[] };
    const golden = buildGolden(levels.levels);
    writeFileSync(join(fixtures, "pixel-golden.json"), `{"version":1,"cases":[\n${golden.cases.map((c) => JSON.stringify(c)).join(",\n")}\n]}\n`);
    console.log(`golden: ${golden.cases.length} cases`);
  }
}
