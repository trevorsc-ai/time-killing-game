/**
 * Generates PuzzleGetaway/Resources/Levels/d3-parking.json (Baggage Bay, 6 levels).
 * Deterministic: every level has a recorded seed. Run: npx tsx scripts/gen-parking.ts
 */
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { DEFAULT_RESOURCES } from "../src/validate.js";
import { generateParking, type ParkingSpec } from "../src/modes/parking/generator.js";
import { solveParking } from "../src/modes/parking/solver.js";

interface Plan {
  order: number;
  title: string;
  difficulty: number;
  seed: number;
  spec: ParkingSpec;
  tutorial?: string;
  twists: string[];
}

const PLANS: Plan[] = [
  { order: 1, title: "First Slide", difficulty: 1, seed: 301, tutorial: "parking.slide", twists: [], spec: { targets: 1, lo: 2, hi: 2, minVehicles: 3, maxVehicles: 3 } },
  { order: 2, title: "Tight Corner", difficulty: 2, seed: 302, twists: [], spec: { targets: 1, lo: 5, hi: 6, minVehicles: 6, maxVehicles: 8 } },
  { order: 3, title: "Rush Hour at the Bay", difficulty: 3, seed: 303, twists: [], spec: { targets: 1, lo: 9, hi: 11, minVehicles: 8, maxVehicles: 10 } },
  { order: 4, title: "The Long Queue", difficulty: 5, seed: 304, twists: [], spec: { targets: 1, lo: 14, hi: 17, minVehicles: 9, maxVehicles: 11 } },
  { order: 5, title: "Two Gates", difficulty: 7, seed: 305, tutorial: "twist.second-gate", twists: ["second-gate"], spec: { targets: 2, lo: 14, hi: 18, minVehicles: 8, maxVehicles: 10 } },
  { order: 6, title: "Grand Departure", difficulty: 9, seed: 306, twists: ["second-gate"], spec: { targets: 2, lo: 20, hi: 40, minVehicles: 9, maxVehicles: 12, attempts: 6000, stopAt: 22 } },
];

const levels = PLANS.map((plan) => {
  let g = null;
  for (let k = 0; k < 6 && !g; k++) g = generateParking(plan.seed + k * 1000, plan.spec);
  if (!g) throw new Error(`no board found for order ${plan.order}`);
  const solution = solveParking(g.payload)!;
  console.log(`order ${plan.order}: optimal ${solution.length}, ${g.payload.vehicles.length} vehicles`);
  return {
    id: `d3-parking-${String(plan.order).padStart(2, "0")}`,
    mode: "parking",
    destination: "d3",
    order: plan.order,
    title: plan.title,
    difficulty: plan.difficulty,
    ...(plan.tutorial ? { tutorial: plan.tutorial } : {}),
    twists: plan.twists,
    par: solution.length,
    solution,
    payload: g.payload,
  };
});

writeFileSync(join(DEFAULT_RESOURCES, "Levels", "d3-parking.json"), JSON.stringify({ destination: "d3", mode: "parking", levels }, null, 1) + "\n");
