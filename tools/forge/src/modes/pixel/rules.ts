/**
 * Pixel Picnic ("Critter Clear") canonical rules, TypeScript side.
 * Spec: docs/rules.md "Pixel Picnic". The Swift mirror is PuzzleGetaway/Modes/Pixel/PixelRules.swift.
 * Keep both in lockstep; golden fixtures (PuzzleGetawayTests/Fixtures) are produced from this file.
 */

export interface Crate {
  color: string;
  count: number;
  /** Display only. */
  pattern?: string;
}

export interface PixelPayload {
  /** Rows of equal length. `.` = empty (cleared from the start), `#` = stone, otherwise a palette id. */
  grid: string[];
  /** Tray slots. */
  slots: number;
  /** Lanes, front crate first. */
  lanes: Crate[][];
}

export interface PixelMove {
  lane: number;
}

export interface PixelState {
  w: number;
  h: number;
  /** Row-major char codes; 46 ('.') = cleared, 35 ('#') = stone. */
  cells: Uint8Array;
  /** Per slot: palette char code, 0 = empty. */
  slotColor: Uint8Array;
  slotRem: Int16Array;
  /** Per lane: how many crates have been tapped (index of the current front crate). */
  laneNext: Int16Array;
}

export const CLEAR = 46;
export const STONE = 35;

/** One slot visit that changed something; used for golden traces and animation replay. */
export interface PackEvent {
  slot: number;
  color: string;
  /** Cell indices (row * w + c) packed, in BFS order. */
  cells: number[];
  /** Stones that crumbled right after this visit. */
  crumbled: number[];
  /** True if the crate reached 0 and departed. */
  departed: boolean;
}

export function initialState(p: PixelPayload): PixelState {
  const h = p.grid.length;
  const w = p.grid[0]?.length ?? 0;
  const cells = new Uint8Array(w * h);
  for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) cells[r * w + c] = p.grid[r]!.charCodeAt(c);
  return {
    w,
    h,
    cells,
    slotColor: new Uint8Array(p.slots),
    slotRem: new Int16Array(p.slots),
    laneNext: new Int16Array(p.lanes.length),
  };
}

export function cloneState(s: PixelState): PixelState {
  return {
    w: s.w,
    h: s.h,
    cells: s.cells.slice(),
    slotColor: s.slotColor.slice(),
    slotRem: s.slotRem.slice(),
    laneNext: s.laneNext.slice(),
  };
}

export function isPixelCode(code: number): boolean {
  return code !== CLEAR && code !== STONE;
}

export function pixelsLeft(s: PixelState): number {
  let n = 0;
  for (const c of s.cells) if (isPixelCode(c)) n++;
  return n;
}

export function isSolved(s: PixelState): boolean {
  return pixelsLeft(s) === 0;
}

export function legalMoves(p: PixelPayload, s: PixelState): PixelMove[] {
  if (!s.slotColor.includes(0)) return [];
  const out: PixelMove[] = [];
  for (let l = 0; l < p.lanes.length; l++) if (s.laneNext[l]! < p.lanes[l]!.length) out.push({ lane: l });
  return out;
}

export function isStuck(p: PixelPayload, s: PixelState): boolean {
  return !isSolved(s) && legalMoves(p, s).length === 0;
}

export function isExposed(s: PixelState, idx: number): boolean {
  const { w, h, cells } = s;
  const r = Math.floor(idx / w);
  const c = idx - r * w;
  if (r === 0 || c === 0 || r === h - 1 || c === w - 1) return true;
  return cells[idx - w] === CLEAR || cells[idx - 1] === CLEAR || cells[idx + 1] === CLEAR || cells[idx + w] === CLEAR;
}

/** Pack one crate visit. Mutates `s`. Returns packed cell indices (BFS order). */
export function pack(s: PixelState, slot: number): number[] {
  const color = s.slotColor[slot]!;
  const { w, h, cells } = s;
  let rem = s.slotRem[slot]!;
  const visited = new Uint8Array(w * h);
  const queue: number[] = [];
  for (let i = 0; i < cells.length; i++) {
    if (cells[i] === color && isExposed(s, i)) {
      visited[i] = 1;
      queue.push(i);
    }
  }
  const enqueue = (n: number) => {
    if (cells[n] === color && !visited[n]) {
      visited[n] = 1;
      queue.push(n);
    }
  };
  const packed: number[] = [];
  let head = 0;
  while (rem > 0 && head < queue.length) {
    const p = queue[head++]!;
    cells[p] = CLEAR;
    rem--;
    packed.push(p);
    const r = Math.floor(p / w);
    const c = p - r * w;
    // up, left, right, down
    if (r > 0) enqueue(p - w);
    if (c > 0) enqueue(p - 1);
    if (c < w - 1) enqueue(p + 1);
    if (r < h - 1) enqueue(p + w);
  }
  s.slotRem[slot] = rem;
  return packed;
}

/** Crumble stones 4-adjacent to any of `packed`. Mutates `s`. Returns crumbled indices (row-major). */
export function crumble(s: PixelState, packed: number[]): number[] {
  const { w, h, cells } = s;
  const hit = new Set<number>();
  for (const p of packed) {
    const r = Math.floor(p / w);
    const c = p - r * w;
    const ns = [r > 0 ? p - w : -1, c > 0 ? p - 1 : -1, c < w - 1 ? p + 1 : -1, r < h - 1 ? p + w : -1];
    for (const n of ns) if (n >= 0 && cells[n] === STONE) hit.add(n);
  }
  const out = [...hit].sort((a, b) => a - b);
  for (const n of out) cells[n] = CLEAR;
  return out;
}

/** Run resolve() to its fixpoint. Mutates `s`; returns the events in order. */
export function resolve(s: PixelState): PackEvent[] {
  const events: PackEvent[] = [];
  let changed = true;
  while (changed) {
    changed = false;
    for (let slot = 0; slot < s.slotColor.length; slot++) {
      if (s.slotColor[slot] === 0) continue;
      const color = String.fromCharCode(s.slotColor[slot]!);
      const packed = pack(s, slot);
      const crumbled = packed.length > 0 ? crumble(s, packed) : [];
      const departed = s.slotRem[slot] === 0;
      if (departed) s.slotColor[slot] = 0;
      if (packed.length > 0 || crumbled.length > 0 || departed) {
        events.push({ slot, color, cells: packed, crumbled, departed });
        changed = true;
      }
    }
  }
  return events;
}

/** Apply a tap. Returns null if illegal. */
export function applyDetailed(
  p: PixelPayload,
  s: PixelState,
  m: PixelMove,
): { state: PixelState; events: PackEvent[]; slot: number } | null {
  const lane = m.lane;
  if (!Number.isInteger(lane) || lane < 0 || lane >= p.lanes.length) return null;
  const idx = s.laneNext[lane]!;
  const crate = p.lanes[lane]![idx];
  if (!crate) return null;
  const slot = s.slotColor.indexOf(0);
  if (slot < 0) return null;
  const n = cloneState(s);
  n.laneNext[lane] = idx + 1;
  n.slotColor[slot] = crate.color.charCodeAt(0);
  n.slotRem[slot] = crate.count;
  const events = resolve(n);
  return { state: n, events, slot };
}

export function apply(p: PixelPayload, s: PixelState, m: PixelMove): PixelState | null {
  return applyDetailed(p, s, m)?.state ?? null;
}

/** Canonical string key for memoization / hashing. */
export function stateKey(s: PixelState): string {
  return `${Buffer.from(s.cells).toString("latin1")}|${Array.from(s.slotColor).join(",")}|${Array.from(s.slotRem).join(",")}|${Array.from(s.laneNext).join(",")}`;
}

export function gridRows(s: PixelState): string[] {
  const rows: string[] = [];
  for (let r = 0; r < s.h; r++) rows.push(Buffer.from(s.cells.subarray(r * s.w, (r + 1) * s.w)).toString("latin1"));
  return rows;
}

/** Slots as `["r:3", "", "g:2"]` ("" = empty). */
export function slotStrings(s: PixelState): string[] {
  return Array.from(s.slotColor, (c, i) => (c === 0 ? "" : `${String.fromCharCode(c)}:${s.slotRem[i]}`));
}

/** Per-color pixel counts of a grid. */
export function colorCounts(grid: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const row of grid) for (const ch of row) if (ch !== "." && ch !== "#") out[ch] = (out[ch] ?? 0) + 1;
  return out;
}

export function crateTotals(lanes: Crate[][]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const lane of lanes) for (const c of lane) out[c.color] = (out[c.color] ?? 0) + c.count;
  return out;
}

/** Replay a lane-tap list. `ok` is false on an illegal move or on moves after the board became solved. */
export function replayMoves(
  p: PixelPayload,
  moves: PixelMove[],
): { state: PixelState; ok: boolean; failedAt: number; solvedAt: number } {
  let s = initialState(p);
  let solvedAt = -1;
  for (let i = 0; i < moves.length; i++) {
    if (solvedAt >= 0) return { state: s, ok: false, failedAt: i, solvedAt };
    const n = apply(p, s, moves[i]!);
    if (!n) return { state: s, ok: false, failedAt: i, solvedAt };
    s = n;
    if (isSolved(s)) solvedAt = i;
  }
  return { state: s, ok: true, failedAt: -1, solvedAt };
}
