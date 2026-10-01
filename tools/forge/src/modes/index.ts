import type { ModeHandlers } from "./types.js";
import { demo } from "./demo.js";
// === MODE IMPORTS: add one line per mode (expect merge conflicts here; keep one per line) ===
// import { liquid } from "./liquid/index.js";
// === END MODE IMPORTS ===

/**
 * Mode registry. To add a mode: import its ModeHandlers above and add ONE line to the array below.
 */
export const MODE_HANDLERS: ModeHandlers[] = [
  demo,
  // === MODE REGISTRATIONS: one per line, trailing comma ===
  // liquid,
  // === END MODE REGISTRATIONS ===
];

export const MODES: Record<string, ModeHandlers> = Object.fromEntries(MODE_HANDLERS.map((h) => [h.mode, h]));
