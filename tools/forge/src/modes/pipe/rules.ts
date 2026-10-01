/**
 * Flow Fix rules (docs/rules.md, "Flow Fix"). Must match PuzzleGetaway/Modes/Pipe/PipeRules.swift.
 * Openings are a 4-bit mask N=1, E=2, S=4, W=8. Rotation is 90 degrees clockwise.
 */
export const N = 1;
export const E = 2;
export const S = 4;
export const W = 8;
export const DIRS = [N, E, S, W] as const;
/** Row/column deltas for N, E, S, W (index = bit position). */
export const DR = [-1, 0, 1, 0];
export const DC = [0, 1, 0, -1];

export type Kind = "." | "i" | "l" | "t" | "x" | "S" | "D";

export interface PipePayload {
  grid: string[][];
  fixed?: [number, number][];
}
export interface PipeMove {
  r: number;
  c: number;
}

const BASE: Record<string, number> = { ".": 0, i: N | S, l: N | E, t: E | S | W, x: 15, S: N, D: N };

export const rotateMask = (m: number): number => ((m << 1) & 15) | (m >> 3);

export function maskOf(kind: string, rot: number): number {
  let m = BASE[kind] ?? 0;
  for (let k = 0; k < ((rot % 4) + 4) % 4; k++) m = rotateMask(m);
  return m;
}

export interface PipeBoard {
  rows: number;
  cols: number;
  kinds: string[];
  /** Initial rotations, row-major. */
  rots: number[];
  fixed: boolean[];
  sourceIndex: number;
  destIndices: number[];
}

export type PipeState = number[];

export function parseToken(tok: string): { kind: string; rot: number } | null {
  if (typeof tok !== "string" || tok.length !== 2) return null;
  const kind = tok[0];
  const rot = Number(tok[1]);
  if (!(kind in BASE) || !Number.isInteger(rot) || rot < 0 || rot > 3) return null;
  return { kind, rot };
}

export function parseBoard(p: PipePayload): PipeBoard {
  const rows = p.grid.length;
  const cols = p.grid[0].length;
  const kinds: string[] = [];
  const rots: number[] = [];
  p.grid.forEach((row) =>
    row.forEach((tok) => {
      const t = parseToken(tok)!;
      kinds.push(t.kind);
      rots.push(t.rot);
    }),
  );
  const fixed = new Array<boolean>(rows * cols).fill(false);
  for (const [r, c] of p.fixed ?? []) fixed[r * cols + c] = true;
  return {
    rows,
    cols,
    kinds,
    rots,
    fixed,
    sourceIndex: kinds.indexOf("S"),
    destIndices: kinds.flatMap((k, i) => (k === "D" ? [i] : [])),
  };
}

export function initialState(b: PipeBoard): PipeState {
  return b.rots.slice();
}

export function legalMoves(b: PipeBoard, s: PipeState): PipeMove[] {
  const out: PipeMove[] = [];
  for (let i = 0; i < b.kinds.length; i++) {
    if (b.kinds[i] !== "." && !b.fixed[i]) out.push({ r: Math.floor(i / b.cols), c: i % b.cols });
  }
  void s;
  return out;
}

export function apply(b: PipeBoard, s: PipeState, m: PipeMove): PipeState | null {
  if (!Number.isInteger(m.r) || !Number.isInteger(m.c) || m.r < 0 || m.c < 0 || m.r >= b.rows || m.c >= b.cols) return null;
  const i = m.r * b.cols + m.c;
  if (b.kinds[i] === "." || b.fixed[i]) return null;
  const next = s.slice();
  next[i] = (next[i] + 1) % 4;
  return next;
}

/** Tiles reached by flow from the source (BFS). `parent[i]` = direction index (0..3) pointing from i toward the tile that fed it, or -1. */
export function flow(b: PipeBoard, s: PipeState): { reached: boolean[]; parent: number[] } {
  const reached = new Array<boolean>(b.kinds.length).fill(false);
  const parent = new Array<number>(b.kinds.length).fill(-1);
  if (b.sourceIndex < 0) return { reached, parent };
  reached[b.sourceIndex] = true;
  const queue = [b.sourceIndex];
  for (let h = 0; h < queue.length; h++) {
    const i = queue[h];
    const r = Math.floor(i / b.cols);
    const c = i % b.cols;
    const m = maskOf(b.kinds[i], s[i]);
    for (let d = 0; d < 4; d++) {
      if (!(m & (1 << d))) continue;
      const nr = r + DR[d];
      const nc = c + DC[d];
      if (nr < 0 || nc < 0 || nr >= b.rows || nc >= b.cols) continue;
      const j = nr * b.cols + nc;
      if (reached[j]) continue;
      if (maskOf(b.kinds[j], s[j]) & (1 << ((d + 2) % 4))) {
        reached[j] = true;
        parent[j] = (d + 2) % 4;
        queue.push(j);
      }
    }
  }
  return { reached, parent };
}

export function isSolved(b: PipeBoard, s: PipeState): boolean {
  const { reached } = flow(b, s);
  return b.destIndices.length > 0 && b.destIndices.every((i) => reached[i]);
}
