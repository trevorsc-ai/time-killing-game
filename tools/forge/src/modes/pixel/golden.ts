/**
 * Golden parity fixtures: initial payload + a tap list + the exact expected state after every tap.
 * Swift (PixelRulesTests) reproduces them move for move. Produced by `npm run build:pixel golden`.
 */
import type { LevelEnvelope } from "../../schema.js";
import { createRng } from "../../util/prng.js";
import {
  applyDetailed,
  gridRows,
  initialState,
  isSolved,
  isStuck,
  legalMoves,
  slotStrings,
  type PackEvent,
  type PixelPayload,
} from "./rules.js";

export interface GoldenStep {
  lane: number;
  legal: boolean;
  grid: string[];
  slots: string[];
  laneNext: number[];
  events: PackEvent[];
  solved: boolean;
  stuck: boolean;
}

export interface GoldenCase {
  name: string;
  levelId: string;
  payload: PixelPayload;
  steps: GoldenStep[];
}

function trace(name: string, levelId: string, payload: PixelPayload, taps: number[]): GoldenCase {
  let s = initialState(payload);
  const steps: GoldenStep[] = [];
  for (const lane of taps) {
    const r = applyDetailed(payload, s, { lane });
    if (!r) {
      steps.push({ lane, legal: false, grid: gridRows(s), slots: slotStrings(s), laneNext: Array.from(s.laneNext), events: [], solved: isSolved(s), stuck: isStuck(payload, s) });
      continue;
    }
    s = r.state;
    steps.push({ lane, legal: true, grid: gridRows(s), slots: slotStrings(s), laneNext: Array.from(s.laneNext), events: r.events, solved: isSolved(s), stuck: isStuck(payload, s) });
  }
  return { name, levelId, payload, steps };
}

/** Random legal play from the start until the board is stuck (or solved), seeded. Returns the taps. */
function randomPlay(payload: PixelPayload, seed: number, wantStuck: boolean): number[] | null {
  for (let attempt = 0; attempt < 400; attempt++) {
    const rng = createRng(seed + attempt);
    let s = initialState(payload);
    const taps: number[] = [];
    for (;;) {
      const moves = legalMoves(payload, s);
      if (moves.length === 0) break;
      const m = moves[rng.int(moves.length)]!;
      taps.push(m.lane);
      s = applyDetailed(payload, s, m)!.state;
    }
    if (isStuck(payload, s) === wantStuck && (wantStuck || isSolved(s))) return taps;
  }
  return null;
}

export function buildGolden(levels: LevelEnvelope[]): { version: 1; cases: GoldenCase[] } {
  const cases: GoldenCase[] = [];
  for (const lv of levels) {
    const payload = lv.payload as PixelPayload;
    const taps = (lv.solution as { lane: number }[]).map((m) => m.lane);
    cases.push(trace(`${lv.id}:solution`, lv.id, payload, taps));
    // A jam, where the level admits one, plus one tap beyond it (illegal).
    const jam = randomPlay(payload, 1000 + lv.order, true);
    if (jam) cases.push(trace(`${lv.id}:jam`, lv.id, payload, [...jam, 0]));
    // Tapping an exhausted lane / over-full tray must be rejected without changing the state.
    cases.push(trace(`${lv.id}:overtap`, lv.id, payload, [...taps, 0, 1]));
  }
  return { version: 1, cases };
}
