# Puzzle Getaway

An offline-first iPhone and iPad puzzle collection set on the Lantern Line, a cozy workshop train served by the Parcel Pals. Five puzzle modes (Liquid, Bolt, Pixel Picnic, Baggage Jam, Flow Fix), restoration projects, a scrapbook, relaxed pools and a daily journey. SwiftUI + SpriteKit, iOS 16+, no ads, no accounts, no sound (haptics only).

## Features

- Five puzzle modes: Color Mixer (Liquid Sort), Tool Bench (Bolt Sort), Pixel Picnic, Baggage Jam, Flow Fix. Every mode has a first-level tutorial pointer, first-time tip cards for each twist, undo, restart, hints and a slim progress line in the HUD.
- Campaign: Station Snack Cart (25 levels), Garden Express (5), Baggage Bay (6), Rainy Platform (6). Destinations 5 to 8 show as "coming soon" on the map. Levels unlock in order; the next stop opens at 60% completion. Stars: finish, no hints, 3 or fewer undos.
- Restoration projects with a pixel-art scrapbook that fills as stars are earned.
- Relax: three unscored pools (Liquid 150, Pixel 150, Flow Fix 150) that keep your place.
- Daily Journey: 730 puzzles rotating across all five modes, picked by hashing the local date (FNV-1a, see `docs/rules.md`). No streaks; only a "journeys taken" count.
- Haptics only (no sound, no music). Offline, no accounts, no ads, no analytics.
- Accessibility and comfort: VoiceOver labels on every control and board element, color-blind symbols and patterns, high-contrast theme, reduced motion (follows the system setting), 1x/2x animation speed, left-handed HUD, Dynamic Type, iPad landscape side panel and Split View.
- Progress lives in one JSON file on the device (atomic writes, rolling backup, checksum) and can be exported and imported as a `.pgsave` file from the Backup screen.

### Content counts

| Content | Count |
|---|---|
| Campaign levels | 42 (Liquid 10, Pixel 10, Bolt 10, Baggage Jam 6, Flow Fix 6) plus 3 demo levels (hidden) |
| Relax pools | 450 (150 each: Liquid, Pixel, Flow Fix) |
| Daily Journey pool | 730 (Liquid 209, Pixel 209, Flow Fix 104, Bolt 104, Baggage Jam 104) |
| Scrapbook pictures | one per restoration stage |

Every level and pool entry stores a verified solution that the forge and the Swift tests both replay.

## Build and run

```sh
brew install xcodegen
xcodegen generate
open PuzzleGetaway.xcodeproj
```

The Xcode project is generated from `project.yml` and git-ignored. Sources are picked up by folder, so adding a Swift file needs no project edits. The `PuzzleGetaway/Resources` folder is bundled as a folder reference copied to `Content/Resources/` inside the app (`Levels`, `Pools`, `Art`, `Destinations.json`); load it through `ContentStore` / `ResourceLocator` in `Core/Content.swift`.

Run tests: select the `PuzzleGetaway` scheme and press Cmd-U, or

```sh
xcodebuild test -project PuzzleGetaway.xcodeproj -scheme PuzzleGetaway \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## Level forge

`tools/forge` (TypeScript, Node 22) generates and validates every bundled level and pool entry, proving solvability and storing a solution with each one.

```sh
cd tools/forge
npm ci
npm test          # unit tests (node:test via tsx)
npm run validate  # validates all JSON in PuzzleGetaway/Resources
npm run build     # type-check
```

### Regenerating content

All generators are deterministic (seeded `mulberry32`), so rerunning reproduces the same files.

```sh
cd tools/forge
npm run gen:sort            # Levels/d1-liquid, d1-bolt, d2-bolt and Pools/relax-liquid
npm run build:pixel         # Levels/d1-pixel, Pools/relax-pixel and the Swift golden fixtures
npx tsx scripts/gen-parking.ts   # Levels/d3-parking
npx tsx scripts/gen-pipe.ts      # Levels/d4-pipe and Pools/relax-pipe
npm run gen:daily           # Pools/daily (730 entries, roughly half an hour)
npx tsx scripts/make-scrapbook.ts   # Art/scrapbook/*.json
npm run validate && npm test        # always run before committing generated files
```

Modes register in `tools/forge/src/modes/index.ts` (`{validate, replay, solve}`); the Swift side registers in `PuzzleGetaway/Engine/ModeRegistry.swift`.

## Offline guarantee

The app contains no networking code, no analytics and no third-party packages. `Info.plist` declares no network, tracking or local-network keys, and no remote URLs appear in code or bundled resources. CI (`.github/workflows/ios.yml`, job "Network audit", `.github/scripts/network_audit.sh`) fails if Swift sources use `URLSession`, `import Network`, `import WebKit`, `NSURLConnection`, `URLRequest(`, ad or analytics imports, URL-opening calls or `http(s)://` literals, if bundled resources contain URLs, if `project.yml` declares network-related keys, or if any Swift Package dependency appears.

## Folder map

| Path | Purpose |
|---|---|
| `project.yml` | XcodeGen project definition |
| `PuzzleGetaway/App` | App entry, `AppModel`, `Router`, scene-phase autosave |
| `PuzzleGetaway/Core` | Content models and loader, `SaveStore`, `Settings`, `Haptics`, `Theme` |
| `PuzzleGetaway/Engine` | `PuzzleRules`, `GameSession`, `HintSolver`, controllers, `ModeRegistry` |
| `PuzzleGetaway/Modes` | One folder per puzzle mode (`Demo` is a placeholder) |
| `PuzzleGetaway/Screens` | SwiftUI screens (menu, map, level select, game host and HUD, completion, restoration, scrapbook, Relax, Daily, settings, backup) |
| `PuzzleGetaway/Resources` | Levels, pools, art, destinations (JSON) |
| `PuzzleGetawayTests`, `PuzzleGetawayUITests` | XCTest unit and UI tests |
| `tools/forge` | TypeScript level forge |
| `docs/rules.md`, `docs/level-format.md` | Canonical rules and JSON formats |
| `.github/workflows` | `ios.yml` (macOS build/test, network audit), `forge.yml` |

## Continuous integration

- `iOS` (macOS runner): network audit, then XcodeGen build and all unit and UI tests on an iPhone and an iPad simulator. Screenshots from the UI tests are exported as the `iphone-results` and `ipad-results` artifacts (the `*-attachments` folders inside them; each file is a named `XCTAttachment`).
- `Forge` (Ubuntu): `npm test`, `npm run validate`, `npm run build`.
- UI tests with real content use DEBUG-only launch hooks (`Core/TestHooks.swift`): `-PGUITestHooks` adds an invisible but hittable "Solve step" button (accessibility id `solveStep`) in the HUD that plays the next stored-solution move, and `-PGOpenLevel <id>` opens a level directly. Neither exists in Release builds. Older shell tests use `-PGDemoOnly`.
- `SolutionReplayTests` replays every campaign level and a deterministic sample of each pool (every 6th entry); the forge replays all entries.

## Manual device test checklist

Run on a real iPhone and iPad before shipping.

1. Airplane mode on a fresh install: install, launch, play a level from each mode, open Relax and Daily, change settings. Nothing should ask for the network or for any permission.
2. Persistence: make a few moves in a puzzle, press Home, force-quit, relaunch and tap Continue (exact board returns). Repeat after a device reboot.
3. Backup: complete a few levels, export from Backup, delete the app, reinstall, import the file and confirm stars, restoration stages, scrapbook, in-progress puzzle and settings come back. Also try importing a damaged file (an error message, no data loss).
4. VoiceOver: navigate the menu, map and level select; play one level in each mode using only VoiceOver (tube, bolt, crate, vehicle and tile labels, hint, undo, level complete card).
5. Dynamic Type at the largest accessibility size (XXXL): menu, level select, HUD, pause, completion and settings must scroll or wrap without clipped text.
6. iPad: landscape side panel, portrait, Split View and Slide Over at narrow widths; rotate mid-puzzle.
7. Small iPhone (SE size): a big Pixel Picnic picture (for example `d1-pixel-23`) stays readable; use the zoom button if offered and confirm crate taps still work.
8. Settings: haptics off, reduce motion, 2x speed, high contrast, left-handed HUD and patterns off all apply immediately.
9. Date handling: change the device date and confirm the Daily Journey puzzle changes with the local date and never crashes at month or year boundaries.
