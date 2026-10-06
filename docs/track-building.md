# Track building internals

Read before changing how roads, branches, rooms, scenery, checkpoints, respawn points, gap jumps or the grid are built.

## Roads and branches
- Track building: `planRoute` works out one road (the main road or a branch).
  - It samples the curve every `STEP` studs and works out the road's width at each sample (`Room`s flare out over `ROOM_EASE`), plus the off-road strips (`route.edge` = road plus off-road).
  - It works out banking (flat in rooms and at the road's ends) and the sections.
  - `buildRoute` builds it. Off-road is one sheet from wall to wall, 0.15 studs below the road (its parts carry an `OffRoad` attribute); the road sits on top.
  - Where two roads overlap (a branch joining a Room), walls, curbs, off-road and pillars open up by themselves (`route.covers`, with `roadOnly` to ignore off-road).
  - A branch with `respawns = false` gets no respawn points, so falling off it puts you back at the last main-road gate before it.
  - Branch ends must sit inside a main-road Room, at about the same height. `fitBranchEnds` then lays the branch's ends right onto the main road's surface (both edges, so lean and slope match) and eases back to the branch's own shape over `ROOM_EASE`, so a junction never has a lip.
  - Tight corners need control points ~20–30 studs apart, evenly spaced (Windy Ledge's 90° turn is a 30-stud circle). A corner tighter than the road is wide folds the inside edge over itself, leaving lips and holes; a short gap between points next to a long one makes the curve bulge. TrackCheck reports these as TIGHT.

## Hollow scenery (volcano, temple)
- Scenery that roads pass through is hollow, with openings cut where roads go: the volcano (`buildCrater`) and the step-temple pyramid (`buildPyramid`, built for any track with a `TEMPLE`: Jungle and Swamp; the Swamp one has Fred on top instead of the gem).
  - Each step of the temple is a ring of four thick walls. Where a road crosses a wall, only a doorway just big enough for the road and its cave is cut (the wall is sliced at each doorway's edges, with a sill under the road and a lintel above). Every road inside the temple must be a `Tunnel`, so its cave hides the hollow inside.
  - Roads must cross the temple's walls head-on: a road running along inside a wall cuts a long slot in it. Swamp scenery: mangroves, reeds, lily pads and giant glowing mushrooms (`buildMangrove`, `buildReeds`, `buildLilyPad`, `buildMushroom`); the `CaveMushrooms` theme flag puts mushrooms along cave walls instead of crystals. The ground (lava sea, cloud sea, river) is tiled, because a part can't be longer than 2048 studs.

## Checkpoints and respawn points
- Checkpoints vs respawn points: checkpoints (must be passed in order) only go on road every route shares. There are none on main road that a branch or a `Skippable` drop shortcut skips, none in a gap-jump run-up (`JUMP_RUNWAY`), and none next to a hazard that reaches the middle of the road (`HAZARD_CLEARANCE`). `RespawnPoints` are optional gates on every route, branches included. You respawn at whichever gate you went through last.
  - A racer may miss up to `CHECKPOINT_SKIP` (3) checkpoints in a row; passing any of the next 3 still counts. Big jumps can fly right over gates: for example, coming off Magma's Lava River Jump angled left lands you on the road below, past checkpoints 41 and 42. It's safe because no checkpoint's pass zone covers road near an earlier one; that was checked on all four tracks. Re-check that when adding a track whose roads run close together.
  - Every gate faces the race direction. The client uses the nearest one to show a blinking "WRONG WAY!" after 1 s of driving against it. This matters after Magma's drop: you land facing the wall, and the race goes left. Turning right takes you backwards up the Lava Falls Loop, where only respawn points update and you never reach the next checkpoint.
  - To test a route in Play, move your kart from the Server with `RaceEvent:FireClient(player, "Respawned", cframe)` (it also sets the kart's heading). Then watch the player's `Checkpoint` attribute. Moving the kart from the Client doesn't update the client's heading.

## Jumps and grid
- Gap jumps (`Ramp` with `gap`): gap sizes were tuned by test: full speed clears by ~12 studs, below ~60 studs/s at the lip falls.
- Grid spacing: `GRID_SIDE` (13) and `GRID_ROW` (16) are roomy on purpose, so bigger or customised karts still fit. A 12×16-stud kart fits on road at every slot on all tracks. The back row sits ~68 studs behind the start line, so keep it under `PRE_START` (80).
