# Karts, physics, controls and characters

Read before changing kart models, kart physics, controls, bumping, mascots/characters or grandstand fans.

## Karts and characters
- `buildKart` makes the "default" kart (rounded nose and sides, racing stripe, headlights, chunky tyres with hubcaps in the kart's colour, spoiler, twin exhausts). Players' karts and the lobby showroom use it too. Later kart customisation should add other shapes next to it, keeping the hitbox and seat where they are.
- The `Mascots` ModuleScript inside RaceServer holds the 15 characters as simple shape lists (rounded "Egg" parts are Parts with a Sphere `SpecialMesh`), plus `Mascots.build`, which makes bot drivers, grandstand fans and statues. Keep new characters friendly and original: the frog and cat were redesigned once because they looked too much like a meme and a famous brand.
- The one deliberate exception is **Feelsgood Fred** (`Fred`): the owner asked for a recognisable homage to the famous meme frog (big droopy-lidded eyes, wide lips, blue shirt), knowing the small copyright risk. Never use the original character's name anywhere in the game's code or text. He's a CPU racer ("Fred (CPU)"), cheers in Croaker Swamp's stands, sits crowned on top of its temple (`buildFred`) and on its billboard (`buildFredBillboard`, `FRED_BILLBOARD`).
- Grandstand fans are the theme's characters (`Crowd` in `THEMES`) in random team colours, arms up. Their parts are anchored; the fan model's `Cheer` attribute sets when it hops. The client makes them hop with `workspace:BulkMoveTo`, only when the camera is within 250 studs.

## Physics and bumping
- Kart physics: the kart hovers at its `RideHeight` attribute on raycast springs (`senseGround` / `driveStep`, run in `RunService.PreSimulation`); the hitbox only ever touches walls. Wall hits are detected from unexpected velocity changes and deflect the kart. On off-road the top speed drops to `OFFROAD_SPEED` (unless boosting) and dust in the ground's colour flies off the wheels. You can drift on off-road (from a lower speed, `DRIFT_MIN_SPEED` × `OFFROAD_SPEED`), but it charges no mini-turbo, and any charge is lost there; otherwise drifting through mud would cancel its slow-down.
- Bumping is on for every track and is meant to be chaotic: a big shove, a hop, a random twist and a moment of slippery tyres (`BUMP_*` in the client's `HANDLING`; bots use the same values in `BOTS`). A track's `BUMPING` (default 1) becomes its `Bumping` attribute and scales the shove. Karts still pass through each other physically (collision groups), because client-owned karts colliding is laggy. Instead, each client shoves only its own kart away from nearby karts (`bumpKarts`). On ice the shove slides a long way.

## Controls
- Controls while driving: W/S gas and brake, A/D steer, Space drift, E use item, Q look back (hold), R respawn. Gamepad: RB drift, X item, LB look back, Y respawn. On touch screens, ContextActionService adds DRIFT/ITEM/BACK/RESET buttons.
