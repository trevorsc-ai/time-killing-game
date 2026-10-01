# Level and content format

All content is JSON under `PuzzleGetaway/Resources/`, bundled as a folder reference at `<app>/Content/Resources/` (see `ResourceLocator` in `Core/Content.swift`; never use `Bundle.url(forResource:)` for these). Mirrors: TypeScript `tools/forge/src/schema.ts`, Swift `PuzzleGetaway/Core/Content.swift`. The forge validator (`npm run validate`) enforces everything below. Rules semantics live in `rules.md`.

## Layout

```
Resources/
  Destinations.json
  Art/palette.json            shared palette (+ later: pixel scenes, scrapbook art: Art/<name>.json)
  Levels/<destination>-<mode>.json   e.g. d1-liquid.json, d1-pixel.json, d1-bolt.json, d2-bolt.json, d3-parking.json, d4-pipe.json
  Pools/relax-liquid.json  relax-pixel.json  relax-pipe.json  daily.json
```

One levels file per destination **and** mode so parallel work never touches the same file. The app loads every `Levels/*.json`, merges, and sorts by `(destination, order)`. `demo-demo.json` is the reserved development destination `demo` (hidden from the map).

## Level file

```json
{ "destination": "d1", "mode": "liquid", "levels": [ <level envelope>, ... ] }
```

File name must be `<destination>-<mode>.json`; every level inside must repeat the same `destination` and `mode`.

## Level envelope

```json
{
  "id": "d1-liquid-01",
  "mode": "liquid",
  "destination": "d1",
  "order": 1,
  "title": "Warm-up Pour",
  "difficulty": 1,
  "tutorial": "liquid.pour",
  "twists": [],
  "par": 5,
  "solution": [ {"from":0,"to":2}, ... ],
  "payload": { ... mode specific ... }
}
```

| Field | Type | Rules |
|---|---|---|
| `id` | string | `<destination>-<mode>-<NN>` with `NN = order` zero-padded to 2 digits; unique across the whole bundle (pool entries: see Pools) |
| `mode` | string | `liquid`, `bolt`, `pixel`, `parking`, `pipe` (plus `demo` for the placeholder) |
| `destination` | string | `d1`..`d8`, or `demo` (pool entries: the pool name) |
| `order` | int >= 1 | position inside the destination; must be one of the pre-assigned slots below; unique per destination |
| `title` | string | short, warm, original |
| `difficulty` | int 1..10 | should rise within a mode across a destination |
| `tutorial` | string, optional | key of the first-time tip card the shell shows (e.g. `liquid.pour`) |
| `twists` | [string] | names of twists the level introduces or uses (`hidden`, `lock`, `capped`, `rusty`, `stone`, `tee`, ...); shell shows a tip the first time |
| `par` | int >= 1 | optimal (or best-known) move count; `par <= solution.length` |
| `solution` | [move] | a verified full solution; each move is the mode's move JSON |
| `payload` | object | mode-specific initial state |

### Pre-assigned orders

| Destination | Mode (orders) |
|---|---|
| d1 | liquid: 1 3 5 7 9 11 13 15 18 21 |
| d1 | pixel: 2 4 6 8 10 12 14 17 20 23 |
| d1 | bolt: 16 19 22 24 25 |
| d2 | bolt: 1 2 3 4 5 |
| d3 | parking: 1 2 3 4 5 6 |
| d4 | pipe: 1 2 3 4 5 6 |

d1 therefore has 25 levels interleaved by `order`. d5..d8 have no levels (coming soon). The same table is `ORDER_TABLE` in `schema.ts`.

## Mode payloads and moves

These are the contracts the mode owners implement (TypeScript type, Swift Codable, JSON). A mode owner may extend a payload with optional fields, but must document the change here in the same PR.

### liquid

```json
"payload": {
  "capacity": 4,
  "tubes": [["r","b","r"], ["b","r","b"], [], []],
  "hidden": [[0,0]],
  "locks": [{"tube": 3, "color": "r"}]
}
```
`tubes`: layers bottom to top as palette ids; every color appears exactly `capacity` times. `hidden` (optional): `[tubeIndex, layerIndex]` pairs (layer 0 = bottom); a hidden layer must not be the top layer of its tube (tops are always revealed). `locks` (optional): the named color must not sit inside the locked tube. Level `twists` must name every twist the payload uses (`hidden`, `lock`). Move: `{"from": 0, "to": 2}`. Hint/solver note: the forge solver and the Swift hint solver treat hidden colors as known (generation guarantees solvability).

### bolt

Same as liquid, plus optional `"capacities": [5,5,3,...]` (per bolt; twist `capped`; colors may then appear fewer times than the tallest bolt holds, never more) and `"rusty": [{"bolt":1,"index":0,"color":"g"}]` (twist `rusty`; `color` is the tag color that must be completed first). Bundled bolt levels use `capacity` 5. Move: `{"from": 0, "to": 2}`.

Content for both modes is regenerated deterministically with `cd tools/forge && npm run gen:sort` (seeds live in `scripts/gen-sort.ts`). Tutorial/twist tip copy lives in `Resources/Tips/liquid.json` and `bolt.json` (keys `liquid.pour`, `bolt.move`, `twist.hidden`, `twist.lock`, `twist.capped`, `twist.rusty`).

### pixel

```json
"payload": {
  "grid": ["wwrrww", "wrrrrw", "..gg.."],
  "slots": 5,
  "lanes": [
    [ {"color":"r","count":6}, {"color":"w","count":6} ],
    [ {"color":"g","count":2} ]
  ]
}
```
- `grid`: rows of equal length (any size from 2x2 up; the bundled levels run from 10x10 to 20x20). Each character is a palette id, `.` for a transparent cell (cleared from the start, so it exposes its neighbors), or `#` for a stone blocker (not a color, has no crate, crumbles when a 4-adjacent pixel is packed; a level containing stones must list the `stone` twist).
- `slots`: tray slots (5 early, 4 mid, 3 late).
- `lanes`: 2 to 4 lanes; each lane is the crate queue, front crate first. A crate is `{color, count}` (`pattern` is accepted but unused: the app derives the symbol/pattern from the palette color).
- Invariant (validated): for every color, the crate counts add up to that color's pixel count; every pixel is therefore packed by exactly one crate.
- Move: `{"lane": 0}` taps the front crate of that lane. `par` equals the number of crates, because every solution taps every crate exactly once.
- Replay rejects taps after the board is clear and any stone that never crumbled.
- Golden parity fixtures for Swift live in `PuzzleGetawayTests/Fixtures/pixel-golden.json` (generated by `npm run build:pixel golden`).

### parking

```json
"payload": {
  "size": 6,
  "vehicles": [
    {"id":"T","r":2,"c":0,"len":2,"axis":"h","target":true},
    {"id":"A","r":0,"c":2,"len":3,"axis":"v"}
  ],
  "gates": [{"target":"T","edge":"right","index":2}]
}
```
Move: `{"id": "A", "delta": 2}`. Vehicle ids are short strings; targets are conventionally `T` (and `U`). The levels `d3-parking-01..06` use tutorial `parking.slide` (level 1) and the twist `second-gate` (levels 5 and 6, two targets).

### pipe

```json
"payload": {
  "grid": [["S0","i1","l0"], ["x0","t2","D3"]],
  "fixed": [[0,0]]
}
```
Tile token = code (`. i l t x S D`) + rotation digit 0..3 (initial, i.e. scrambled, rotation). `fixed` (optional): `[row, col]` tiles that cannot be rotated. Move: `{"r": 1, "c": 2}` (rotate that tile one step clockwise). Shipped boards list the source and destinations in `fixed`. Levels `d4-pipe-01..06` use tutorial `pipe.rotate` (level 1) and the twist `tee` (levels 4 to 6, which also have several destinations). `Pools/relax-pipe.json` holds 150 entries rising from 3x3 to 7x7.

### demo (placeholder)

`"payload": {"start":0,"target":7,"deltas":[1,3]}`; move `{"delta":3}`. Add the delta without exceeding the target; solved at the target.

## Pools

```json
{ "pool": "relax-liquid", "entries": [ <level envelope>, ... ] }
```

Files: `relax-liquid`, `relax-pixel`, `relax-pipe`, `daily`. Entries are full envelopes with `destination` = the pool name, `order` = 1-based index, `id` = `<pool>-<NNN>` (3 digits), a real `mode`, `difficulty`, `par`, and a verified `solution`. Order slots are not restricted by `ORDER_TABLE`. `daily.json` mixes modes (about 730 entries); selection is defined in `rules.md` (Daily Journey selection). Relax pools are unscored.

## Palette: `Art/palette.json`

```json
{ "colors": [ {"id":"r","name":"Tomato","hex":"#E5594F","highContrastHex":"#B3201A","symbol":"circle.fill"}, ... ] }
```
`id` is a single character (not `.`, `#`, `?`, space) used by all payloads and pixel art. `symbol` is the SF Symbol shown as the accessibility pattern (unique per color). `highContrastHex` is used when the high-contrast setting is on.

## Destinations: `Resources/Destinations.json`

```json
{
  "unlockPercent": 60,
  "destinations": [{
    "id": "d1", "name": "Station Snack Cart", "tagline": "...", "intro": "1-2 sentences",
    "theme": {"primary":"#E98B5F","secondary":"#F7D7B5","accent":"#5DA9E8","background":"#FFF6E8"},
    "comingSoon": false,
    "restorationTitle": "Restore the Snack Cart",
    "restorationStages": [{"id":"d1-s1","title":"A good sweep","starsRequired":3,"scrapbookArtId":"d1-stage1"}]
  }]
}
```
Eight destinations `d1..d8`; `d5..d8` are `comingSoon: true` with no stages. `starsRequired` strictly increases within a destination. `scrapbookArtId` names a file `Art/<id>.json` (pixel char-grid art, to be authored by the shell/art work).

## Pixel-art scenes (reserved for the Pixel/Shell work)

Not yet defined beyond: files live in `Resources/Art/<name>.json`, use palette ids per cell with `.` transparent, and are drawn nearest-neighbor. The author of the first art file documents the exact shape here.

## Swift access

```swift
let content = try ContentStore.load()          // Bundle.main and the test bundle both work
content.allLevels; content.levels(in: "d1"); content.pool("daily"); content.destinations; content.palette
let payload: MyPayload = try level.decodePayload()
let moves: [MyMove] = try level.decodeSolution()
```
