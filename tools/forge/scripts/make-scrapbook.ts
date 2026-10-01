// Generates the scrapbook pixel illustrations: PuzzleGetaway/Resources/Art/scrapbook/<id>.json
// Usage: npx tsx scripts/make-scrapbook.ts [--preview <dir>]
//
// Each piece is drawn on a small char grid with a handful of primitives, then outlined. The JSON files are the
// source of truth for the app (format: docs/level-format.md, "Scrapbook art"); this script only authors them.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { renderCharGrid } from "../src/util/png.js";
import { SCRAPBOOK_EXTRA_PALETTE } from "../src/scrapbook.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const RESOURCES = resolve(HERE, "../../../PuzzleGetaway/Resources");
const OUT = join(RESOURCES, "Art", "scrapbook");

const W = 32;
const H = 32;

class Grid {
  cells: string[][];
  constructor(public w = W, public h = H) {
    this.cells = Array.from({ length: h }, () => Array.from({ length: w }, () => "."));
  }
  set(x: number, y: number, c: string): void {
    x = Math.round(x);
    y = Math.round(y);
    if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.cells[y]![x] = c;
  }
  get(x: number, y: number): string {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return ".";
    return this.cells[y]![x]!;
  }
  rect(x: number, y: number, w: number, h: number, c: string): void {
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) this.set(x + i, y + j, c);
  }
  /** Rectangle with the four corner pixels removed (a soft, rounded look). */
  rrect(x: number, y: number, w: number, h: number, c: string): void {
    this.rect(x, y, w, h, c);
    for (const [cx, cy] of [[x, y], [x + w - 1, y], [x, y + h - 1], [x + w - 1, y + h - 1]] as [number, number][]) this.set(cx, cy, ".");
  }
  hline(x0: number, x1: number, y: number, c: string): void {
    for (let x = x0; x <= x1; x++) this.set(x, y, c);
  }
  vline(x: number, y0: number, y1: number, c: string): void {
    for (let y = y0; y <= y1; y++) this.set(x, y, c);
  }
  disc(cx: number, cy: number, r: number, c: string): void {
    for (let y = Math.floor(cy - r); y <= Math.ceil(cy + r); y++)
      for (let x = Math.floor(cx - r); x <= Math.ceil(cx + r); x++) {
        const dx = x - cx;
        const dy = y - cy;
        if (dx * dx + dy * dy <= r * r + 0.4) this.set(x, y, c);
      }
  }
  line(x0: number, y0: number, x1: number, y1: number, c: string): void {
    const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
    for (let i = 0; i <= steps; i++) {
      const t = steps === 0 ? 0 : i / steps;
      this.set(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c);
    }
  }
  poly(pts: [number, number][], c: string): void {
    const ys = pts.map((p) => p[1]);
    const y0 = Math.min(...ys);
    const y1 = Math.max(...ys);
    for (let y = y0; y <= y1; y++) {
      const xs: number[] = [];
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i]!;
        const b = pts[(i + 1) % pts.length]!;
        if ((a[1] <= y && b[1] > y) || (b[1] <= y && a[1] > y)) {
          xs.push(a[0] + ((y - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
        }
      }
      xs.sort((p, q) => p - q);
      for (let k = 0; k + 1 < xs.length; k += 2) this.hline(Math.round(xs[k]!), Math.round(xs[k + 1]!) - 1, y, c);
    }
  }
  plus(cx: number, cy: number, c: string, center = c): void {
    this.set(cx, cy, center);
    this.set(cx - 1, cy, c);
    this.set(cx + 1, cy, c);
    this.set(cx, cy - 1, c);
    this.set(cx, cy + 1, c);
  }
  /** Surround every non-empty pixel with an outline color (8-neighborhood would be too heavy: use 4). */
  outline(c = "d"): void {
    const add: [number, number][] = [];
    for (let y = 0; y < this.h; y++)
      for (let x = 0; x < this.w; x++) {
        if (this.get(x, y) !== ".") continue;
        if (this.get(x - 1, y) !== "." || this.get(x + 1, y) !== "." || this.get(x, y - 1) !== "." || this.get(x, y + 1) !== ".") add.push([x, y]);
      }
    for (const [x, y] of add) this.set(x, y, c);
  }
  rows(): string[] {
    return this.cells.map((r) => r.join(""));
  }
}

interface Piece {
  id: string;
  title: string;
  caption: string;
  draw: (g: Grid) => void;
  /** Drawn after the outline, on empty cells only (soft glows). */
  post?: (g: Grid) => void;
  outline?: boolean;
}

// ---- shared sub-drawings ----------------------------------------------------------------------------------------

function wheel(g: Grid, cx: number, cy: number, r = 3): void {
  g.disc(cx, cy, r, "d");
  g.disc(cx, cy, r - 1, "s");
  g.set(cx, cy, "c");
}

function awning(g: Grid, x0: number, x1: number, y: number, hgt = 7, a = "r", b = "c"): void {
  g.rect(x0 - 1, y - 2, x1 - x0 + 3, 2, "R");
  for (let x = x0; x <= x1; x++) {
    const stripe = Math.floor((x - x0) / 4) % 2 === 0 ? a : b;
    g.vline(x, y, y + hgt - 1, stripe);
  }
  // scalloped edge
  for (let s = 0; s * 4 + x0 <= x1; s++) {
    const col = s % 2 === 0 ? a : b;
    const sx = x0 + s * 4;
    g.hline(sx, Math.min(sx + 3, x1), y + hgt, col);
    g.hline(sx + 1, Math.min(sx + 2, x1), y + hgt + 1, col);
  }
}

function jar(g: Grid, x: number, y: number, c: string): void {
  g.rect(x, y + 1, 3, 3, c);
  g.set(x, y, "c");
  g.set(x + 2, y, "c");
  g.set(x, y + 1, "h");
}

function sparkle(g: Grid, x: number, y: number, c = "y"): void {
  g.plus(x, y, c, "h");
}

// ---- d1: Station Snack Cart -------------------------------------------------------------------------------------

const d1s1: Piece = {
  id: "d1-stage1",
  title: "A Good Sweep",
  caption: "Out with the dust, in with the sparkle. The Pals gave the old cart a proper sweep and found a shiny floor underneath.",
  draw: (g) => {
    // floor sparkle line
    g.hline(2, 29, 29, "l");
    // broom handle
    for (let i = 0; i < 18; i++) {
      g.set(24 - i * 0.62, 3 + i, "n");
      g.set(25 - i * 0.62, 3 + i, "m");
    }
    g.rect(11, 20, 7, 2, "r");
    g.hline(11, 17, 20, "R");
    // bristles
    g.poly([[8, 22], [19, 22], [21, 29], [6, 29]], "y");
    for (const x of [9, 12, 15, 18]) g.vline(x, 24, 28, "o");
    g.hline(7, 20, 28, "o");
    // little dust bunnies being swept away
    g.disc(25, 27, 1.6, "u");
    g.disc(28, 26, 1, "u");
    g.set(22, 28, "u");
    sparkle(g, 6, 7);
    sparkle(g, 26, 12, "c");
    sparkle(g, 10, 15, "c");
    g.set(4, 4, "y");
    g.set(28, 20, "y");
  },
};

const d1s2: Piece = {
  id: "d1-stage2",
  title: "Fresh Paint",
  caption: "Coral red, straight from the pot. One brushstroke and the whole cart looked ten years younger.",
  draw: (g) => {
    // swatch of fresh paint on a board
    g.rect(2, 4, 16, 8, "c");
    g.rect(2, 4, 16, 4, "r");
    g.rect(2, 8, 16, 4, "o");
    g.hline(3, 16, 5, "k");
    // pot
    g.rrect(8, 17, 15, 11, "w");
    g.rect(8, 17, 15, 2, "u");
    g.rect(9, 14, 13, 4, "r");
    g.hline(10, 20, 14, "k");
    g.vline(12, 19, 22, "r");
    g.vline(18, 19, 24, "r");
    g.set(12, 23, "r");
    g.set(18, 25, "r");
    g.rect(8, 22, 15, 2, "e");
    g.hline(10, 11, 20, "h");
    // brush
    g.line(25, 3, 20, 12, "n");
    g.line(26, 3, 21, 12, "m");
    g.rect(19, 12, 4, 2, "e");
    g.rect(19, 14, 4, 2, "r");
    sparkle(g, 27, 18, "y");
    sparkle(g, 4, 20, "y");
  },
};

const d1s3: Piece = {
  id: "d1-stage3",
  title: "Striped Awning",
  caption: "Red and cream stripes, scalloped just so. It keeps off the rain and invites everyone in for a treat.",
  draw: (g) => {
    g.rect(4, 14, 24, 10, "l");
    awning(g, 3, 28, 6, 8);
    // posts
    g.vline(3, 16, 29, "m");
    g.vline(28, 16, 29, "m");
    // counter
    g.rect(2, 23, 28, 2, "l");
    g.rect(3, 25, 26, 5, "n");
    g.hline(4, 27, 26, "N");
    // treats on the counter
    g.rect(6, 20, 4, 3, "w");
    g.hline(6, 9, 20, "h");
    g.disc(14, 21, 1.8, "k");
    g.set(14, 21, "c");
    g.disc(19, 21, 1.8, "y");
    g.set(19, 21, "c");
    g.rrect(23, 19, 4, 4, "b");
    // lantern string lights under the scallops
    for (const x of [6, 11, 16, 21, 26]) g.set(x, 17, x % 2 === 0 ? "y" : "k");
  },
};

const d1s4: Piece = {
  id: "d1-stage4",
  title: "Warm Lanterns",
  caption: "When the lanterns came on, the whole platform glowed honey-gold. Even the pigeons stopped to look.",
  draw: (g) => {
    // hook and ring
    g.vline(16, 1, 4, "N");
    g.set(15, 2, "N");
    g.set(17, 2, "N");
    // cap
    g.poly([[11, 8], [21, 8], [19, 5], [13, 5]], "N");
    g.hline(10, 22, 9, "N");
    // glass
    g.rrect(11, 10, 11, 15, "y");
    g.rrect(13, 12, 7, 11, "Y");
    g.rrect(14, 14, 5, 7, "c");
    g.vline(16, 10, 24, "O");
    g.set(12, 11, "c");
    // base
    g.hline(10, 22, 25, "N");
    g.rect(12, 26, 9, 2, "N");
    g.set(16, 28, "N");
  },
  post: (g) => {
    for (let y = 1; y < 31; y++)
      for (let x = 1; x < 31; x++) {
        const d = Math.hypot(x - 16, y - 16);
        if (d > 9.5 && d < 14 && (x + y) % 2 === 0 && g.get(x, y) === ".") g.set(x, y, "Y");
      }
  },
};

const d1s5: Piece = {
  id: "d1-stage5",
  title: "Stocked Shelves",
  caption: "Teapot on the top shelf, jam tarts below. The tea cart is ready for the very first customer of the day.",
  draw: (g) => {
    // handle bar
    g.vline(28, 6, 24, "n");
    g.hline(25, 28, 6, "n");
    // frame
    g.rect(4, 5, 2, 22, "n");
    g.rect(24, 5, 2, 22, "n");
    // top shelf
    g.rect(3, 15, 24, 2, "l");
    g.hline(3, 26, 17, "m");
    // bottom shelf
    g.rect(3, 24, 24, 2, "l");
    g.hline(3, 26, 26, "m");
    // teapot
    g.rrect(8, 8, 8, 7, "b");
    g.hline(9, 14, 8, "B");
    g.rect(11, 6, 2, 2, "B");
    g.rect(16, 10, 2, 2, "b");
    g.set(18, 9, "b");
    g.line(8, 10, 6, 9, "b");
    g.rect(9, 10, 2, 2, "h");
    // cups
    g.rect(19, 12, 4, 3, "w");
    g.set(23, 13, "w");
    g.rect(19, 12, 4, 1, "k");
    // cake stand
    g.rect(8, 22, 9, 1, "c");
    g.disc(10, 21, 1.5, "k");
    g.disc(14, 21, 1.5, "y");
    // jam jars
    jar(g, 20, 20, "r");
    jar(g, 23, 20, "p");
    // wheels
    wheel(g, 8, 29, 2.6);
    wheel(g, 22, 29, 2.6);
  },
};

const d1s6: Piece = {
  id: "d1-stage6",
  title: "Grand Reopening",
  caption: "Bunting up, kettle on, doors open. The Station Snack Cart is back, and the first treat is on the house.",
  draw: (g) => {
    // bunting
    g.hline(1, 30, 3, "d");
    const flags = ["k", "y", "b", "g", "o", "p"];
    for (let i = 0; i < 6; i++) {
      const x = 3 + i * 5;
      g.poly([[x - 1, 4], [x + 3, 4], [x + 1, 8]], flags[i]!);
    }
    g.rect(5, 16, 22, 8, "l");
    awning(g, 4, 27, 11, 5);
    g.vline(4, 18, 27, "m");
    g.vline(27, 18, 27, "m");
    // cart body
    g.rrect(3, 22, 26, 7, "o");
    g.hline(4, 27, 23, "y");
    g.rect(8, 24, 16, 3, "R");
    g.hline(9, 23, 25, "c");
    // steam from a teapot on the counter
    g.rrect(20, 19, 5, 4, "b");
    g.set(21, 17, "h");
    g.set(22, 15, "h");
    g.set(21, 13, "h");
    g.rrect(8, 20, 8, 2, "c");
    g.disc(10, 19.5, 1.2, "k");
    g.disc(14, 19.5, 1.2, "y");
    wheel(g, 8, 30, 2);
    wheel(g, 24, 30, 2);
    sparkle(g, 2, 14);
    sparkle(g, 29, 9, "c");
    sparkle(g, 30, 17);
  },
};

// ---- d2: Garden Express -----------------------------------------------------------------------------------------

const d2s1: Piece = {
  id: "d2-stage1",
  title: "Open the Windows",
  caption: "Shutters wide, fresh air rushing in. The seedlings stretched toward the sunshine like they'd been waiting all year.",
  draw: (g) => {
    // frame
    g.rect(6, 4, 20, 22, "c");
    // view: sky, sun, hill
    g.rect(8, 6, 16, 18, "a");
    g.rect(8, 6, 16, 6, "b");
    g.disc(20, 11, 2.6, "y");
    g.poly([[8, 24], [8, 17], [14, 15], [24, 19], [24, 24]], "g");
    g.hline(8, 24, 22, "G");
    // cross bars
    g.vline(16, 6, 23, "c");
    g.hline(8, 23, 14, "c");
    // shutters swung open
    g.rect(1, 5, 5, 20, "g");
    g.rect(26, 5, 5, 20, "g");
    for (const y of [8, 11, 14, 17, 20, 23]) {
      g.hline(2, 4, y, "G");
      g.hline(27, 29, y, "G");
    }
    // sill and pot
    g.rect(4, 26, 24, 2, "l");
    g.rrect(12, 23, 5, 3, "x");
    g.vline(14, 20, 22, "G");
    g.set(13, 20, "g");
    g.set(15, 19, "g");
    g.hline(5, 6, 27, "m");
    sparkle(g, 4, 1, "y");
  },
};

const d2s2: Piece = {
  id: "d2-stage2",
  title: "Fresh Soil",
  caption: "Dark, soft, and ready. A few green sprouts poked up the very same afternoon.",
  draw: (g) => {
    // box
    g.rect(3, 17, 26, 11, "n");
    for (const x of [8, 14, 20, 26]) g.vline(x, 18, 27, "N");
    g.hline(3, 28, 17, "m");
    g.rect(2, 16, 28, 2, "l");
    // soil heap
    g.rect(4, 14, 24, 3, "N");
    g.hline(6, 25, 13, "N");
    for (const [x, y] of [[8, 15], [14, 14], [21, 15], [25, 14], [11, 16]] as [number, number][]) g.set(x, y, "m");
    // sprouts
    for (const x of [9, 16, 23]) {
      g.vline(x, 8, 12, "g");
      g.set(x - 1, 8, "g");
      g.set(x - 2, 7, "g");
      g.set(x + 1, 9, "g");
      g.set(x + 2, 8, "g");
      g.set(x - 1, 9, "G");
    }
    // water drops
    g.set(6, 3, "b");
    g.set(6, 4, "b");
    g.set(12, 1, "a");
    g.set(12, 2, "b");
    g.set(26, 4, "b");
    g.set(26, 5, "b");
    // trowel
    g.line(28, 26, 31, 22, "s");
    g.set(31, 21, "n");
  },
};

const d2s3: Piece = {
  id: "d2-stage3",
  title: "In Full Bloom",
  caption: "Poppies, daisies, and one very confident sunflower. The greenhouse car smells like a summer morning.",
  draw: (g) => {
    // box
    g.rect(3, 22, 26, 8, "n");
    for (const x of [8, 14, 20, 26]) g.vline(x, 23, 29, "N");
    g.rect(2, 21, 28, 2, "l");
    const flowers: [number, number, string, number][] = [
      [8, 10, "k", 3], [16, 6, "y", 4], [24, 11, "p", 3],
    ];
    for (const [x, y, col, r] of flowers) {
      g.vline(x, y, 21, "G");
      g.set(x - 1, y + 7, "g");
      g.set(x - 2, y + 6, "g");
      g.set(x + 1, y + 9, "g");
      g.set(x + 2, y + 8, "g");
      for (let k = 0; k < 8; k++) {
        const a = (k * Math.PI) / 4;
        g.set(x + Math.cos(a) * r, y + Math.sin(a) * r, col);
      }
      g.disc(x, y, 1.5, col === "y" ? "n" : "y");
    }
    g.disc(12, 17, 1.2, "r");
    g.disc(20, 16, 1.2, "o");
    g.vline(12, 18, 21, "G");
    g.vline(20, 17, 21, "G");
    // butterfly
    g.set(26, 3, "b");
    g.set(28, 3, "b");
    g.set(27, 4, "d");
    g.set(26, 5, "i");
    g.set(28, 5, "i");
  },
};

// ---- d3: Baggage Bay --------------------------------------------------------------------------------------------

function suitcase(g: Grid, x: number, y: number, w: number, h: number, body: string, strap: string, brass = false): void {
  g.rrect(x, y, w, h, body);
  g.vline(x + 2, y, y + h - 1, strap);
  g.vline(x + w - 3, y, y + h - 1, strap);
  g.rect(x + Math.floor(w / 2) - 1, y - 2, 3, 2, brass ? "e" : "m");
  g.set(x + 1, y + 1, "h");
  if (brass) {
    for (const [cx, cy] of [[x, y], [x + w - 1, y], [x, y + h - 1], [x + w - 1, y + h - 1]] as [number, number][]) g.set(cx, cy, "e");
    g.rect(x + Math.floor(w / 2) - 1, y + Math.floor(h / 2), 3, 2, "e");
  }
}

const d3s1: Piece = {
  id: "d3-stage1",
  title: "Clear the Aisle",
  caption: "Two tidy suitcases, one clear path, and not a single trip hazard. The porter did a little happy shuffle.",
  draw: (g) => {
    // floor with aisle stripe
    g.rect(1, 25, 30, 5, "l");
    for (const x of [3, 9, 15, 21, 27]) g.hline(x, x + 2, 28, "y");
    suitcase(g, 4, 12, 11, 13, "s", "d");
    g.rect(5, 17, 9, 2, "i");
    suitcase(g, 18, 15, 10, 10, "n", "N");
    g.rect(19, 20, 8, 2, "o");
    // little arrow pointing along the aisle
    g.poly([[27, 27], [30, 28.5], [27, 30]], "y");
    sparkle(g, 8, 6, "y");
    sparkle(g, 24, 8, "c");
  },
};

const d3s2: Piece = {
  id: "d3-stage2",
  title: "Label the Shelves",
  caption: "Every crate has a name now: Hats, Hampers, and Things That Clink. Finding anything takes about two seconds.",
  draw: (g) => {
    // posts
    g.rect(2, 3, 2, 27, "m");
    g.rect(28, 3, 2, 27, "m");
    // shelves
    for (const y of [12, 21, 30]) g.rect(2, y, 28, 2, "l");
    const cols = ["b", "k", "g", "o", "p", "t"];
    // crates and labels
    for (let row = 0; row < 3; row++) {
      for (let i = 0; i < 3; i++) {
        const x = 5 + i * 8;
        const y = 3 + row * 9;
        g.rect(x, y, 7, 8, "n");
        g.rect(x, y + 2, 7, 1, "N");
        g.rect(x + 1, y + 3, 5, 3, "c");
        g.set(x + 2, y + 4, cols[(row * 3 + i) % 6]!);
        g.hline(x + 3, x + 4, y + 4, "d");
      }
    }
  },
};

const d3s3: Piece = {
  id: "d3-stage3",
  title: "Brass and Polish",
  caption: "The old trolley gleams like a trumpet. Three suitcases ride in style, with brass corners to match.",
  draw: (g) => {
    // trolley frame
    g.rect(3, 24, 22, 2, "e");
    g.vline(26, 6, 24, "e");
    g.hline(24, 29, 6, "e");
    g.set(29, 7, "e");
    // luggage
    suitcase(g, 5, 16, 14, 8, "r", "R", true);
    suitcase(g, 7, 9, 10, 7, "b", "B", true);
    suitcase(g, 18, 18, 7, 6, "g", "G", true);
    // wheels
    wheel(g, 7, 29, 2.6);
    wheel(g, 22, 29, 2.6);
    g.set(7, 29, "e");
    g.set(22, 29, "e");
    sparkle(g, 3, 8);
    sparkle(g, 29, 18, "c");
    sparkle(g, 14, 3, "c");
  },
};

// ---- d4: Rainy Platform -----------------------------------------------------------------------------------------

const d4s1: Piece = {
  id: "d4-stage1",
  title: "Patch the Roof",
  caption: "One orange patch, five careful stitches. The first drops hit it and rolled right off.",
  draw: (g) => {
    // roof
    g.poly([[2, 18], [16, 6], [30, 18]], "u");
    g.hline(3, 28, 18, "s");
    g.hline(2, 29, 19, "s");
    // tile rows
    g.hline(8, 24, 12, "s");
    g.hline(5, 27, 15, "s");
    // patch
    g.rect(12, 11, 8, 6, "o");
    g.hline(12, 19, 11, "O");
    for (const x of [13, 15, 17, 19]) g.set(x, 12, "c");
    for (const x of [13, 15, 17, 19]) g.set(x, 16, "c");
    // posts
    g.vline(5, 20, 29, "m");
    g.vline(26, 20, 29, "m");
    g.hline(2, 29, 29, "s");
    // rain
    for (const [x, y] of [[2, 3], [8, 6], [24, 4], [29, 8], [12, 2], [20, 7], [4, 11]] as [number, number][]) {
      g.set(x, y, "b");
      g.set(x - 1, y + 1, "a");
    }
  },
};

const d4s2: Piece = {
  id: "d4-stage2",
  title: "Flowing Gutters",
  caption: "Plink, plink, whoosh! The rain follows the pipe all the way down to the old barrel, just as planned.",
  draw: (g) => {
    // gutter
    g.rect(1, 4, 20, 3, "b");
    g.hline(1, 20, 4, "a");
    g.hline(1, 20, 6, "B");
    // downpipe
    g.rect(18, 7, 3, 14, "b");
    g.vline(18, 7, 20, "a");
    g.rect(16, 20, 7, 2, "B");
    // water drops
    for (const [x, y] of [[19, 10], [19, 15], [11, 2], [5, 1], [15, 3]] as [number, number][]) g.set(x, y, "a");
    for (const [x, y] of [[20, 12], [19, 17]] as [number, number][]) g.set(x, y, "h");
    // barrel
    g.rrect(13, 22, 16, 8, "n");
    g.hline(13, 28, 24, "N");
    g.hline(13, 28, 28, "N");
    g.rect(14, 22, 14, 1, "b");
    g.set(19, 22, "h");
    g.set(23, 22, "a");
    // ripples
    g.hline(18, 20, 23, "a");
    // floor
    g.hline(1, 30, 30, "s");
    // little cloud
    g.rect(2, 11, 8, 3, "w");
    g.rect(4, 9, 4, 3, "w");
    g.rect(2, 14, 8, 1, "u");
  },
};

const d4s3: Piece = {
  id: "d4-stage3",
  title: "Window Boxes in Bloom",
  caption: "Rain on the glass, and a rainbow behind it. The window boxes are overflowing with color.",
  draw: (g) => {
    // frame
    g.rect(3, 3, 26, 21, "c");
    g.rect(5, 5, 22, 17, "a");
    g.vline(16, 5, 21, "c");
    g.hline(5, 26, 13, "c");
    // rainbow in the glass
    const arcs = ["r", "o", "y", "g", "b"];
    for (let i = 0; i < arcs.length; i++) {
      const rr = 8 - i;
      for (let a = 0; a <= 180; a += 6) {
        const rad = (a * Math.PI) / 180;
        g.set(21 - Math.cos(rad) * rr, 21 - Math.sin(rad) * rr, arcs[i]!);
      }
    }
    // window box
    g.rect(2, 24, 28, 6, "n");
    g.hline(2, 29, 24, "m");
    g.hline(3, 28, 28, "N");
    const cols = ["k", "y", "p", "r", "o", "k", "y"];
    for (let i = 0; i < 7; i++) {
      const x = 4 + i * 4;
      g.set(x, 22, "G");
      g.set(x, 23, "G");
      g.disc(x, 21, 1.2, cols[i]!);
      g.set(x, 21, "c");
    }
    // raindrops on the glass
    for (const [x, y] of [[8, 7], [11, 10], [24, 8], [19, 11]] as [number, number][]) g.set(x, y, "h");
  },
};

export const PIECES: Piece[] = [d1s1, d1s2, d1s3, d1s4, d1s5, d1s6, d2s1, d2s2, d2s3, d3s1, d3s2, d3s3, d4s1, d4s2, d4s3];

export function buildPiece(p: Piece): { id: string; title: string; caption: string; width: number; height: number; rows: string[]; palette: Record<string, string> } {
  const g = new Grid();
  p.draw(g);
  if (p.outline !== false) g.outline("d");
  if (p.post) p.post(g);
  const rows = g.rows();
  const used = new Set(rows.join(""));
  const palette: Record<string, string> = {};
  for (const [k, v] of Object.entries(SCRAPBOOK_EXTRA_PALETTE)) if (used.has(k)) palette[k] = v;
  return { id: p.id, title: p.title, caption: p.caption, width: W, height: H, rows, palette };
}

// CLI
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  mkdirSync(OUT, { recursive: true });
  const shared = JSON.parse(readFileSync(join(RESOURCES, "Art", "palette.json"), "utf8")) as { colors: { id: string; hex: string }[] };
  const colors: Record<string, string> = {};
  for (const c of shared.colors) colors[c.id] = c.hex;
  const previewIdx = process.argv.indexOf("--preview");
  const previewDir = previewIdx >= 0 ? resolve(process.argv[previewIdx + 1] ?? ".") : undefined;
  if (previewDir) mkdirSync(previewDir, { recursive: true });
  for (const p of PIECES) {
    const art = buildPiece(p);
    writeFileSync(join(OUT, `${art.id}.json`), JSON.stringify(art, null, 1) + "\n");
    if (previewDir) {
      // Preview on a cream card so transparent areas read like the app's background.
      const full = { ...colors, ...art.palette, ".": "#F7ECD9" };
      writeFileSync(join(previewDir, `${art.id}.png`), renderCharGrid(art.rows.map((r) => r.replace(/\./g, ".")), full, 12));
    }
  }
  console.log(`wrote ${PIECES.length} scrapbook pieces to ${OUT}`);
}
