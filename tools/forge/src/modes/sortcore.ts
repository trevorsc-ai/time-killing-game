/**
 * Shared Liquid Sort / Bolt Sort rules engine. Canonical description: docs/rules.md.
 * Swift mirror: PuzzleGetaway/Modes/Sort/SortRules.swift. Keep both identical.
 */
import type { LevelEnvelope } from "../schema.js";

export interface SortPayload {
  capacity?: number;
  /** Per-bolt capacities (bolt mode, twist `capped`). */
  capacities?: number[];
  /** Layers bottom to top, as palette ids. */
  tubes: string[][];
  /** `[tubeIndex, layerIndex]` pairs (layer 0 = bottom). */
  hidden?: [number, number][];
  locks?: { tube: number; color: string }[];
  rusty?: { bolt: number; index: number; color: string }[];
}

/** One layer / nut. `h` = hidden (frosted "?"), `r` = rust tag color or "" when not rusty. */
export interface Layer {
  readonly c: string;
  readonly h: boolean;
  readonly r: string;
}

export interface SortState {
  tubes: Layer[][];
  /** `locks[i]` = color that opens tube i, or "" when it is not locked (any more). */
  locks: string[];
}

export interface SortMove {
  from: number;
  to: number;
}

export const DEFAULT_CAPACITY = 4;

export function layer(c: string, h = false, r = ""): Layer {
  return { c, h, r };
}

export class SortRules {
  readonly caps: number[];

  constructor(payload: SortPayload) {
    const n = payload.tubes.length;
    const base = payload.capacity ?? DEFAULT_CAPACITY;
    this.caps = payload.capacities ? payload.capacities.slice() : new Array<number>(n).fill(base);
  }

  get tubeCount(): number {
    return this.caps.length;
  }

  /** Builds the initial state from a payload (applies hidden / locks / rust, reveals tops, settles). */
  static initialState(payload: SortPayload): SortState {
    const tubes: Layer[][] = payload.tubes.map((t) => t.map((c) => layer(c)));
    for (const [ti, li] of payload.hidden ?? []) {
      const t = tubes[ti];
      if (t && t[li]) t[li] = layer(t[li].c, true, t[li].r);
    }
    for (const r of payload.rusty ?? []) {
      const t = tubes[r.bolt];
      if (t && t[r.index]) t[r.index] = layer(t[r.index].c, false, r.color);
    }
    const locks = payload.tubes.map(() => "");
    for (const l of payload.locks ?? []) locks[l.tube] = l.color;
    for (const t of tubes) revealTop(t);
    return settle({ tubes, locks });
  }

  legalMoves(s: SortState): SortMove[] {
    const out: SortMove[] = [];
    const n = s.tubes.length;
    for (let from = 0; from < n; from++) {
      if (!this.canSource(s, from)) continue;
      for (let to = 0; to < n; to++) {
        if (to !== from && this.canTarget(s, from, to)) out.push({ from, to });
      }
    }
    return out;
  }

  /** Source tube is non-empty, unlocked, and its top nut is not rusty. */
  canSource(s: SortState, from: number): boolean {
    const t = s.tubes[from];
    if (!t || t.length === 0 || s.locks[from] !== "") return false;
    const top = t[t.length - 1];
    return !top.h && top.r === "";
  }

  /** Assumes `canSource(from)`. */
  canTarget(s: SortState, from: number, to: number): boolean {
    const dst = s.tubes[to];
    if (!dst || s.locks[to] !== "" || dst.length >= this.caps[to]) return false;
    if (dst.length === 0) return true;
    const src = s.tubes[from];
    return dst[dst.length - 1].c === src[src.length - 1].c;
  }

  apply(m: SortMove, s: SortState): SortState | null {
    const n = s.tubes.length;
    if (!Number.isInteger(m.from) || !Number.isInteger(m.to)) return null;
    if (m.from < 0 || m.to < 0 || m.from >= n || m.to >= n || m.from === m.to) return null;
    if (!this.canSource(s, m.from) || !this.canTarget(s, m.from, m.to)) return null;
    const src = s.tubes[m.from];
    const dst = s.tubes[m.to];
    const topC = src[src.length - 1].c;
    let run = 0;
    for (let i = src.length - 1; i >= 0; i--) {
      const l = src[i];
      if (l.c !== topC || l.h || l.r !== "") break;
      run++;
    }
    const k = Math.min(run, this.caps[m.to] - dst.length);
    if (k <= 0) return null;
    const newSrc = src.slice(0, src.length - k);
    revealTop(newSrc);
    const newDst = dst.concat(src.slice(src.length - k));
    const tubes = s.tubes.slice();
    tubes[m.from] = newSrc;
    tubes[m.to] = newDst;
    return settle({ tubes, locks: s.locks });
  }

  isSolved(s: SortState): boolean {
    const seen = new Set<string>();
    for (const t of s.tubes) {
      if (t.length === 0) continue;
      const c = t[0].c;
      for (const l of t) if (l.c !== c) return false;
      if (seen.has(c)) return false;
      seen.add(c);
    }
    return true;
  }

  isStuck(s: SortState): boolean {
    return !this.isSolved(s) && this.legalMoves(s).length === 0;
  }
}

function revealTop(t: Layer[]): void {
  const last = t.length - 1;
  if (last >= 0 && t[last].h) t[last] = layer(t[last].c, false, t[last].r);
}

/** Colors completed in `tubes` (see docs/rules.md "Completed color"). */
export function completedColors(tubes: readonly Layer[][]): Set<string> {
  const holders = new Map<string, number>();
  const impure = new Set<string>();
  for (const t of tubes) {
    if (t.length === 0) continue;
    const here = new Set<string>();
    for (const l of t) here.add(l.c);
    for (const c of here) holders.set(c, (holders.get(c) ?? 0) + 1);
    if (here.size > 1) for (const c of here) impure.add(c);
  }
  const done = new Set<string>();
  for (const [c, n] of holders) if (n === 1 && !impure.has(c)) done.add(c);
  return done;
}

/** Opens satisfied locks and clears satisfied rust. Returns the same object when nothing changed. */
function settle(s: SortState): SortState {
  const needs = s.locks.some((l) => l !== "") || s.tubes.some((t) => t.some((l) => l.r !== ""));
  if (!needs) return s;
  const done = completedColors(s.tubes);
  if (done.size === 0) return s;
  let locks = s.locks;
  if (locks.some((l) => l !== "" && done.has(l))) locks = locks.map((l) => (l !== "" && done.has(l) ? "" : l));
  let tubes = s.tubes;
  if (tubes.some((t) => t.some((l) => l.r !== "" && done.has(l.r)))) {
    tubes = tubes.map((t) =>
      t.some((l) => l.r !== "" && done.has(l.r)) ? t.map((l) => (l.r !== "" && done.has(l.r) ? layer(l.c, l.h, "") : l)) : t,
    );
  }
  return { tubes, locks };
}

/** Non-canonical, order-preserving text form (used by golden tests; Swift implements the same). */
export function fingerprint(s: SortState): string {
  const t = s.tubes.map((tube) => tube.map((l) => l.c + (l.h ? "?" : "") + (l.r ? "~" + l.r : "")).join("")).join("|");
  return t + "#" + s.locks.join(",");
}

export function payloadOf(level: LevelEnvelope): SortPayload {
  return level.payload as SortPayload;
}

export interface SortReplay {
  ok: boolean;
  error?: string;
}

/** Replays `level.solution`. Moves after the first solved state, or illegal moves, are errors. */
export function replaySort(level: LevelEnvelope): SortReplay {
  const p = payloadOf(level);
  const rules = new SortRules(p);
  let s = SortRules.initialState(p);
  for (const [i, raw] of level.solution.entries()) {
    if (rules.isSolved(s)) return { ok: false, error: `move ${i}: puzzle already solved` };
    const next = rules.apply(raw as SortMove, s);
    if (!next) return { ok: false, error: `move ${i}: illegal move ${JSON.stringify(raw)}` };
    s = next;
  }
  return rules.isSolved(s) ? { ok: true } : { ok: false, error: "final state is not solved" };
}

const isInt = (x: unknown): x is number => typeof x === "number" && Number.isInteger(x);

/** Payload + solution shape validation shared by liquid and bolt. */
export function validateSort(level: LevelEnvelope, mode: "liquid" | "bolt"): string[] {
  const errs: string[] = [];
  const p = level.payload as Partial<SortPayload> | null;
  if (!p || typeof p !== "object") return ["payload must be an object"];
  if (!Array.isArray(p.tubes) || p.tubes.length < 2) return ["payload.tubes must be an array of at least 2 tubes"];
  if (p.capacity !== undefined && (!isInt(p.capacity) || p.capacity < 1 || p.capacity > 8)) errs.push("payload.capacity must be an integer 1..8");
  const n = p.tubes.length;
  if (p.capacities !== undefined) {
    if (!Array.isArray(p.capacities) || p.capacities.length !== n || !p.capacities.every((c) => isInt(c) && c >= 1 && c <= 8))
      errs.push("payload.capacities must be one integer 1..8 per tube");
    if (mode === "liquid") errs.push("payload.capacities is only used by bolt levels");
  }
  if (errs.length) return errs;
  const rules = new SortRules(p as SortPayload);
  const counts = new Map<string, number>();
  for (const [i, t] of p.tubes.entries()) {
    if (!Array.isArray(t) || !t.every((c) => typeof c === "string" && c.length === 1 && !" .#?".includes(c))) {
      errs.push(`tubes[${i}] must be an array of single-character palette ids`);
      continue;
    }
    if (t.length > rules.caps[i]) errs.push(`tubes[${i}] holds ${t.length} layers but capacity is ${rules.caps[i]}`);
    for (const c of t) counts.set(c, (counts.get(c) ?? 0) + 1);
  }
  const maxCap = Math.max(...rules.caps);
  for (const [c, k] of counts) {
    if (mode === "liquid" && k !== maxCap) errs.push(`color ${c} appears ${k} times; liquid levels need exactly capacity (${maxCap})`);
    if (mode === "bolt" && k > maxCap) errs.push(`color ${c} appears ${k} times, more than any bolt can hold (${maxCap})`);
  }
  for (const h of p.hidden ?? []) {
    if (!Array.isArray(h) || h.length !== 2 || !isInt(h[0]) || !isInt(h[1]) || !p.tubes[h[0]] || h[1] < 0 || h[1] >= p.tubes[h[0]].length)
      errs.push(`hidden entry ${JSON.stringify(h)} is out of range`);
    else if (h[1] === p.tubes[h[0]].length - 1) errs.push(`hidden entry ${JSON.stringify(h)} is a top layer (tops are always revealed)`);
  }
  for (const l of p.locks ?? []) {
    if (!l || !isInt(l.tube) || l.tube < 0 || l.tube >= n || typeof l.color !== "string" || !counts.has(l.color)) errs.push(`bad lock ${JSON.stringify(l)}`);
    else if (p.tubes[l.tube].includes(l.color)) errs.push(`lock on tube ${l.tube} needs color ${l.color}, which sits inside that tube`);
  }
  for (const r of p.rusty ?? []) {
    if (!r || !isInt(r.bolt) || !isInt(r.index) || r.bolt < 0 || r.bolt >= n || r.index < 0 || r.index >= p.tubes[r.bolt].length || !counts.has(r.color))
      errs.push(`bad rusty entry ${JSON.stringify(r)}`);
    else if (p.hidden?.some((h) => h[0] === r.bolt && h[1] === r.index)) errs.push(`rusty nut ${JSON.stringify(r)} cannot also be hidden`);
  }
  for (const [i, m] of level.solution.entries()) {
    const mv = m as SortMove;
    if (!mv || typeof mv !== "object" || !isInt(mv.from) || !isInt(mv.to)) errs.push(`solution[${i}] must be {from:int,to:int}`);
  }
  if (errs.length === 0) {
    if (rules.isSolved(SortRules.initialState(p as SortPayload))) errs.push("level starts solved");
    const twists = new Set(level.twists);
    if ((p.hidden?.length ?? 0) > 0 && !twists.has("hidden")) errs.push('payload uses hidden layers but twists lacks "hidden"');
    if ((p.locks?.length ?? 0) > 0 && !twists.has("lock")) errs.push('payload uses locks but twists lacks "lock"');
    if ((p.rusty?.length ?? 0) > 0 && !twists.has("rusty")) errs.push('payload uses rusty nuts but twists lacks "rusty"');
    if (p.capacities && new Set(p.capacities).size > 1 && !twists.has("capped")) errs.push('payload uses per-bolt capacities but twists lacks "capped"');
  }
  return errs;
}
