import type { ModeHandlers } from "./types.js";
import { replaySort, validateSort } from "./sortcore.js";
import { solveForLevel } from "../solvers/sortSolver.js";

/** Bolt Sort ("Tool Bench"). Shares the Liquid engine; adds capped bolts and rusty nuts. */
export const bolt: ModeHandlers = {
  mode: "bolt",
  validate: (level) => validateSort(level, "bolt"),
  replay: replaySort,
  solve: (level, budget) => solveForLevel(level, budget),
};
