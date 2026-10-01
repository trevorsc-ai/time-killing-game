/**
 * Station Snack Cart (d1) Pixel Picnic level plan. `build.ts` turns this into Levels/d1-pixel.json by running the
 * crate/lane search (generate.ts) and storing a verified solution.
 */
import type { Target } from "./generate.js";

export interface LevelPlan {
  order: number;
  scene: string;
  title: string;
  difficulty: number;
  slots: number;
  lanes: number;
  maxSplit: number;
  minCrate: number;
  tutorial?: string;
  twists: string[];
  target: Target;
  seed: number;
  tries: number;
}

export const D1_PLAN: LevelPlan[] = [
  // L1-3: nothing can jam (doomedFraction 0): any tapping order wins.
  {
    order: 2, scene: "fruit-cup", title: "A Cup of Berries", difficulty: 1, slots: 5, lanes: 2, maxSplit: 2, minCrate: 2,
    tutorial: "pixel.tap", twists: [],
    target: { crates: [4, 5], doomedFraction: [0, 0], pStuck: [0, 0], prefer: { pStuck: 0 } }, seed: 101, tries: 300,
  },
  {
    order: 4, scene: "tea-tray", title: "Tea for the Train", difficulty: 1, slots: 5, lanes: 3, maxSplit: 2, minCrate: 2,
    twists: [],
    target: { crates: [6, 8], doomedFraction: [0, 0], pStuck: [0, 0] }, seed: 102, tries: 400,
  },
  {
    order: 6, scene: "donut-box", title: "Donut Delivery", difficulty: 2, slots: 5, lanes: 3, maxSplit: 2, minCrate: 2,
    twists: [],
    target: { crates: [7, 9], doomedFraction: [0, 0], pStuck: [0, 0] }, seed: 103, tries: 800,
  },
  // L4-6: a few traps appear.
  {
    order: 8, scene: "sandwich", title: "Sandwich Stack", difficulty: 3, slots: 4, lanes: 3, maxSplit: 3, minCrate: 2,
    twists: [],
    target: { crates: [8, 11], doomedFraction: [0.01, 0.4], pStuck: [0.04, 0.3], prefer: { pStuck: 0.15 } }, seed: 104, tries: 1500,
  },
  {
    order: 10, scene: "ramen-bowl", title: "Slurpy Ramen", difficulty: 4, slots: 4, lanes: 3, maxSplit: 3, minCrate: 2,
    twists: [],
    target: { crates: [9, 12], doomedFraction: [0.02, 0.5], pStuck: [0.1, 0.4], prefer: { pStuck: 0.25 } }, seed: 105, tries: 1500,
  },
  {
    order: 12, scene: "strawberry-tart", title: "Berry Tart Rescue", difficulty: 5, slots: 3, lanes: 3, maxSplit: 3, minCrate: 2,
    twists: [],
    target: { crates: [8, 11], doomedFraction: [0.05, 0.6], pStuck: [0.2, 0.55], prefer: { pStuck: 0.4 } }, seed: 106, tries: 2500,
  },
  // L7: stones arrive.
  {
    order: 14, scene: "pretzel-stand", title: "Salty Pretzel Stand", difficulty: 6, slots: 3, lanes: 3, maxSplit: 3, minCrate: 2,
    tutorial: undefined, twists: ["stone"],
    target: { crates: [9, 12], doomedFraction: [0.05, 0.7], pStuck: [0.25, 0.7], prefer: { pStuck: 0.45 } }, seed: 107, tries: 2500,
  },
  // L8-10: real look-ahead.
  {
    order: 17, scene: "onigiri-bento", title: "Bento Bundle", difficulty: 7, slots: 3, lanes: 3, maxSplit: 3, minCrate: 3,
    twists: [],
    target: { crates: [10, 14], doomedFraction: [0.08, 0.9], pStuck: [0.4, 0.85], prefer: { pStuck: 0.6 } }, seed: 108, tries: 1500,
  },
  {
    order: 20, scene: "lemonade-jug", title: "Lemonade Lanes", difficulty: 8, slots: 3, lanes: 4, maxSplit: 3, minCrate: 2,
    twists: [],
    target: { crates: [11, 15], doomedFraction: [0.1, 0.9], pStuck: [0.45, 0.9], prefer: { pStuck: 0.65 } }, seed: 109, tries: 1500,
  },
  {
    order: 23, scene: "snack-cart", title: "The Snack Cart Itself", difficulty: 9, slots: 3, lanes: 4, maxSplit: 3, minCrate: 3,
    twists: [],
    target: { crates: [12, 16], doomedFraction: [0.1, 0.9], pStuck: [0.5, 0.92], prefer: { pStuck: 0.7 } }, seed: 110, tries: 800,
  },
];
