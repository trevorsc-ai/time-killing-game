/**
 * Original procedural pixel patterns (quilts, tile mosaics, bullseyes, stained glass, tiny icons) used to fill the
 * Relax pool. Everything derives from a seeded Rng, so regenerating produces identical scenes.
 */
import type { Rng } from "../../../util/prng.js";

export const ALL_COLORS = "roygtbipknws".split("");

export interface PatternScene {
  kind: string;
  title: string;
  rows: string[];
}

function blank(w: number, h: number, fill = "."): string[][] {
  return Array.from({ length: h }, () => Array.from({ length: w }, () => fill));
}

function toRows(g: string[][]): string[] {
  return g.map((r) => r.join(""));
}

export function pickColors(rng: Rng, k: number): string[] {
  return rng.shuffle(ALL_COLORS).slice(0, k);
}

/** Nested rectangular rings, a "log cabin" quilt. */
export function quilt(rng: Rng, w: number, h: number, k: number): PatternScene {
  const colors = pickColors(rng, k);
  const g = blank(w, h);
  const thick = rng.int(2) === 0 ? 1 : 2;
  const layers = Math.ceil(Math.min(w, h) / 2 / thick);
  let prev = -1;
  for (let l = 0; l < layers; l++) {
    let c = rng.int(k);
    if (c === prev) c = (c + 1) % k;
    prev = c;
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const d = Math.min(x, y, w - 1 - x, h - 1 - y);
        if (Math.floor(d / thick) === l) g[y]![x] = colors[c]!;
      }
  }
  return { kind: "quilt", title: "Picnic Quilt", rows: toRows(g) };
}

/** Diamond tiles. */
export function diamonds(rng: Rng, w: number, h: number, k: number): PatternScene {
  const colors = pickColors(rng, k);
  const g = blank(w, h);
  const cx = (w - 1) / 2;
  const cy = (h - 1) / 2;
  const period = 2 + rng.int(2);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const d = Math.abs(x - cx) + Math.abs(y - cy);
      g[y]![x] = colors[Math.floor(d / period) % k]!;
    }
  return { kind: "diamonds", title: "Garden Tiles", rows: toRows(g) };
}

/** Concentric round ripples inside a round silhouette (transparent corners). */
export function bullseye(rng: Rng, w: number, h: number, k: number): PatternScene {
  const colors = pickColors(rng, k);
  const g = blank(w, h);
  const cx = (w - 1) / 2;
  const cy = (h - 1) / 2;
  const rmax = Math.min(w, h) / 2;
  const band = 1.2 + rng.next() * 0.8;
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const d = Math.hypot(x - cx, y - cy);
      if (d <= rmax) g[y]![x] = colors[Math.floor(d / band) % k]!;
    }
  return { kind: "bullseye", title: "Lantern Ripples", rows: toRows(g) };
}

/** Diagonal candy stripes with a plain border (the border hides the stripes from the edge). */
export function stripes(rng: Rng, w: number, h: number, k: number): PatternScene {
  const colors = pickColors(rng, k + 1);
  const g = blank(w, h);
  const width = 1 + rng.int(2);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      const border = x === 0 || y === 0 || x === w - 1 || y === h - 1;
      g[y]![x] = border ? colors[k]! : colors[Math.floor((x + y) / width) % k]!;
    }
  return { kind: "stripes", title: "Candy Wrapper", rows: toRows(g) };
}

/** Stained-glass mosaic: nearest-seed regions, each seed gets a color (colors repeat, so regions are separate). */
export function mosaic(rng: Rng, w: number, h: number, k: number): PatternScene {
  const colors = pickColors(rng, k);
  const seeds = Math.max(k + 2, Math.round((w * h) / 18));
  const pts: { x: number; y: number; c: string }[] = [];
  for (let i = 0; i < seeds; i++) pts.push({ x: rng.int(w), y: rng.int(h), c: colors[i % k]! });
  const g = blank(w, h);
  for (let y = 0; y < h; y++)
    for (let x = 0; x < w; x++) {
      let best = Infinity;
      let col = colors[0]!;
      for (const p of pts) {
        const d = Math.abs(p.x - x) + Math.abs(p.y - y) + 0.01 * (p.x * 7 + p.y);
        if (d < best) {
          best = d;
          col = p.c;
        }
      }
      g[y]![x] = col;
    }
  return { kind: "mosaic", title: "Lantern Mosaic", rows: toRows(g) };
}

/** Pinwheel: four rotated triangles in a bordered square. */
export function pinwheel(rng: Rng, w: number, h: number, k: number): PatternScene {
  const n = Math.min(w, h);
  const colors = pickColors(rng, Math.max(3, k));
  const g = blank(n, n);
  const c = (n - 1) / 2;
  for (let y = 0; y < n; y++)
    for (let x = 0; x < n; x++) {
      const dx = x - c;
      const dy = y - c;
      const quad = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 0 : 2) : dy > 0 ? 1 : 3;
      const ring = Math.min(x, y, n - 1 - x, n - 1 - y) === 0 ? colors[colors.length - 1]! : colors[quad % (colors.length - 1)]!;
      g[y]![x] = ring;
    }
  return { kind: "pinwheel", title: "Windmill Tile", rows: toRows(g) };
}

/** Tiny hand-drawn icons. `a`..`d` are placeholders replaced by random distinct palette colors. */
const ICONS: { title: string; rows: string[] }[] = [
  { title: "Heart Cookie", rows: [".aa..aa.", "aaaaaaaa", "abaaaaaa", "aaaaaaaa", ".aaaaaa.", "..aaaa..", "...aa..."] },
  { title: "Little Star", rows: ["....a....", "....a....", "...aaa...", "aaaabaaaa", ".aaaaaaa.", "..aaaaa..", "..aa.aa..", ".aa...aa."] },
  { title: "Paper Boat", rows: ["....a....", "....aa...", "...aaa...", "..aaaaa..", "....c....", "bbbbbbbbb", ".bbbbbbb.", "..bbbbb.."] },
  { title: "Garden Flower", rows: ["..aaa..", ".aabaa.", ".abbba.", ".aabaa.", "..aaa..", "...c...", "..cc...", "..c.cc.", "ccc.cc."] },
  { title: "Mushroom Hut", rows: ["..aaaaa..", ".aabaabaa", "aaaaaaaaa", "aabaaabaa", "...ccc...", "...ccc...", "...ccc...", "..ccccc.."] },
  { title: "Balloon Bunch", rows: [".aa..bb.", "aaaabbbb", "aaaabbbb", ".aa..bb.", "..d..d..", "...dd...", "....d...", "...dd..."] },
  { title: "Cherry Pair", rows: ["....cc..", "...c.cc.", "..c...c.", ".c.....c", "aa.....bb", "aaa...bbb", "aaa...bbb", ".a.....b."] },
  { title: "Cozy House", rows: ["...aa...", "..aaaa..", ".aaaaaa.", "aaaaaaaa", ".bbbbbb.", ".bcbbcb.", ".bbbdbb.", ".bbbdbb."] },
  { title: "Tiny Fish", rows: ["..aaa....a", ".aaaaa..aa", "aabaaaaaaa", ".aaaaa..aa", "..aaa....a"] },
  { title: "Teacup", rows: [".c..c....", "..c..c...", "aaaaaaaa.", "abbbbbba.", "abbbbbbaa", "abbbbbba.a", ".abbbba..a", "..aaaa.aa", "aaaaaaaa."] },
];

export function icon(rng: Rng, index: number, pad: number): PatternScene {
  const def = ICONS[index % ICONS.length]!;
  const cols = pickColors(rng, 4);
  const mw = Math.max(...def.rows.map((r) => r.length));
  const w = mw + pad * 2;
  const h = def.rows.length + pad * 2;
  const g = blank(w, h);
  const map: Record<string, string> = { a: cols[0]!, b: cols[1]!, c: cols[2]!, d: cols[3]! };
  def.rows.forEach((r, y) => [...r].forEach((ch, x) => { if (ch !== ".") g[y + pad]![x + pad] = map[ch] ?? ch; }));
  // Frame the icon in a plain tile so there is something to peel (when padded).
  if (pad > 0) {
    const frame = cols[3]!;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (g[y]![x] === ".") g[y]![x] = frame;
  }
  return { kind: "icon", title: def.title, rows: toRows(g) };
}

export const ICON_COUNT = ICONS.length;
