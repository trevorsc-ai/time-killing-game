// Generates a placeholder 1024x1024 app icon: warm gradient with a lantern glow.
// Usage: npx tsx scripts/make-appicon.ts
import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { writePng } from "../src/util/png.js";

const N = 1024;
const px = new Uint8Array(N * N * 4);
for (let y = 0; y < N; y++) {
  for (let x = 0; x < N; x++) {
    const t = y / N;
    let r = 255 * (1 - t) + 93 * t;
    let g = 190 * (1 - t) + 169 * t;
    let b = 120 * (1 - t) + 232 * t;
    const d = Math.hypot(x - 512, y - 480);
    if (d < 230) {
      const k = Math.max(0, 1 - d / 230);
      r = r + (255 - r) * (0.55 + 0.45 * k);
      g = g + (244 - g) * (0.55 + 0.45 * k);
      b = b + (190 - b) * (0.55 + 0.45 * k);
    }
    if (Math.abs(x - 512) < 14 && y > 690 && y < 860) {
      r = 70; g = 60; b = 90;
    }
    const o = (y * N + x) * 4;
    px[o] = r; px[o + 1] = g; px[o + 2] = b; px[o + 3] = 255;
  }
}
const out = resolve(dirname(fileURLToPath(import.meta.url)), "../../../PuzzleGetaway/Assets.xcassets/AppIcon.appiconset");
mkdirSync(out, { recursive: true });
writePng(`${out}/icon-1024.png`, N, N, px);
