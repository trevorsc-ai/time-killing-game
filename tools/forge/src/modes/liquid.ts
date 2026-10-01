import type { ModeHandlers } from "./types.js";
import { replaySort, validateSort } from "./sortcore.js";
import { solveForLevel } from "../solvers/sortSolver.js";

/** Liquid Sort ("Color Mixer"). Rules: docs/rules.md. Payload/moves: docs/level-format.md. */
export const liquid: ModeHandlers = {
  mode: "liquid",
  validate: (level) => validateSort(level, "liquid"),
  replay: replaySort,
  solve: (level, budget) => solveForLevel(level, budget),
};
