import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { encodePng, hexToRgb } from "../../util/png.js";
import type { PaletteFile } from "../../schema.js";
import { SCENES } from "./art/scenes.js";
import { colorCounts } from "./rules.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const RES = resolve(HERE, "../../../../../PuzzleGetaway/Resources");

export function loadPaletteHex(): Record<string, string> {
  const pal = JSON.parse(readFileSync(join(RES, "Art/palette.json"), "utf8")) as PaletteFile;
  return Object.fromEntries(pal.colors.map((c) => [c.id, c.hex]));
}

/** Render a grid as bevelled blocks on a cream board (approximates the in-app look). */
export function renderBlocks(rows: string[], colors: Record<string, string>, scale = 24): Buffer {
  const h = rows.length;
  const w = rows[0]!.length;
  const pad = scale;
  const W = w * scale + pad * 2;
  const H = h * scale + pad * 2;
  const px = new Uint8Array(W * H * 4);
  const bg = hexToRgb("#E3D8C0");
  for (let i = 0; i < W * H; i++) {
    px[i * 4] = bg[0];
    px[i * 4 + 1] = bg[1];
    px[i * 4 + 2] = bg[2];
    px[i * 4 + 3] = 255;
  }
  const put = (x: number, y: number, rgb: [number, number, number]) => {
    const o = (y * W + x) * 4;
    px[o] = rgb[0];
    px[o + 1] = rgb[1];
    px[o + 2] = rgb[2];
  };
  const shade = (rgb: [number, number, number], f: number): [number, number, number] => [
    Math.max(0, Math.min(255, Math.round(rgb[0] * f))),
    Math.max(0, Math.min(255, Math.round(rgb[1] * f))),
    Math.max(0, Math.min(255, Math.round(rgb[2] * f))),
  ];
  for (let r = 0; r < h; r++) {
    for (let c = 0; c < w; c++) {
      const ch = rows[r]![c]!;
      if (ch === ".") {
        // faint checker so transparent cells are visible
        const tint: [number, number, number] = (r + c) % 2 === 0 ? [218, 208, 186] : [224, 214, 193];
        for (let y = 0; y < scale; y++) for (let x = 0; x < scale; x++) put(pad + c * scale + x, pad + r * scale + y, tint);
        continue;
      }
      const base: [number, number, number] = ch === "#" ? [120, 110, 104] : hexToRgb(colors[ch] ?? "#FF00FF");
      const gap = 1;
      for (let y = gap; y < scale - gap; y++) {
        for (let x = gap; x < scale - gap; x++) {
          let f = 1;
          if (y < 3 || x < 3) f = 1.1;
          if (y >= scale - 4 || x >= scale - 4) f = 0.86;
          put(pad + c * scale + x, pad + r * scale + y, shade(base, f));
        }
      }
    }
  }
  return encodePng(W, H, px);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const out = resolve(HERE, "../../../previews");
  mkdirSync(out, { recursive: true });
  const colors = loadPaletteHex();
  for (const s of SCENES) {
    const widths = new Set(s.rows.map((r) => r.length));
    if (widths.size !== 1) console.error(`${s.id}: ragged rows (widths ${[...widths].join(",")})`);
    const buf = renderBlocks(s.rows, colors);
    writeFileSync(join(out, `${s.id}.png`), buf);
    console.log(`${s.id}: ${s.rows[0]!.length}x${s.rows.length}`, JSON.stringify(colorCounts(s.rows)));
  }
}

