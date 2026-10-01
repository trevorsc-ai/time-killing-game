/**
 * TypeScript mirror of the Puzzle Getaway JSON formats.
 * Canonical description: docs/level-format.md. Swift mirror: PuzzleGetaway/Core/Content.swift.
 * Keep all three in sync.
 */

/** Playable puzzle modes shipped to players. */
export type ModeId = "liquid" | "bolt" | "pixel" | "parking" | "pipe";
/** `demo` is a development-only placeholder mode (destination "demo"). */
export type LevelMode = ModeId | "demo";

export const MODE_IDS: readonly ModeId[] = ["liquid", "bolt", "pixel", "parking", "pipe"];

/** A single puzzle. `payload` and `solution` entries are mode-specific JSON. */
export interface LevelEnvelope<P = unknown, M = unknown> {
  /** Unique across the whole bundle. Levels: `<destination>-<mode>-<NN>`; pool entries: `<pool>-<NNN>`. */
  id: string;
  mode: LevelMode | string;
  /** Destination id (d1..d8, "demo") for levels; the pool name for pool entries. */
  destination: string;
  /** 1-based position within its destination (or pool). See ORDER_TABLE. */
  order: number;
  title: string;
  /** 1 (gentle) .. 10 (hardest). */
  difficulty: number;
  /** Optional tutorial key; the shell shows the matching tip card. */
  tutorial?: string;
  /** Names of twists (mode specific) used for first-time tip cards. */
  twists: string[];
  /** Optimal (or best-known) move count. Invariant: 1 <= par <= solution.length. */
  par: number;
  /** A verified full solution, as an ordered list of mode-specific moves. */
  solution: M[];
  payload: P;
}

/** One file per destination + mode: Resources/Levels/<destination>-<mode>.json */
export interface LevelFile {
  destination: string;
  mode: LevelMode | string;
  levels: LevelEnvelope[];
}

/** Resources/Pools/<pool>.json */
export interface PoolFile {
  pool: string;
  entries: LevelEnvelope[];
}

export interface PaletteColor {
  /** Single character key. Pixel-art grids and level payloads refer to colors by this key. */
  id: string;
  name: string;
  hex: string;
  highContrastHex: string;
  /** SF Symbol used as the accessibility pattern for this color. */
  symbol: string;
}

export interface PaletteFile {
  colors: PaletteColor[];
}

export interface RestorationStage {
  id: string;
  title: string;
  starsRequired: number;
  scrapbookArtId: string;
}

export interface DestinationTheme {
  primary: string;
  secondary: string;
  accent: string;
  background: string;
}

export interface Destination {
  id: string;
  name: string;
  tagline: string;
  intro: string;
  theme: DestinationTheme;
  comingSoon: boolean;
  restorationTitle: string;
  restorationStages: RestorationStage[];
}

export interface DestinationsFile {
  /** Percent of the previous destination's levels that must be completed to unlock the next. */
  unlockPercent: number;
  destinations: Destination[];
}

/**
 * Pre-assigned level orders per destination (mode -> orders). Parallel agents must
 * use exactly these slots. Dest 1 interleaves three modes.
 */
export const ORDER_TABLE: Record<string, Record<string, number[]>> = {
  d1: {
    liquid: [1, 3, 5, 7, 9, 11, 13, 15, 18, 21],
    pixel: [2, 4, 6, 8, 10, 12, 14, 17, 20, 23],
    bolt: [16, 19, 22, 24, 25],
  },
  d2: { bolt: [1, 2, 3, 4, 5] },
  d3: { parking: [1, 2, 3, 4, 5, 6] },
  d4: { pipe: [1, 2, 3, 4, 5, 6] },
};
