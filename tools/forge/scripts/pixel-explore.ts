// Exploration helper: print solver statistics for random crate configurations of each scene.
import { SCENES } from "../src/modes/pixel/art/scenes.js";
import { makeLanes, evaluate } from "../src/modes/pixel/generate.js";
import { createRng } from "../src/util/prng.js";

const slotsArg = Number(process.argv[2] ?? 3);
const lanesArg = Number(process.argv[3] ?? 3);
const split = Number(process.argv[4] ?? 2);
for (const s of SCENES) {
  const rng = createRng(7);
  const t0 = Date.now();
  const rows: string[] = [];
  for (let i = 0; i < 30; i++) {
    const lanes = makeLanes(s.rows, lanesArg, split, 2, rng);
    if (!lanes) continue;
    const c = evaluate({ grid: s.rows, slots: slotsArg, lanes }, {}, 100_000);
    const a = c.analysis;
    rows.push(
      `crates=${lanes.reduce((n, l) => n + l.length, 0)} states=${a.states}${a.complete ? "" : "+"} solv=${a.solvable ? 1 : 0} doomed=${a.doomedFraction.toFixed(2)} pStuck=${a.pStuck.toFixed(2)} traps=${a.firstTraps}/${a.firstMoves} lines=${a.winningLines}`,
    );
  }
  console.log(`== ${s.id} (${Date.now() - t0}ms)`);
  console.log(rows.slice(0, 8).join("\n"));
}
