# Puzzle Getaway: canonical rules

This file is the single source of truth. The forge (TypeScript, `tools/forge`) and the app (Swift, `PuzzleGetaway/Modes/*`) must produce **identical** results for the same level and move list. If you change a rule, change it here first, then in both implementations, in the same PR.

Conventions used throughout:

- Colors are single-character palette ids (`Art/palette.json`): `r o y g t b i p k n w s`.
- Grids are indexed `(row, col)`, row 0 at the top, col 0 at the left. "Row-major" scan order is row 0 left to right, then row 1, and so on.
- Tube/bolt layers are listed **bottom to top**. The *top* is the last element.
- A "move" is one entry of `solution` (see `level-format.md` for each mode's JSON form). `moveCount` counts applied moves (undo decrements it).
- Every mode implements: `legalMoves(state)`, `apply(move, state) -> state | nil` (nil = illegal), `isSolved(state)`, `isStuck(state)` (default: not solved and no legal move).
- Replay check (forge `replay`, Swift `PuzzleModePlugin.replay`): start from the payload's initial state, apply each stored move in order; every move must be legal and the final state must be solved. A solution must not contain moves after the state first becomes solved.

## Liquid Sort ("Color Mixer"), mode `liquid`

State: `tubes: [[Layer]]`, each tube holds at most `capacity` layers (default 4). A layer is a color plus a `hidden` flag.

**Move** `{from, to}` (tube indices), `from != to`. Legal iff all hold:

1. Tube `from` is non-empty and not locked; tube `to` is not locked.
2. Tube `to` has free space: `len(to) < capacity`.
3. `to` is empty, or `top(to).color == top(from).color`.

There is no "pointless move" filter: for example pouring a lone-colored tube into an empty tube is legal. Solvers may prune such moves, but the rules do not.

**Effect.** Let `run` = number of contiguous layers at the top of `from` that are *revealed* and share `top(from).color`. Move `n = min(run, capacity - len(to))` layers from the top of `from` onto the top of `to`, preserving order. Then reveal the new top of `from` (set `hidden = false`) if `from` is non-empty. Then evaluate lock openings (below).

**Hidden layers (twist `hidden`, from L7).** A hidden layer renders as "?" and is **not** part of a run (`run` stops at the first hidden layer going downward). It becomes revealed permanently the moment it is the top of its tube (including at the initial state: the top of every tube is revealed on load). A hidden layer cannot be the top of the `to` tube (tops are always revealed), so matching never depends on hidden colors.

**Locked tubes (twist `lock`, from L9).** Payload `locks: [{tube, color}]`. A locked tube can be neither source nor target. It opens (permanently, tracked in state) when the named color is *completed*: some tube holds `capacity` layers all of that color. Check after every move, and once at load. Lock openings are not themselves moves.

**Solved.** Every non-empty tube is single-colored (all layers same color), and no color appears in more than one tube. (With every color appearing exactly `capacity` times this means each non-empty tube is full of one color.) A tube that is still locked and non-empty is judged like any other tube.

**Stuck.** Not solved and no legal move.

## Bolt Sort ("Tool Bench"), mode `bolt`

Shares the Liquid engine and the Liquid move definition (`{from, to}`, "bolts" = tubes, "nuts" = layers, same top-run pour rule, same solved rule). Differences:

- **Per-bolt capacity.** Payload may give `capacities: [int]`, one per bolt (default: `capacity` for all). "Space left" and `len(to) < capacity` use the target bolt's own capacity. (Twist `capped`, Dest 2.)
- **Rusty nuts (twist `rusty`, Dest 2 late).** Payload `rusty: [{bolt, index, color}]`: the nut at `index` (0 = bottom) of `bolt` is rusty until `color` is *completed* (all nuts of that color sit together in a single bolt that holds only that color; evaluated after every move and at load; once cleared, a nut stays clear). A rusty nut cannot be moved: if the top nut of `from` is rusty the bolt is not a legal source, and a top run stops above a rusty nut. Rusty nuts are never hidden.
- Hidden layers and locks are not used in Bolt, but the engine supports them identically if a payload provides them.

## Pixel Picnic ("Critter Clear"), mode `pixel`

### State

- `grid`: rows of cells. Each cell is a palette color char, `.` (empty, counts as **cleared** from the start), or `#` (stone blocker).
- `lanes`: 2 to 4 lanes; each lane is an ordered list of crates, front first. A crate: `{color, count, pattern?}`. (`pattern` is display only.)
- `slots`: `S` tray slots (5 early, 3 later). Each slot is empty or holds a crate with `remaining` (initially `count`).
- Invariant (checked by validators): for every color, the sum of crate `count`s over all lanes equals the number of pixels of that color in `grid`.

### Move

`{lane}`: tap the front crate of lane `lane`. Legal iff the lane is non-empty **and** at least one slot is empty. Effect: pop the front crate; place it (with `remaining = count`) into the **leftmost empty slot**; then run `resolve()`.

### Exposure

A pixel (colored cell) at `(r,c)` is **exposed** iff it touches the grid edge (`r == 0 || c == 0 || r == H-1 || c == W-1`) **or** any 4-neighbor is a cleared cell. A cleared cell is `.`, a cell whose pixel was packed, or a crumbled stone. Stones (`#`) are never cleared until they crumble and never count as exposing.

### `pack(crate, color c)` (one crate, one visit)

1. Build the BFS queue: all currently exposed pixels of color `c`, in row-major order. Mark them visited.
2. While `remaining > 0` and the queue is non-empty: pop the front pixel `p`; clear it (it becomes a cleared cell); `remaining -= 1`; then, for each neighbor of `p` in the order **up, left, right, down** (`(r-1,c)`, `(r,c-1)`, `(r,c+1)`, `(r+1,c)`), if it is in bounds, has color `c`, and is not visited: mark it visited and push it to the back (chaining inward through same-color neighbors, whether or not it was exposed at the start).
3. Pixels packed in this visit are the cleared cells for the crumble rule below.
4. If `remaining == 0` the crate departs (see resolve). Otherwise it stays in its slot and waits.

### Stone crumble

After each `pack` visit that cleared at least one pixel, every stone that has at least one 4-neighbor among **the pixels packed in that visit** crumbles: it becomes a cleared cell. Crumbling does not cascade within the same visit (a crumbled stone does not crumble neighboring stones); the next visit/pass handles any further effect since the crumbled cell is now cleared for exposure.

### `resolve()`

Repeat passes until a pass makes no change:

- A pass visits slots `0 .. S-1` **left to right**. For each non-empty slot: run `pack` with its crate. If afterwards `remaining == 0`, empty the slot (the crate departs). The pass "changed something" if any pixel was packed or any crate departed (or any stone crumbled).

Departing frees the slot immediately within the pass, but lanes never auto-advance: only taps move crates into slots.

### Solved / stuck

- **Solved:** no pixels remain in `grid` (equivalently all crates have departed, given the invariant). Stones may remain only if unreachable, which validators reject: a valid level has no stones left once all pixels are cleared or they must crumble (levels with leftover stones are invalid).
- **Stuck:** not solved and no legal move (all slots full after `resolve()`, or all lanes empty). The app shows "The Pals are jammed" with Undo/Restart; there is no game over.
- **Twists:** `stone` (blockers, from L7+); tighter slot counts (`slots` = 3).

### Golden determinism requirements

Both implementations must pick pixels strictly in the BFS order above. `lanes` are tapped by index; slots fill left to right. No randomness at play time.

## Baggage Jam, mode `parking`

A `6 x 6` grid (`size` in the payload, default 6). Vehicles are axis-aligned rectangles: `{id, r, c, len, axis}` where `(r,c)` is the top-left cell, `len` is 2 or 3, `axis` is `"h"` (occupies `(r, c..c+len-1)`) or `"v"` (occupies `(r..r+len-1, c)`). Exactly the vehicles flagged `target: true` are the carts that must exit.

**Move** `{id, delta}`: slide vehicle `id` along its own axis by `delta != 0` cells (positive = right for `h`, down for `v`). Legal iff the vehicle stays fully in bounds and every cell it passes through or ends on is free (not covered by another vehicle). One slide of any length is **one move**. No move limit.

**Gates.** Payload `gates: [{target, edge, index}]`: `edge` is `"left" | "right" | "top" | "bottom"`; `index` is the row (for left/right) or column (for top/bottom). The vehicle named `target` must have its axis aligned with the gate (`h` for left/right with the same row as `index`; `v` for top/bottom with the same column).

**Solved.** For every gate, the target vehicle touches that edge: `right`: `c + len == size`; `left`: `c == 0`; `bottom`: `r + len == size`; `top`: `r == 0` (the cart "drives out"). Two-target levels have two gates and two targets (late levels).

**Exit presentation (not a rule).** Targets stay on the board and remain movable until *every* gate is satisfied; only then does the app play the departure animation (targets roll out through their gates, the gates open). The exit is purely visual and happens after the state is solved, so it does not affect replay, hints, or undo. A target that already touches its gate in a two-target level simply waits there. Solutions must not contain moves after the state first becomes solved. Because every slide can be undone by the opposite slide, a Baggage Jam board can never get stuck. Vehicle "kind" (luggage cart, mini train, service tug, baggage trolley) is cosmetic and derived by the app from the vehicle's length and index.

## Flow Fix, mode `pipe`

Grid of tiles. Openings are a 4-bit mask `N=1, E=2, S=4, W=8`. Rotation is 90 degrees **clockwise**: `rotate(mask) = ((mask << 1) & 15) | (mask >> 3)`.

| Tile code | Meaning | Mask at rotation 0 |
|---|---|---|
| `.` | empty | 0 |
| `i` | straight | `N|S` (5) |
| `l` | elbow | `N|E` (3) |
| `t` | tee (splitter) | `E|S|W` (14) |
| `x` | cross | all (15) |
| `S` | source (exactly one) | `N` (1) |
| `D` | destination (one or more) | `N` (1) |

A tile token is its code plus the rotation digit `0-3` (e.g. `l2`); empty tiles are written `.0`. Rotation `k` applies `rotate` k times to the base mask.

**Move** `{r, c}`: rotate the tile at `(r,c)` clockwise by 90 degrees (`rot = (rot + 1) % 4`). Illegal on empty tiles and on tiles listed in `fixed`. Each tap is one move, so a tile needing 3 turns costs 3 moves.

**Connectivity.** Tiles at `(r,c)` and its neighbor in direction `d` are connected iff the tile at `(r,c)` has opening `d` **and** the neighbor has the opposite opening. Flow starts at the source and spreads through connected tiles (BFS; order irrelevant to the result).

**Solved.** Every destination tile is reached by the flow. (Dead ends and unused branches are allowed.)

**Scramble guarantee.** The initial state must not be solved. Forge generators scramble from a solved layout and reject any result that is solved.

**Conventions for shipped content.** The source and every destination are listed in `fixed` (they keep their solved orientation); only pipes are turned by the player. Several solutions may exist; the stored `solution` is one valid list of taps and `par` is its length. The forge solver (`tools/forge/src/modes/pipe/solver.ts`) searches for a cheaper solution and shipped boards are proven minimal whenever its search finishes within budget. Swift hints do not search: they steer the player toward the configuration reached by the stored solution. The app may show connected tiles filled with water and lit destinations as presentation; this does not change the rules.

## Stars

Applies to every mode except Relax (unscored). When a level is solved, stars = `1` (completed) `+ 1` if `hintsUsed == 0` `+ 1` if `undoCount <= 3`. `undoCount` and `hintsUsed` accumulate over the whole session including after Restart. Re-asking for the hint that is already displayed is free. A level's saved result keeps the best stars and fewest moves.

## Progression constants

- Levels within a destination unlock in `order`. The next destination unlocks when `>= unlockPercent` (60) percent of the previous destination's levels have a recorded result (rounded up: `ceil(0.6 * n)` levels).
- Restoration stages unlock when the destination's total stars `>= starsRequired`.

## Daily Journey selection

`index = fnv1a32(utf8("YYYY-MM-DD")) % entries.count` using the player's **local** date, zero-padded, and the FNV-1a 32-bit hash (offset basis `0x811c9dc5`, prime `0x01000193`, byte-wise `xor` then multiply, mod 2^32). Test vectors: `fnv1a32("") = 0x811c9dc5`, `fnv1a32("a") = 0xe40c292c`, `fnv1a32("foobar") = 0xbf9cf968`. The forge exposes `fnv1a32` in `src/util/prng.ts`. There are no streaks; the app only counts journeys taken.

## Forge PRNG

`mulberry32(seed)`: `state = (state + 0x6D2B79F5) mod 2^32; t = imul(state ^ (state >>> 15), state | 1); t ^= t + imul(t ^ (t >>> 7), t | 61); result = ((t ^ (t >>> 14)) >>> 0) / 2^32`. Generators must derive all randomness from a seed recorded by the generator script so that regenerating produces the same files.
