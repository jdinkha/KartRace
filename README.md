# KartRace — Roblox Kart Racing

An arcade kart racing game for Roblox. Up to 12 racers (players plus CPU bots) vote on a track, then race from the start line to the finish, grabbing coins and item boxes along the way.


## Structure
- Open `KartRace.rbxlx` in Roblox Studio. All scripts live inside the place file:
  - `ServerScriptService.RaceServer`: lobby, track building, race rules, bots, coins.
  - `RaceServer.Tracks`: every track's layout.
  - `StarterPlayerScripts.RaceClient`: kart driving, camera, HUD and sounds.

<img width="2038" height="1200" alt="Screenshot (49)" src="https://github.com/user-attachments/assets/11b1e3be-5594-4fde-a5c7-074c3340f128" />
