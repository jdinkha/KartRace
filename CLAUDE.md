# KartRace — notes for Claude Code

Roblox kart racing game written in Luau. The scripts live in the place file (`KartRace.rbxlx`) and are edited in Studio through the Roblox Studio MCP. There are no local script files.

## Working rules
- The owner is new to Roblox development. Explain changes in plain language and say what to test in Studio.
- Make small, focused changes. Before a big feature or refactor, write a short plan and wait for the owner's OK.
- For open-ended design work (new track areas, shortcuts, items, rewards, UI), come up with 2–3 genuinely different ideas, say which you'd pick and why, and let the owner choose. For bug fixes and small tweaks, just do it.
- Keep tunable values in the tables at the top of each script (SETTINGS, TRACK, HANDLING, BOTS, PICKUPS, SOUNDS, THEMES). If a value is copied between server and client, change both.
- Validate anything the client sends to the server; clients can be exploited.
- Audience is young players: keep content age-appropriate and follow Roblox monetization rules (e.g. disclose odds for random paid items). Keep new characters friendly and original.
- Drivable road must have no clipping or unevenness: a step of more than 0.3 studs acts as a wall. `[RoadCheck]` finds these.

## Read the matching doc before working on a system
- `docs/track-design.md`: design rules for tracks (levels, not circuits), shortcuts, and every current track's route.
- `docs/track-building.md`: how roads, branches (and branches of branches), rooms, hollow scenery, Moonlight Manor's house, checkpoints, respawn points, jumps and grid spacing are built.
- `docs/hazards.md`: Burn/Bonk/Launch/Wind hazards, frogs, tongues, boost pad timing.
- `docs/coins-items.md`: pickups, client prediction, crash coin loss, items, payouts and coin saving.
- `docs/karts-characters.md`: kart models, the Garage (karts + wheels, garage menu), mascots, Feelsgood Fred, fans, hover physics, bumping, controls.
- `docs/bots-grid.md`: CPU racers, race-ending rules, starting grid order.
- `docs/audio.md`: the SOUNDS table, engines, effects, sound sourcing rules.
- `docs/blender.md`: rules for making models with the Blender MCP.

If you change a system, update its doc (or this file) to match.

## Overview
- `RaceServer` (Script, ServerScriptService): builds the lobby and the track picked for the next race, from `TRACKS` in the `Tracks` ModuleScript (POINTS + FEATURES + optional BRANCHES; looks from `THEMES`, build settings from `TRACK`). The big comment at the top of `Tracks` lists every feature kind. Moonlight Manor lives in `Tracks.Mansion`, and the `MansionBuilder` ModuleScript (inside RaceServer) builds its house. `Mascots` ModuleScript (ReplicatedStorage) holds the characters. Runs the race state machine (Waiting → Joining → Reveal → Countdown → Racing → Results), checkpoints, placements, respawns, bots, DataStore wins and coins.
- `RaceClient` (LocalScript, StarterPlayerScripts): kart physics (the client owns its kart after GO), drift, hazards, bumping, camera, HUD, the RACE menu and JOIN banner (vote cards in Vote mode), weather, all audio.
- `Garage` (ModuleScript, ReplicatedStorage): the karts and wheel sets players can pick, their templates (`Karts`/`Wheels` folders) and `Garage.build`. `GarageClient` (LocalScript, StarterPlayerScripts) is the garage menu.
- Server ↔ client: attributes on `ReplicatedStorage.RaceState` (`LobbyMode`, `TrackId`/`TrackName`, pick `NextTrack`/`Host`/`JoinedCount`, vote `Option1..3`/`Votes1..3`, a `Tracks` folder) and on each Player (`Racing`, `Finished`, `Place`, `Joined`, `Vote`, `RaceCoins`, `Item`, `Checkpoint`, `Kart`, `Wheels`, `Character`), plus the `ReplicatedStorage.RaceEvent` RemoteEvent (client → server: `Respawn` [reason `"Lava"`], `Start` [track id], `Join` [true/false], `Vote`, `UseItem`, `HitBanana` [a peel], `Crash`, `Equip` [`"Kart"`/`"Wheels"`/`"Character"`, id], `Bump` [a CPU's kart]; server → client: `Respawned` [reason `"Fell"`/`"Lava"`/`"Teleport"`], `RacerFinished`, `TimeUp`, `Results`, `CoinsEarned`, `CoinsLost`, `Mist`, `ItemNews`).
- Track folders under `workspace.RaceTrack`: `Road` (what ground raycasts hit; ice has a `Grip` attribute), `Walkable` (only on some tracks: solid ground off the road that the client's ground sensor also hits, e.g. Croaker Swamp's temple steps, Moonlight Manor's floors and lawn; not checked by RoadCheck or used by bots), `Walls`, `Decor`, `Hazards`, `Pickups`, `Scenery`, `Checkpoints`, `RespawnPoints`, `StartSlots`, `StartLights`.
- Lobby: the server updates `StatusScreen` and `PodiumName1..3`; the client animates `Spin` models and handles `BouncePower` parts.
- How races start (`SETTINGS.LOBBY_MODE`): `"Pick"` (default): nobody is pulled into a race, so players can stay in the lobby as long as they like. A player presses RACE, picks a track (`Start`), and everyone else in the lobby has `JOIN_TIME` seconds to `Join` (`pickRound`). Only one race runs at a time. While it runs, a player in the lobby can line up the next one, whose join countdown starts when the race ends. `"Vote"` brings back the old loop (`voteRound`): everyone in the lobby votes between 3 tracks every round, then races. Both call `runRace(humans)`.
- Server size: Max Players is 12, set in Game Settings (`Players.MaxPlayers` reads 60 in Studio).

## Gotchas (don't undo these)
- Only one `workspace.RaceTrack` exists at a time and `loadTrack` replaces it. The client must look it up fresh, never cache it.
- The road is WedgePart triangles sharing exact edges (`buildTriangle`). Don't go back to overlapping boxes: that made collisions glitchy.
- The server builds hazards static; each client animates moving ones from `workspace:GetServerTimeNow()`, and the server computes the same positions for bots.
- Item boxes use a SurfaceGui on every face. A single BillboardGui inside the see-through box flickers.
- Seating fix: `startDriving` calls `PlayerModule:GetControls():OnHumanoidSeated(true, seat)`. Never `require` the PlayerModule from MCP `execute_luau` on the Client: it makes a second copy of the controls and breaks driving for the rest of the test.

## Before saying a change is done
1. Playtest through the MCP and check the Output for new errors (ignore the known Studio plugin errors below).
2. Track changes: run TrackCheck on that track, then load it in Play (`PreviewTrack`) and fix every `[RoadCheck]` warning. Grid/standings changes: run GridCheck.
3. Visual changes: take a screenshot and look at it.
4. Tell the owner what to try by hand. Only a person can judge if it's fun.

## Testing in Studio
- Through the MCP you can press Play, read the Output, run code on the Server/Client and take screenshots.
- Track layout check (game stopped): `require(game.ServerStorage.TrackCheck:Clone())("Magma")`. Reports road lengths, roads crashing into each other (need 20+ studs of height between crossings), corners too tight for the road's width (TIGHT), and roads through the lobby.
- Road surface check: in Studio, `checkRoads` runs every time a track loads and prints `[RoadCheck] <track>: no steps or holes in the road` or one warning per hole/step (positions in POINTS numbers). It skips jump gaps, ramp lips and boost pads. Moonlight Manor also prints `[MansionCheck]`: any house wall or floor in a road's way.
- Bot run: start a race with no input and watch the CPUs; on Moonlight Manor they all finish in about 2:00–2:15. A bot sitting still for 10+ s means a spot it can't drive through.
- Grid check (game stopped): `require(game.ServerStorage.GridCheck:Clone())()`.
- Switch tracks in Play (Server, Studio only): `game.ServerStorage.PreviewTrack:Invoke("Magma")`. Not mid-race with a kart you're testing.
- Give a racer an item mid-race (Server, Studio only): `game.ServerStorage.GiveItem:Invoke("Player1", "Banana")`. Boost and Mega Jump need a real E press (`user_keyboard_input`); the rest can be used by firing `UseItem` from the Client.
- Move a kart to test a route: from the Server, `RaceEvent:FireClient(player, "Respawned", cframe)`, then watch the player's `Checkpoint` attribute. Moving it from the Client doesn't update its heading.
- Free-look screenshots: on the Server set `Players.CharacterAutoLoads = false` and destroy the characters, then pass a camera position to the screenshot tool. The tool sometimes ignores the position, renders in daylight or hangs for minutes: retry from another spot, or move the kart with `Respawned` and capture without a position.
- DataStore messages (`StudioAccessToApisNotAllowed`) are expected unless "Enable Studio Access to API Services" is on. Opened from the `.rbxlx` file instead of the published place, DataStores are off entirely.
- Ignore Studio's own plugin errors, e.g. `GameSettingsPlugin … Failed to parse secrets` and `builtin_ViewSelector … attempt to index nil with 'Parent'`.
- `loadstring` only works in Edit mode, not on the Play server.
