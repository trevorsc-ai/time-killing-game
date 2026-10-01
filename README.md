# Puzzle Getaway

An offline-first iPhone and iPad puzzle collection set on the Lantern Line, a cozy workshop train served by the Parcel Pals. Five puzzle modes (Liquid, Bolt, Pixel Picnic, Baggage Jam, Flow Fix), restoration projects, a scrapbook, relaxed pools and a daily journey. SwiftUI + SpriteKit, iOS 16+, no ads, no accounts, no sound (haptics only).

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

`tools/forge` (TypeScript, Node 22) validates and will generate every bundled level, proving solvability and storing a solution with each level.

```sh
cd tools/forge
npm ci
npm test          # unit tests (node:test via tsx)
npm run validate  # validates all JSON in PuzzleGetaway/Resources
npm run build     # type-check
```

Modes register in `tools/forge/src/modes/index.ts` (`{validate, replay, solve}`); the Swift side registers in `PuzzleGetaway/Engine/ModeRegistry.swift`.

## Offline guarantee

The app contains no networking code. CI (`.github/workflows/ios.yml`, job "Network audit") fails if Swift sources use `URLSession`, `import Network`, `import WebKit`, `NSURLConnection` or `URLRequest(`, or if any Swift Package dependency appears.

## Folder map

| Path | Purpose |
|---|---|
| `project.yml` | XcodeGen project definition |
| `PuzzleGetaway/App` | App entry, `AppModel`, `Router`, scene-phase autosave |
| `PuzzleGetaway/Core` | Content models and loader, `SaveStore`, `Settings`, `Haptics`, `Theme` |
| `PuzzleGetaway/Engine` | `PuzzleRules`, `GameSession`, `HintSolver`, controllers, `ModeRegistry` |
| `PuzzleGetaway/Modes` | One folder per puzzle mode (`Demo` is a placeholder) |
| `PuzzleGetaway/Screens` | SwiftUI screens (currently stubs) |
| `PuzzleGetaway/Resources` | Levels, pools, art, destinations (JSON) |
| `PuzzleGetawayTests`, `PuzzleGetawayUITests` | XCTest unit and UI tests |
| `tools/forge` | TypeScript level forge |
| `docs/rules.md`, `docs/level-format.md` | Canonical rules and JSON formats |
| `.github/workflows` | `ios.yml` (macOS build/test, network audit), `forge.yml` |
