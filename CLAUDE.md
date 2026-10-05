# KartRace — notes for Claude Code

Roblox kart racing game written in Luau, synced into Roblox Studio with Rojo (`default.project.json`).

## Layout
- `RaceServer` → Script in ServerScriptService. Builds the lobby, and builds whichever track won the vote procedurally from its entry in `TRACKS` (POINTS + FEATURES; looks come from `THEMES`, shared build settings from `TRACK`). Only one `workspace.RaceTrack` exists at a time; `loadTrack` replaces it (with its `Scenery` subfolder and lighting) when a different track wins. Runs the race state machine (Waiting → Intermission/track vote → Reveal → Countdown → Racing → Results), checkpoints, placements, respawns (automatic below the track's `KillY` attribute, or manual), DataStore wins leaderboard.
- `RaceClient` → LocalScript in StarterPlayerScripts. Arcade kart physics (client has network ownership of its kart after GO), drift/mini-turbo, chase camera, HUD, track vote cards, weather particles. It looks up `workspace.RaceTrack` fresh (it gets replaced), never caches it.
- Server ↔ client communication: attributes on `ReplicatedStorage.RaceState` (incl. `TrackId`/`TrackName`, vote `Option1..3`/`Votes1..3`, and a `Tracks` folder with each track's name/blurb/colour) and on each Player (`Racing`, `Finished`, `Place`, `Vote`), plus the `ReplicatedStorage.RaceEvent` RemoteEvent (`Respawn`, `Vote`).
- Track folders: `RaceTrack.Road` (driveable surfaces — the client's ground raycasts only hit this; ice pieces carry a `Grip` attribute), `Walls`, `Decor` (non-collidable visuals), `Scenery`, `Checkpoints`, `StartSlots`, `StartLights`. The road is built from WedgePart triangles that share exact edges (`buildTriangle`) — don't go back to overlapping boxes, that's what made collisions glitchy.
- Gap jumps (`Ramp` with `gap`): checkpoints are kept out of the run-up (`JUMP_RUNWAY`) so a respawn always leaves room to reach full speed. Gap sizes were tuned by test: full speed clears by ~12 studs, below ~60 studs/s at the lip falls.
- Kart physics: the kart hovers at its `RideHeight` attribute on raycast springs (`senseGround` / `driveStep`, run in `RunService.PreSimulation`); the hitbox only ever touches walls. Wall hits are detected from unexpected velocity changes and deflect the kart.
- Lobby: server updates `StatusScreen` and `PodiumName1..3` labels; the client animates models with a `Spin` attribute and handles parts with a `BouncePower` attribute.

## Working rules
- The owner is new to Roblox development. Explain changes in plain language and say what to test in Studio.
Edit scripts directly in Studio through the Roblox Studio MCP. There are no local script files
- You cannot run Studio. Ask the user to press Play and paste errors from the Output window.
- Keep tunable values in the SETTINGS / TRACK / HANDLING tables at the top of each script.
- Validate anything the client sends to the server; clients can be exploited.
- Audience is young players: keep content age-appropriate and follow Roblox monetization rules (e.g. disclose odds for random paid items).
- Make the tracks truly unique. Give each one a specific name and theme, make it fun and wide enough for 10 players