# Hazards

Read before adding or changing hazards (lava, fire bars, frogs, tongues, geysers, wind, boost pad timing).

- Hazards: parts in `RaceTrack.Hazards` carry a `Hazard` attribute that the client feels for with `GetPartsInPart` on its hitbox:
  - `Burn`: lava, sends you back to your respawn point.
  - `Bonk`: fire bars, snowballs, boulders, hopping frogs and idol tongues, knock you aside and spin you out.
    - Hopping frogs (`Frog` feature, a model with `From`/`To`/`Period`/`Hops`/`Height`/`Offset`) cross the road and back in hops, crouching before each one; both sides work out the position with `hopAt` (server for bots, client to animate). `reverse` starts one on the right; a pair (`hops` 2, same timing, 8 studs apart along the road, one reversed) goes left, middle, right / right, middle, left and passes in the middle.
    - Frog idols (`Tongue` feature, a model with `Origin`/`Reach`/`Period`/`Active`/`Offset`) sit on the off-road. For 1 s their throat swells and goes from white to red (`THROAT_CALM` → `THROAT_ANGRY` in the client) and they croak, then the `Lash` part shoots `reach` studs across the road (never all the way).
  - Boost pads can give a longer boost: a `Boost` feature's `time` becomes the pad's `BoostTime` attribute (default `PAD_BOOST_TIME`, 1.2 s); the client and bots both read it.
  - `Launch`: geysers (lava, or water in the jungle), throw you up.
  - `Wind`: pushes you sideways during gusts (`push` studs/s², applied once per frame even where two wind zones overlap). Every piece of a wind zone has two emitters, `Gust` (long streaks) and `Flurry` (big bluish puffs), blowing the way it pushes; the client sets their rates: a few streaks always, more for 1 s as a warning, a storm during the gust. Every 4th piece (`Howl` attribute) gets a looping howl anyone nearby hears, louder in gusts; your own kart howls and the camera rattles while you're pushed. Streaks use `Orientation` VelocityParallel with a negative `Squash` (positive makes them stand upright like rain). Windy Ledge uses `push` 90, enough to blow an unsteered kart off in about a second.

  The server builds hazards static and never moves them. Each client animates the moving ones in step with `workspace:GetServerTimeNow()` (attributes `Origin`/`Speed`, `From`/`To`/`Period`/`Offset`, `Period`/`Active`/`Offset`/`Height`), so everyone sees the same thing.
