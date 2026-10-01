import type { LevelEnvelope } from "../schema.js";

export interface ReplayResult {
  ok: boolean;
  /** Human-readable reason when !ok. */
  error?: string;
}

/**
 * What each puzzle mode registers in src/modes/index.ts.
 * - validate: payload/solution shape checks. Return a list of error strings (empty = valid).
 * - replay:   apply level.solution from level.payload with the canonical rules; ok iff it ends solved
 *             and every move is legal.
 * - solve:    optional solver (shortest solution or null if none found within `budget` nodes).
 */
export interface ModeHandlers {
  mode: string;
  validate(level: LevelEnvelope): string[];
  replay(level: LevelEnvelope): ReplayResult;
  solve?(level: LevelEnvelope, budget?: number): unknown[] | null;
}
