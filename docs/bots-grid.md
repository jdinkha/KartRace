# CPU racers and starting grid

Read before changing bot behaviour, race-ending rules, rubber-banding or starting grid order.

## Bots
- CPU racers (bots): every race has 12 karts, so there are `MAX_RACERS` − (number of players) bots. Settings are in the `BOTS` table at the top of `RaceServer`.
  - Bots have no Player or Humanoid. The server owns their karts and drives them in its own `RunService.PreSimulation` loop (`driveBot`) with the same hover physics as players. Their karts carry a `Bot` attribute. Each bot drives as its own cartoon character (`BOTS.MASCOTS`: Pickle the frog, Comet the penguin, Bolt the robot…), welded into the kart with a name tag (`addBotDriver`), and its kart is the character's colour.
  - A bot keeps its name ("Blaze (CPU)"), `skill` (top-speed multiplier) and favourite lane from race to race.
  - Bots follow the main road only (`currentPath` = the main route that `buildTrack` returns) and never take branches. They pick a lane clear of obstacles (`scanForBots` collects every `Obstacle` part, trees, fire bar posts and lava, plus fire bars, rollers, hopping frogs, idol tongues and geysers as moving hazards): 9 lanes are tried 60 studs ahead, then 26 ahead, so they weave through a thick forest. They slow for tight corners, use boost pads, and boost by themselves before gap jumps.
  - Hazards hit bots too. Clients animate the moving hazards, so the server works out where they are from the same attributes and the server clock. Wind and bumping work the same way.
  - A bot stuck for 2.5 s respawns at its last gate.
  - Rubber-banding (`CATCH_UP`): bots far behind the leading player speed up a little, bots far ahead slow down.
  - The race ends when every player has finished (or time runs out). Bots never hold it up.
  - It also ends as soon as only one racer is left on the track (e.g. 11th of 12 has finished). The last one, player or bot, is placed last with no finish time (shown as "—"), not DNF.
  - A win only counts on the leaderboard with at least `MIN_RACERS_FOR_WIN` players; bots don't count. In `RacerFinished`, bots have userId 0.

## Starting grid order
- Starting grid order (`startingGrid`): you start where you finished last race (`standings`), bots included. Anyone ahead who left drops out, so everyone behind moves up.
  - New players start at the very back, replacing the rearmost bots, in the order they joined (`joinedAt`). Bots fill whatever is left.
  - Run `require(game.ServerStorage.GridCheck:Clone())()` (game stopped) to check these rules.
