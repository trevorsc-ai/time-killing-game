import { Rng } from "../../util/prng.js";
import { DC, DR, isSolved, maskOf, parseBoard, type PipeBoard, type PipeMove, type PipePayload } from "./rules.js";
import { solvePipe } from "./solver.js";

export interface PipeSpec {
  rows: number;
  cols: number;
  /** Number of destinations (1 = a single path; >1 requires tees). */
  dests: number;
  /** Allow decoy tees among the filler tiles. */
  decoyTees?: boolean;
  /** Fraction of non-path cells left empty/blocked. */
  emptyFrac?: number;
  /** Minimum length (in cells) of the first source-to-destination path. */
  minPath?: number;
  /** Maximum length (in cells) of the first path. */
  maxPath?: number;
  /** Accept only scrambles whose planted solution needs between these many taps (inclusive). */
  minTaps?: number;
  maxTaps?: number;
  /** Node budget for the improvement search (0 disables it). */
  solveBudget?: number;
}

export interface GeneratedPipe {
  payload: PipePayload;
  solution: PipeMove[];
  /** Taps of the stored solution (== par). */
  par: number;
  /** Planted solution length before the optional search improved it. */
  plantedTaps: number;
  /** True if the improvement search finished and proved `par` minimal. */
  proven: boolean;
}

type Cell = [number, number];

/** Rotation k (0..3) such that maskOf(kind, k) === mask, or -1. */
function rotFor(kind: string, mask: number): number {
  for (let k = 0; k < 4; k++) if (maskOf(kind, k) === mask) return k;
  return -1;
}

function randomPath(rng: Rng, rows: number, cols: number, from: Cell, to: Cell, blocked: Set<number>, maxLen: number, minLen = 0): Cell[] | null {
  const path: Cell[] = [from];
  const seen = new Set<number>([from[0] * cols + from[1]]);
  let steps = 0;
  const dfs = (): boolean => {
    if (++steps > 4000) return false;
    const [r, c] = path[path.length - 1];
    if (r === to[0] && c === to[1]) return path.length >= minLen;
    if (path.length >= maxLen) return false;
    // Bias toward the goal: shuffle, then stable-sort by distance with some noise.
    const order = rng.shuffle([0, 1, 2, 3]);
    order.sort((a, b) => {
      const da = Math.abs(r + DR[a] - to[0]) + Math.abs(c + DC[a] - to[1]);
      const db = Math.abs(r + DR[b] - to[0]) + Math.abs(c + DC[b] - to[1]);
      return da - db + (rng.next() - 0.5) * 2.2;
    });
    for (const d of order) {
      const nr = r + DR[d];
      const nc = c + DC[d];
      if (nr < 0 || nc < 0 || nr >= rows || nc >= cols) continue;
      const key = nr * cols + nc;
      if (seen.has(key)) continue;
      if (blocked.has(key) && !(nr === to[0] && nc === to[1])) continue;
      seen.add(key);
      path.push([nr, nc]);
      if (dfs()) return true;
      path.pop();
      seen.delete(key);
    }
    return false;
  };
  return dfs() ? path : null;
}

/**
 * Plant a solved layout (a tree from the source to every destination), convert it to tiles, fill the rest with
 * decoys, then scramble the rotatable tiles with the seeded RNG. Source and destinations are listed in `fixed`.
 * Returns null if no acceptable layout was found for this seed.
 */
export function generatePipe(seed: number, spec: PipeSpec): GeneratedPipe | null {
  const rng = new Rng(seed);
  const { rows, cols } = spec;
  for (let attempt = 0; attempt < 400; attempt++) {
    // Edge masks of the planted tree, per cell (bit d = opening toward direction d).
    const mask = new Array<number>(rows * cols).fill(0);
    const inTree = new Set<number>();
    const destSet = new Set<number>();
    const link = (a: Cell, b: Cell) => {
      for (let d = 0; d < 4; d++) {
        if (a[0] + DR[d] === b[0] && a[1] + DC[d] === b[1]) {
          mask[a[0] * cols + a[1]] |= 1 << d;
          mask[b[0] * cols + b[1]] |= 1 << ((d + 2) % 4);
        }
      }
    };
    // Source on the border.
    const border: Cell[] = [];
    for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) if (r === 0 || c === 0 || r === rows - 1 || c === cols - 1) border.push([r, c]);
    const src = rng.pick(border);
    const minPath = spec.minPath ?? Math.max(3, Math.floor((rows + cols) / 2));
    const maxPath = spec.maxPath ?? rows * cols;
    const farCells: Cell[] = [];
    for (let r = 0; r < rows; r++)
      for (let c = 0; c < cols; c++) {
        const dist = Math.abs(r - src[0]) + Math.abs(c - src[1]);
        if (dist + 1 >= Math.ceil(minPath / 2) && dist + 1 <= maxPath) farCells.push([r, c]);
      }
    if (!farCells.length) continue;
    const d1 = rng.pick(farCells);
    const first = randomPath(rng, rows, cols, src, d1, new Set(), maxPath, minPath);
    if (!first || first.length < minPath) continue;
    first.forEach((cell) => inTree.add(cell[0] * cols + cell[1]));
    for (let i = 0; i + 1 < first.length; i++) link(first[i], first[i + 1]);
    destSet.add(d1[0] * cols + d1[1]);
    // Extra destinations branch off interior path cells (which then become tees).
    let ok = true;
    for (let k = 1; k < spec.dests && ok; k++) {
      ok = false;
      for (let tries = 0; tries < 60 && !ok; tries++) {
        const branchCands = [...inTree].filter((key) => {
          const m = mask[key];
          const deg = (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1);
          return deg === 2 && key !== src[0] * cols + src[1] && !destSet.has(key);
        });
        if (!branchCands.length) break;
        const bKey = rng.pick(branchCands);
        const from: Cell = [Math.floor(bKey / cols), bKey % cols];
        const free: Cell[] = [];
        for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) if (!inTree.has(r * cols + c)) free.push([r, c]);
        if (!free.length) break;
        const to = rng.pick(free);
        const blocked = new Set<number>([...inTree]);
        blocked.delete(bKey);
        // The branch must leave `from` through a free cell: forbid revisiting tree cells.
        const path = randomPath(rng, rows, cols, from, to, blocked, 2 + rows + cols);
        if (!path || path.length < 2) continue;
        // Reject paths that touch the tree again except at the start (blocked handles that) or end next to nothing special.
        path.slice(1).forEach((cell) => inTree.add(cell[0] * cols + cell[1]));
        for (let i = 0; i + 1 < path.length; i++) link(path[i], path[i + 1]);
        const last = path[path.length - 1];
        destSet.add(last[0] * cols + last[1]);
        ok = true;
      }
    }
    if (!ok) continue;
    // Destinations must be leaves (no further branches grew out of them) and source a leaf.
    const deg = (key: number) => {
      const m = mask[key];
      return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1) + ((m >> 3) & 1);
    };
    if ([...destSet].some((k) => deg(k) !== 1) || deg(src[0] * cols + src[1]) !== 1) continue;
    if ([...inTree].some((k) => deg(k) > 3)) continue;

    // Build solved tiles.
    const solvedKind = new Array<string>(rows * cols).fill(".");
    const solvedRot = new Array<number>(rows * cols).fill(0);
    let bad = false;
    for (let key = 0; key < rows * cols; key++) {
      if (!inTree.has(key)) continue;
      const m = mask[key];
      const dg = deg(key);
      let kind: string;
      if (key === src[0] * cols + src[1]) kind = "S";
      else if (destSet.has(key)) kind = "D";
      else if (dg === 3) kind = "t";
      else if (dg === 2) kind = m === 5 || m === 10 ? "i" : "l";
      else {
        bad = true;
        break;
      }
      const rot = rotFor(kind, m);
      if (rot < 0) {
        bad = true;
        break;
      }
      solvedKind[key] = kind;
      solvedRot[key] = rot;
    }
    if (bad) continue;
    // Decoy filler.
    const emptyFrac = spec.emptyFrac ?? 0.12;
    const fillKinds = spec.decoyTees ? ["i", "l", "l", "t"] : ["i", "l", "l"];
    for (let key = 0; key < rows * cols; key++) {
      if (inTree.has(key)) continue;
      if (rng.next() < emptyFrac) solvedKind[key] = ".";
      else {
        solvedKind[key] = rng.pick(fillKinds);
        solvedRot[key] = rng.int(4);
      }
    }
    // Scramble every rotatable tile; reject an unsolved-start violation or out-of-range tap counts.
    const fixedCells: [number, number][] = [];
    const rots = solvedRot.slice();
    for (let key = 0; key < rows * cols; key++) {
      const kind = solvedKind[key];
      if (kind === "S" || kind === "D") fixedCells.push([Math.floor(key / cols), key % cols]);
      else if (kind !== ".") rots[key] = rng.int(4);
    }
    const grid: string[][] = [];
    for (let r = 0; r < rows; r++) {
      const row: string[] = [];
      for (let c = 0; c < cols; c++) row.push(`${solvedKind[r * cols + c]}${solvedKind[r * cols + c] === "." ? 0 : rots[r * cols + c]}`);
      grid.push(row);
    }
    const payload: PipePayload = { grid, fixed: fixedCells };
    const board = parseBoard(payload);
    if (isSolved(board, board.rots)) continue;
    const planted = plantedSolution(board, solvedRot, inTree);
    if (!planted) continue;
    if (planted.length < (spec.minTaps ?? 2) || planted.length > (spec.maxTaps ?? 1e9)) continue;
    let moves = planted;
    let proven = false;
    const budget = spec.solveBudget ?? 200_000;
    if (budget > 0) {
      const first = solvePipe(board, budget, planted.length);
      if (first.solution && first.solution.moves.length < moves.length) moves = first.solution.moves;
      // Proof pass: nothing strictly cheaper than the stored solution exists within budget.
      const check = solvePipe(board, budget, moves.length);
      proven = check.solution === null && check.exhaustive;
    }
    return { payload, solution: moves, par: moves.length, plantedTaps: planted.length, proven };
  }
  return null;
}

/** Taps toward the planted layout: each tile on the tree is turned the minimum number of times to show the planted mask. */
function plantedSolution(b: PipeBoard, solvedRot: number[], inTree: Set<number>): PipeMove[] | null {
  const moves: PipeMove[] = [];
  const state = b.rots.slice();
  for (let i = 0; i < b.kinds.length; i++) {
    if (!inTree.has(i) || b.fixed[i]) continue;
    const want = maskOf(b.kinds[i], solvedRot[i]);
    let k = 0;
    while (maskOf(b.kinds[i], state[i] + k) !== want) {
      k++;
      if (k > 3) return null;
    }
    for (let j = 0; j < k; j++) moves.push({ r: Math.floor(i / b.cols), c: i % b.cols });
    state[i] = (state[i] + k) % 4;
  }
  return isSolved(b, state) ? moves : null;
}
