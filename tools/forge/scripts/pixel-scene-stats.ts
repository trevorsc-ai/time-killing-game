// Prints, per scene and color: pixel count, connected components, and how many components start with an exposed pixel.
import { SCENES } from "../src/modes/pixel/art/scenes.js";
import { initialState, isExposed } from "../src/modes/pixel/rules.js";

for (const s of SCENES) {
  const st = initialState({ grid: s.rows, slots: 3, lanes: [] });
  const seen = new Uint8Array(st.cells.length);
  const stats: Record<string, { px: number; comps: number; hidden: number }> = {};
  for (let i = 0; i < st.cells.length; i++) {
    const ch = String.fromCharCode(st.cells[i]!);
    if (ch === "." || ch === "#" || seen[i]) continue;
    const e = (stats[ch] ??= { px: 0, comps: 0, hidden: 0 });
    e.comps++;
    let exposed = false;
    const q = [i];
    seen[i] = 1;
    while (q.length) {
      const p = q.pop()!;
      e.px++;
      if (isExposed(st, p)) exposed = true;
      const r = Math.floor(p / st.w);
      const c = p % st.w;
      for (const [dr, dc] of [[1, 0], [-1, 0], [0, 1], [0, -1]] as const) {
        const nr = r + dr;
        const nc = c + dc;
        if (nr < 0 || nc < 0 || nr >= st.h || nc >= st.w) continue;
        const n = nr * st.w + nc;
        if (!seen[n] && st.cells[n] === st.cells[i]) {
          seen[n] = 1;
          q.push(n);
        }
      }
    }
    if (!exposed) e.hidden++;
  }
  console.log(`${s.id.padEnd(16)} ${s.rows[0]!.length}x${s.rows.length}  ` + Object.entries(stats).map(([k, v]) => `${k}:${v.px}/${v.comps}c/${v.hidden}h`).join("  "));
}
