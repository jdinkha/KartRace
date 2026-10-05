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
- **Frosty Peaks** (Snow, bumping on, ~6900): Avalanche Pass → Pass Gate fork: Crystal Cave or Windy Ledge → Sky Rink → Frozen Bridge → Ski Jump → Snowy Lodge → Forest Clearing fork: Pine Forest or Ice Slide (icy, rail-less) → Snowman Village → Glacier Canyon → Frostbite Hills → finish.
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
- Server ↔ client communication: attributes on `ReplicatedStorage.RaceState` (incl. `TrackId`/`TrackName`, vote `Option1..3`/`Votes1..3`, and a `Tracks` folder with each track's name/blurb/colour) and on each Player (`Racing`, `Finished`, `Place`, `Vote`), plus the `ReplicatedStorage.RaceEvent` RemoteEvent (`Respawn` with optional reason `"Lava"`, `Vote`).
- Track folders: `RaceTrack.Road` (driveable surfaces — the client's ground raycasts only hit this; ice pieces carry a `Grip` attribute), `Walls` (barriers and solid obstacles), `Decor` (non-collidable visuals), `Hazards`, `Scenery`, `Checkpoints`, `RespawnPoints`, `StartSlots`, `StartLights`. The road is built from WedgePart triangles that share exact edges (`buildTriangle`) — don't go back to overlapping boxes, that's what made collisions glitchy.
- Hazards: parts in `RaceTrack.Hazards` carry a `Hazard` attribute that the client feels for with `GetPartsInPart` on its hitbox:
  - `Burn`: lava, sends you back to your respawn point.
  - `Bonk`: fire bars, snowballs and boulders, knock you aside and spin you out.
  - `Launch`: geysers (lava, or water in the jungle), throw you up.
  - `Wind`: pushes you sideways during gusts.

  The server builds hazards static and never moves them. Each client animates the moving ones in step with `workspace:GetServerTimeNow()` (attributes `Origin`/`Speed`, `From`/`To`/`Period`/`Offset`, `Period`/`Active`/`Offset`/`Height`), so everyone sees the same thing.
- Checkpoints vs respawn points: checkpoints (must be passed in order) only go on road every route shares. There are none on main road that a branch or a `Skippable` drop shortcut skips, none in a gap-jump run-up (`JUMP_RUNWAY`), and none next to a hazard that reaches the middle of the road (`HAZARD_CLEARANCE`). `RespawnPoints` are optional gates on every route, branches included. You respawn at whichever gate you went through last.
- Gap jumps (`Ramp` with `gap`): gap sizes were tuned by test: full speed clears by ~12 studs, below ~60 studs/s at the lip falls.
- Bumping: a track's `BUMPING` becomes the track's `Bumping` attribute. Karts still pass through each other physically (collision groups), because client-owned karts colliding is laggy. Instead, each client shoves only its own kart away from nearby karts (`bumpKarts`). On ice the shove slides a long way.
- Kart physics: the kart hovers at its `RideHeight` attribute on raycast springs (`senseGround` / `driveStep`, run in `RunService.PreSimulation`); the hitbox only ever touches walls. Wall hits are detected from unexpected velocity changes and deflect the kart. On off-road the top speed drops to `OFFROAD_SPEED` (unless boosting) and dust in the ground's colour flies off the wheels.
- Lobby: server updates `StatusScreen` and `PodiumName1..3` labels; the client animates models with a `Spin` attribute and handles parts with a `BouncePower` attribute.
- Audio is all client-side, in `RaceClient`. Every sound's id, volume and optional `stretch` is in the `SOUNDS` table at the top; `playSound` / `loopSound` play them. `stretch` makes a sound last longer at the same pitch: it slows the sound down and raises the pitch back with a `PitchShiftSoundEffect`.
  - Every kart gets a looping engine sound whose pitch follows its speed (other players' karts too).
  - Your own kart also gets: tyre squeal while drifting, a whoosh on boosts, a thump when landing, wall/obstacle hits, a boing when bumping karts, and hazard sounds.
  - Race sounds: countdown beeps (higher pitch for GO), a ding on respawn, a victory fanfare when you finish, and a sad trombone on time up.
  - In the lobby, material-matched footsteps replace Roblox's default `Running` sound, which is muted.
  - Only use sounds that are free and public in the Creator Store. Prefer the licensed ProSoundEffects/APM uploads or `rbxasset://sounds/...` built-ins. Check a new id loads in Studio (`IsLoaded`, `TimeLength > 0`) before using it.

## Testing in Studio
- Through the MCP you can press Play, read the Output, run code on the Server/Client and take screenshots. Still ask the owner to drive it, because only a person can judge whether it's fun.
- Check a track layout before building it: with the game stopped, run `require(game.ServerStorage.TrackCheck:Clone())("Magma")`. It reports the length of each road and any spots where roads crash into each other (need 20+ studs of height between crossings), corners too tight for the road's width, or roads through the lobby.
- Switch tracks without waiting for a vote: in Play, run `game.ServerStorage.PreviewTrack:Invoke("Magma")` on the Server (Studio only). Don't do it mid-race with a kart you're testing (the kart keeps sensing the old track).
- Screenshots during a race show the kart camera. To look around freely, stop races from starting: on the Server set `Players.CharacterAutoLoads = false` and destroy the characters. Then pass a camera position to the screenshot tool.
- The place is published, so Studio prints DataStore "API access" messages for the leaderboard. That's expected unless "Enable Studio Access to API Services" is turned on.

## Working rules
- The owner is new to Roblox development. Explain changes in plain language and say what to test in Studio.
- Edit scripts directly in Studio through the Roblox Studio MCP. There are no local script files. Remind the owner to save the place (Ctrl+S) so `KartRace.rbxlx` gets the changes before committing.
- Keep tunable values in the SETTINGS / TRACK / HANDLING tables at the top of each script.
- Validate anything the client sends to the server; clients can be exploited.
- Audience is young players: keep content age-appropriate and follow Roblox monetization rules (e.g. disclose odds for random paid items).
- Make the tracks truly unique. Give each one a specific name and theme, make it fun and wide enough for 12 players (see "Track design" above).
