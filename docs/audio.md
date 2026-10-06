# Audio

Read before adding or changing sounds or music.

- Audio is all client-side, in `RaceClient`. Every sound's id, volume and optional `stretch` is in the `SOUNDS` table at the top; `playSound` / `loopSound` play them. `stretch` makes a sound last longer at the same pitch: it slows the sound down and raises the pitch back with a `PitchShiftSoundEffect`.
  - Every kart gets a looping engine sound whose pitch follows its speed (other players' karts too). Engines are quieter when idling, and other karts' engines are quieter and fade with distance sooner (`RollOffMinDistance` 6). Otherwise 12 engines on the grid are deafening.
  - Your own kart also gets: tyre squeal while drifting, howling wind during gusts (wind zones also howl for everyone nearby), a whoosh on boosts, a thump when landing, wall/obstacle hits, a boing when bumping karts, and hazard sounds.
  - Frogs: a `Ribbit` each time a hopping frog leaps (and when one bonks you), a `Croak` from each idol just before its tongue lashes.
  - Race sounds: countdown beeps (higher pitch for GO), a warpy whoosh on respawn, a coin blip (higher with every coin), a wooden crack-and-splinter for item boxes (other racers' grabs play from where they happen), a jingle when you get an item, a victory fanfare when you finish, and a sad trombone on time up.
  - In the lobby, material-matched footsteps replace Roblox's default `Running` sound, which is muted.
  - Only use sounds that are free and public in the Creator Store. Prefer the licensed ProSoundEffects/APM uploads or `rbxasset://sounds/...` built-ins. Check a new id loads in Studio (`IsLoaded`, `TimeLength > 0`) before using it.
