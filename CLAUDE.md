# KartRace — notes for Claude Code

Roblox kart racing game written in Luau, synced into Roblox Studio with Rojo (`default.project.json`).

## Layout
- `src/RaceServer.server.luau` → Script in ServerScriptService. Builds the track/lobby procedurally from `TRACK.POINTS`, runs the race state machine (Waiting → Intermission → Countdown → Racing → Results), checkpoints, placements, respawns, DataStore wins leaderboard.
- `src/RaceClient.client.luau` → LocalScript in StarterPlayerScripts. Arcade kart physics (client has network ownership of its kart after GO), drift/mini-turbo, chase camera, HUD.
- Server ↔ client communication: attributes on `ReplicatedStorage.RaceState` and on each Player (`Racing`, `Finished`, `Place`), plus the `ReplicatedStorage.RaceEvent` RemoteEvent.
- Track folders: `RaceTrack.Road` (driveable surfaces — the client's ground raycasts only hit this), `Walls`, `Decor` (non-collidable visuals), `Checkpoints`, `StartSlots`, `StartLights`. The road is built from WedgePart triangles that share exact edges (`buildTriangle`) — don't go back to overlapping boxes, that's what made collisions glitchy.
- Kart physics: the kart hovers at its `RideHeight` attribute on raycast springs (`senseGround` / `driveStep`, run in `RunService.PreSimulation`); the hitbox only ever touches walls. Wall hits are detected from unexpected velocity changes and deflect the kart.
- Lobby: server updates `StatusScreen` and `PodiumName1..3` labels; the client animates models with a `Spin` attribute and handles parts with a `BouncePower` attribute.

## Working rules
- The owner is new to Roblox development. Explain changes in plain language and say what to test in Studio.
- Rojo syncs files → Studio one way. Only edit files in `src/`; never tell the user to edit scripts in Studio.
- You cannot run Studio. Ask the user to press Play and paste errors from the Output window.
- Keep tunable values in the SETTINGS / TRACK / HANDLING tables at the top of each script.
- Validate anything the client sends to the server; clients can be exploited.
- Audience is young players: keep content age-appropriate and follow Roblox monetization rules (e.g. disclose odds for random paid items).
