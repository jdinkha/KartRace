# KartRace — notes for Claude Code

Roblox kart racing game written in Luau. The scripts live in the place file (`KartRace.rbxlx`) and are edited in Studio through the Roblox Studio MCP (the Rojo `src/` files were removed).

## Track design: every track is a level, not a circuit
The goal is for each track to feel like a level in a video game (think of driving through a 3D Zelda dungeon or a Mario Kart world). It should not feel like a real-world circuit (NASCAR/F1: one line of constant width with a few turns). It's still a race from the start line to one finish line, but the trip goes through distinct places.
- **A string of named areas.** Split each track into about 4–6 areas. Each gets its own name (on a `Banner`), its own look and its own challenge. Change the pace between them: open arena → tight cliff road → cave → big jump.
- **Rooms joined by corridors.** Like a dungeon: wide `Room` sections (arenas, plazas, caverns, 60–140 studs wide) connected by normal roads and `Tunnel` caves.
- **Choices and creative shortcuts.** Each track needs at least two shortcuts, and they should be inventive, not just "a narrower road". Mark each one with a `Sign` or `Banner`. Examples already in the game:
  - a hole you can drop through onto road below (Magma's Lava River Jump: the main road loops down and passes under its own jump, `Skippable`)
  - a secret cave behind a waterfall (Jungle)
  - a boost-only leap across a ravine (Jungle)
  - an icy rail-less slide (Frosty)
  - a grass cut that's only fast if you hit the boost pad first (Skyway)
  - a risky geyser tube (Magma)

  A good shortcut saves a few seconds but costs something: risk of falling, slow off-road, hazards, or needing a boost.
- **Off-road instead of bare walls.** Roads have slow off-road strips (grass, ash, snow, mud) between the road and the walls (`OFFROAD`); the walls sit at their outer edge. Boosting ignores off-road, so a boost pad before an off-road cut makes it a real shortcut.
- **Race length.** A race should take about 1.5–2 minutes: around 7000–8500 studs of main road, with several distinct areas.
- **Hazards that fit the theme, with patterns players can learn.** Timed things warn before they fire (geysers bubble first). Moving things move steadily (fire bars, snowballs). Always leave a clear line through, and never place an unavoidable hit.
- **Height and landmarks.** Climb and drop, cross over or under other parts of the track, and give players something big to head for (the volcano, the sky rink).
- **Kid-friendly punishment.** Hazards slow you, spin you out, or send you back a little ("TOO HOT!", "WHOOPS!"). Nothing scary or violent.
- **Room for a dozen karts.** Races have up to 12 racers (`MAX_RACERS`). The main road is never narrower than `ROAD_WIDTH` (46, about eight karts side by side). Only branches can be narrower (~26–32), because only part of the pack takes them.

**The one exception is Rainbow Skyway: the "vanilla" track** (like Mario Circuit). It's deliberately plain: wide (54), gentle and nearly straight, with walls everywhere and no hazards. Its extras stay simple: grass verges, a few cloud pillars to weave between, boost pads and one grass cut. It should still be the prettiest track. New tracks should follow the level style above, not copy Skyway.

Current tracks (all in the `RaceServer.Tracks` ModuleScript). Each round the vote offers 3 of them at random (`VOTE_CHOICES`):
- **Rainbow Skyway** (Sky, vanilla, ~8600 studs): Into the Clouds (sweeping climb under a giant rainbow) → boost straight → Sunrise Curve → Cloud Bridge → Starlight Bend/Straight (cloud pillars) → Meadow Corner (Meadow Cut grass shortcut) → Sunset Sweep → Home Stretch. The grid is four karts wide.
- **Magma Mountain** (Lava, ~8400): Ember Fields → fork: Cinder Ridge or Lava Tube shortcut → Crater Hall inside the hollow volcano → Magma Depths → Sulfur Flats → Obsidian Bridges (no rails, fire bar) → Basalt Forest → Ashfall Canyon → Lava River Jump. Drop through the jump's hole to land on the Lava Falls Loop below, skipping most of it. Then Fire Temple → Temple Gate finish.
- **Frosty Peaks** (Snow, ~6900): Avalanche Pass → Pass Gate fork: Crystal Cave or Windy Ledge → Sky Rink → Frozen Bridge → Ski Jump → Snowy Lodge → Forest Clearing fork: Pine Forest or Ice Slide (icy, rail-less) → Snowman Village → Glacier Canyon → Frostbite Hills → finish.
- **Jungle Ruins** (Jungle, ~6800): River Crossing (rope bridges) → Boulder Steps → The Waterfall fork: Cliff Road or the Secret Cave hidden behind the waterfall → Temple of the Sun (a hall inside the hollow pyramid, water geysers) → Temple Stairs (boulders) → The Ravine: long rope bridge, or the Ravine Leap (needs a boost) → Mud Flats (all mud, with a line of boost pads) → Vine Tunnel → Crocodile Creek → finish.

## Layout
- `RaceServer` → Script in ServerScriptService. Builds the lobby, and builds whichever track won the vote procedurally from its entry in `TRACKS` (POINTS + FEATURES + optional BRANCHES; looks come from `THEMES`, shared build settings from `TRACK`). `TRACKS` lives in the `Tracks` ModuleScript inside RaceServer; the big comment at its top lists every feature kind. Only one `workspace.RaceTrack` exists at a time; `loadTrack` replaces it (with its `Scenery` subfolder and lighting) when a different track wins. Runs the race state machine (Waiting → Intermission/track vote → Reveal → Countdown → Racing → Results), checkpoints, placements, respawns (automatic below the track's `KillY` attribute, in lava, or manual), DataStore wins leaderboard.
- Track building: `planRoute` works out one road (the main road or a branch).
  - It samples the curve every `STEP` studs and works out the road's width at each sample (`Room`s flare out over `ROOM_EASE`), plus the off-road strips (`route.edge` = road plus off-road).
  - It works out banking (flat in rooms and at the road's ends) and the sections.
  - `buildRoute` builds it. Off-road is one sheet from wall to wall, 0.15 studs below the road (its parts carry an `OffRoad` attribute); the road sits on top.
  - Where two roads overlap (a branch joining a Room), walls, curbs, off-road and pillars open up by themselves (`route.covers`, with `roadOnly` to ignore off-road).
  - Branch ends must sit inside a main-road Room, on flat road at the same height.
- Scenery that roads pass through is hollow, with openings cut where roads go: the volcano (`buildCrater`) and the jungle pyramid (`buildPyramid`). The ground (lava sea, cloud sea, river) is tiled, because a part can't be longer than 2048 studs.
- `RaceClient` → LocalScript in StarterPlayerScripts. Arcade kart physics (client has network ownership of its kart after GO), drift/mini-turbo, hazards and bumping, chase camera, HUD, track vote cards, weather particles. It looks up `workspace.RaceTrack` fresh (it gets replaced), never caches it.
- Server ↔ client communication: attributes on `ReplicatedStorage.RaceState` (incl. `TrackId`/`TrackName`, vote `Option1..3`/`Votes1..3`, and a `Tracks` folder with each track's name/blurb/colour) and on each Player (`Racing`, `Finished`, `Place`, `Vote`, `RaceCoins`, `Item`, `Checkpoint` = the next gate the server is waiting for, handy when testing), plus the `ReplicatedStorage.RaceEvent` RemoteEvent (client → server: `Respawn` with optional reason `"Lava"`, `Vote`, `UseItem`; server → client: `Respawned`, `RacerFinished`, `TimeUp`, `Results`, `CoinsEarned`).
- Track folders: `RaceTrack.Road` (driveable surfaces — the client's ground raycasts only hit this; ice pieces carry a `Grip` attribute), `Walls` (barriers and solid obstacles), `Decor` (non-collidable visuals), `Hazards`, `Pickups` (coins and item boxes), `Scenery`, `Checkpoints`, `RespawnPoints`, `StartSlots`, `StartLights`. The road is built from WedgePart triangles that share exact edges (`buildTriangle`) — don't go back to overlapping boxes, that's what made collisions glitchy.
- Hazards: parts in `RaceTrack.Hazards` carry a `Hazard` attribute that the client feels for with `GetPartsInPart` on its hitbox:
  - `Burn`: lava, sends you back to your respawn point.
  - `Bonk`: fire bars, snowballs and boulders, knock you aside and spin you out.
  - `Launch`: geysers (lava, or water in the jungle), throw you up.
  - `Wind`: pushes you sideways during gusts.

  The server builds hazards static and never moves them. Each client animates the moving ones in step with `workspace:GetServerTimeNow()` (attributes `Origin`/`Speed`, `From`/`To`/`Period`/`Offset`, `Period`/`Active`/`Offset`/`Height`), so everyone sees the same thing.
- Checkpoints vs respawn points: checkpoints (must be passed in order) only go on road every route shares. There are none on main road that a branch or a `Skippable` drop shortcut skips, none in a gap-jump run-up (`JUMP_RUNWAY`), and none next to a hazard that reaches the middle of the road (`HAZARD_CLEARANCE`). `RespawnPoints` are optional gates on every route, branches included. You respawn at whichever gate you went through last.
  - A racer may miss up to `CHECKPOINT_SKIP` (3) checkpoints in a row; passing any of the next 3 still counts. Big jumps can fly right over gates: for example, coming off Magma's Lava River Jump angled left lands you on the road below, past checkpoints 41 and 42. It's safe because no checkpoint's pass zone covers road near an earlier one; that was checked on all four tracks. Re-check that when adding a track whose roads run close together.
  - Every gate faces the race direction. The client uses the nearest one to show a blinking "WRONG WAY!" after 1 s of driving against it. This matters after Magma's drop: you land facing the wall, and the race goes left. Turning right takes you backwards up the Lava Falls Loop, where only respawn points update and you never reach the next checkpoint.
  - To test a route in Play, move your kart from the Server with `RaceEvent:FireClient(player, "Respawned", cframe)` (it also sets the kart's heading). Then watch the player's `Checkpoint` attribute. Moving the kart from the Client doesn't update the client's heading.
- Gap jumps (`Ramp` with `gap`): gap sizes were tuned by test: full speed clears by ~12 studs, below ~60 studs/s at the lip falls.
- Bumping is on for every track and is meant to be chaotic: a big shove, a hop, a random twist and a moment of slippery tyres (`BUMP_*` in the client's `HANDLING`; bots use the same values in `BOTS`). A track's `BUMPING` (default 1) becomes its `Bumping` attribute and scales the shove. Karts still pass through each other physically (collision groups), because client-owned karts colliding is laggy. Instead, each client shoves only its own kart away from nearby karts (`bumpKarts`). On ice the shove slides a long way.
- Coins and items (`PICKUPS` table in `RaceServer`; the client copies `MAX_COINS`, `COIN_SPEED` and `ITEM_BOOST_TIME` in `HANDLING`, so keep them the same):
  - `buildPickups` places them on every track by itself, clear of gaps, ramps/banners (`route.busy`) and hazards. Coins come in lines of 4 that swing from side to side down the main road, plus one line on each branch. Item boxes come in rows across the main road, only outside `skipped` zones (shortcut-bypassed road, jump run-ups, hazards), so every racer passes every row.
  - The server picks them up. Each frame it sweeps each kart's path since the last frame (`REACH`); bots collect too. A grabbed pickup is unparented and comes back after `RESPAWN_TIME` (1.5 s). The client spins them, plays the sounds and animates them from the `Pickups` folder's `ChildRemoved` (a fading copy flies up or bursts, with sparkles, and a sound from that spot) and `ChildAdded` (grows back in with a little bounce).
  - The server's word arrives a moment late, so the client predicts its own grabs. It sweeps its kart's path each frame with `PICKUP_REACH`, kept a bit under the server's `REACH`. When it hits one, it hides it locally (`LocalTransparencyModifier`) and bursts it at once with the sound in your ears, and remembers it in `predicted`. When the server later removes that pickup, it doesn't burst again. If the server never takes it (1.5 s), it pops back. The HUD coin count adds predicted coins (`shownCoins`). The counts that matter (coins, items, speed) still come from the server.
  - Item boxes show "?" with a SurfaceGui on every face. Don't go back to one BillboardGui inside the see-through box: it flickers.
  - Coins: up to `MAX_COINS` (20) per race, reset to 0 every race. Each coin carried adds 1% top speed (players and bots).
  - Items: one held at a time; a box gives a random one of `ITEMS`, all equally likely, whatever your place. `Boost` starts on the client the moment you press E (it owns its kart); the server just takes the item away. `TripleCoin` adds 3 coins on the server. Bots use theirs 1–4 s after grabbing it.
  - Payout (`payCoins`): finishers are paid as they cross the line, everyone else when the race ends. Amount = coins × 2 / 1.5 / 1.25 for 1st / 2nd / 3rd, rounded up; everyone else ×1. Totals are saved with `IncrementAsync` in the `Coins_v1` DataStore (key = user id) and shown as leaderstats `Coins`. Players who leave mid-race still get theirs saved. Spending coins later (a shop) should use `UpdateAsync` on the same key and refuse to go below 0.
- Controls while driving: W/S gas and brake, A/D steer, Space drift, E use item, Q look back (hold), R respawn. Gamepad: RB drift, X item, LB look back, Y respawn. On touch screens, ContextActionService adds DRIFT/ITEM/BACK/RESET buttons.
- Kart physics: the kart hovers at its `RideHeight` attribute on raycast springs (`senseGround` / `driveStep`, run in `RunService.PreSimulation`); the hitbox only ever touches walls. Wall hits are detected from unexpected velocity changes and deflect the kart. On off-road the top speed drops to `OFFROAD_SPEED` (unless boosting) and dust in the ground's colour flies off the wheels.
- CPU racers (bots): every race has 12 karts, so there are `MAX_RACERS` − (number of players) bots. Settings are in the `BOTS` table at the top of `RaceServer`.
  - Bots have no Player or Humanoid. The server owns their karts and drives them in its own `RunService.PreSimulation` loop (`driveBot`) with the same hover physics as players. Their karts carry a `Bot` attribute, and the driver is welded parts with a name tag (`addBotDriver`).
  - A bot keeps its name ("Blaze (CPU)"), `skill` (top-speed multiplier) and favourite lane from race to race.
  - Bots follow the main road only (`currentPath` = the main route that `buildTrack` returns) and never take branches. They pick a lane clear of obstacles (`scanForBots` collects rocks, posts and lava, plus fire bars, rollers and geysers as moving hazards). They slow for tight corners, use boost pads, and boost by themselves before gap jumps.
  - Hazards hit bots too. Clients animate the moving hazards, so the server works out where they are from the same attributes and the server clock. Wind and bumping work the same way.
  - A bot stuck for 2.5 s respawns at its last gate.
  - Rubber-banding (`CATCH_UP`): bots far behind the leading player speed up a little, bots far ahead slow down.
  - The race ends when every player has finished (or time runs out). Bots never hold it up.
  - It also ends as soon as only one racer is left on the track (e.g. 11th of 12 has finished). The last one, player or bot, is placed last with no finish time (shown as "—"), not DNF.
  - A win only counts on the leaderboard with at least `MIN_RACERS_FOR_WIN` players; bots don't count. In `RacerFinished`, bots have userId 0.
- Starting grid order (`startingGrid`): you start where you finished last race (`standings`), bots included. Anyone ahead who left drops out, so everyone behind moves up.
  - New players start at the very back, replacing the rearmost bots, in the order they joined (`joinedAt`). Bots fill whatever is left.
  - Run `require(game.ServerStorage.GridCheck:Clone())()` (game stopped) to check these rules.
- Grid spacing: `GRID_SIDE` (13) and `GRID_ROW` (16) are roomy on purpose, so bigger or customised karts still fit. A 12×16-stud kart fits on road at every slot on all tracks. The back row sits ~68 studs behind the start line, so keep it under `PRE_START` (80).
- Server size: Max Players is 12, set in Game Settings (a script can't change it; `Players.MaxPlayers` reads 60 in Studio).
- Seating: with 12 karts appearing at once, the client can learn "you sat down" before the seat itself arrives. Roblox's controls then never connect W/A/S/D to the seat. `startDriving` in `RaceClient` fixes this by calling `PlayerModule:GetControls():OnHumanoidSeated(true, seat)`. Never `require` the PlayerModule from MCP `execute_luau` on the Client: that makes a second copy of the controls, which steals the keyboard and breaks driving for the rest of the test.
- Lobby: server updates `StatusScreen` and `PodiumName1..3` labels; the client animates models with a `Spin` attribute and handles parts with a `BouncePower` attribute.
- Audio is all client-side, in `RaceClient`. Every sound's id, volume and optional `stretch` is in the `SOUNDS` table at the top; `playSound` / `loopSound` play them. `stretch` makes a sound last longer at the same pitch: it slows the sound down and raises the pitch back with a `PitchShiftSoundEffect`.
  - Every kart gets a looping engine sound whose pitch follows its speed (other players' karts too). Engines are quieter when idling, and other karts' engines are quieter and fade with distance sooner (`RollOffMinDistance` 6). Otherwise 12 engines on the grid are deafening.
  - Your own kart also gets: tyre squeal while drifting, a whoosh on boosts, a thump when landing, wall/obstacle hits, a boing when bumping karts, and hazard sounds.
  - Race sounds: countdown beeps (higher pitch for GO), a warpy whoosh on respawn, a coin blip (higher with every coin), a crystal shatter for item boxes (other racers' grabs play from where they happen), a jingle when you get an item, a victory fanfare when you finish, and a sad trombone on time up.
  - In the lobby, material-matched footsteps replace Roblox's default `Running` sound, which is muted.
  - Only use sounds that are free and public in the Creator Store. Prefer the licensed ProSoundEffects/APM uploads or `rbxasset://sounds/...` built-ins. Check a new id loads in Studio (`IsLoaded`, `TimeLength > 0`) before using it.

## Testing in Studio
- Through the MCP you can press Play, read the Output, run code on the Server/Client and take screenshots. Still ask the owner to drive it, because only a person can judge whether it's fun.
- Check a track layout before building it: with the game stopped, run `require(game.ServerStorage.TrackCheck:Clone())("Magma")`. It reports the length of each road and any spots where roads crash into each other (need 20+ studs of height between crossings), corners too tight for the road's width, or roads through the lobby.
- Switch tracks without waiting for a vote: in Play, run `game.ServerStorage.PreviewTrack:Invoke("Magma")` on the Server (Studio only). Don't do it mid-race with a kart you're testing (the kart keeps sensing the old track).
- Screenshots during a race show the kart camera. To look around freely, stop races from starting: on the Server set `Players.CharacterAutoLoads = false` and destroy the characters. Then pass a camera position to the screenshot tool.
- The place is published, so Studio prints DataStore "API access" messages for the leaderboard (`StudioAccessToApisNotAllowed`). That's expected unless "Enable Studio Access to API Services" is turned on (Game Settings → Security). With the place opened from the `.rbxlx` file instead of the published place, DataStores are off entirely ("You must publish this place"), so wins and coins aren't saved.
- Studio also prints errors from its own built-in plugins, such as `GameSettingsPlugin … Failed to parse secrets` and `builtin_ViewSelector … attempt to index nil with 'Parent'`. They don't come from the game; ignore them.
- `loadstring` only works in Edit mode (the game stopped), not on the Play server.

## Working rules
- The owner is new to Roblox development. Explain changes in plain language and say what to test in Studio.
- Edit scripts directly in Studio through the Roblox Studio MCP. There are no local script files. Remind the owner to save the place (Ctrl+S) so `KartRace.rbxlx` gets the changes before committing.
- Keep tunable values in the SETTINGS / TRACK / HANDLING tables at the top of each script.
- Validate anything the client sends to the server; clients can be exploited.
- Audience is young players: keep content age-appropriate and follow Roblox monetization rules (e.g. disclose odds for random paid items).
- Make the tracks truly unique. Give each one a specific name and theme, make it fun and wide enough for 12 players (see "Track design" above).
