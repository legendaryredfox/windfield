# Changelog

## 0.2.0

Core features: settings keys, fixed timestep, sensors, raycast, point queries, collider filter, one-way platforms and conveyors, LuaLS types. Source compatible except for the changes listed under Changed.

### Added

- `wf.newWorld(xg, yg, sleep, options)`: `options.meter` sets the LÖVE physics meter.
- Collider `settings` keys: `bullet`, `fixed_rotation`, `gravity_scale`, `linear_damping`, `angular_damping`, `sleeping_allowed`, `active`, `angle`, `restitution`, `friction`, `density`, `object`.
- `World:step(dt)`, `World:setFixedStep(dt, max_steps)` and `World:getAlpha()`: fixed time step stepping with an accumulator and a step cap.
- `Collider:setInterpolated`, `isInterpolated`, `getRenderPosition` and `getRenderAngle`: render interpolation between fixed steps.
- Sensors: `addCollisionClass(name, {sensor = true})`, the `sensor` collider setting, `Collider:setSensor` and `Collider:isSensor`.
- LuaLS type definitions in `types/windfield.lua` and a `.luarc.json`.
- `World:raycast(x1, y1, x2, y2, classes, mode)`: hits with point, normal and fraction, sorted by distance, or only the closest.
- `World:queryPoint(x, y, classes)` and `World:getColliderAt(x, y, classes)`: exact point queries.
- `World:setColliderFilter(fn)`: reject contacts between colliders from Lua, with no response and no events.
- Collision class options `one_way = {nx, ny}` (one-way platforms) and `conveyor = speed` (conveyor belts, in pixels per second).

### Changed

- `Collider:setSensor` and `Collider:isSensor` no longer reach the Box2D fixture. Calling `setSensor(true)` used to make the solid fixture a sensor and the collider reported no events (upstream issue 31); now it makes the whole collider a sensor with events.
- Collider constructors raise an error for unknown `settings` keys. Before, they were ignored.
- Colliders switched with `setSensor` and sensor classes are returned by the area, point and ray queries like any other collider; filter by class to leave them out. Before, `setSensor` through the fixture hid the collider from queries.
- Creating a world no longer resets the physics meter to `32` when the meter was already set by an earlier world.

## 0.1.0

Performance and event handling foundations. Public API stays source compatible; the behavior changes are listed below.

### Added

- `Collider:getEnters(class)` and `Collider:getExits(class)`: every enter or exit event of the current frame (`enter` and `exit` only report that one happened).
- `World:onEnter(class_a, class_b, callback)` and `World:onExit(...)`: callbacks that run after the physics step, with a handle that has `remove()`.
- Collision data (`getEnterCollisionData`, `getExitCollisionData`, `getStayCollisionData`, `getEnters`, `getExits`) now carries a copy of the contact geometry: `nx`, `ny`, `x1`, `y1`, `x2`, `y2`. The `contact` field is only valid during the physics step.
- `wf._VERSION`.
- Tests: mocked `love` suite (`tests/run.lua`), real LÖVE smoke script (`tests/smoke`), benchmark (`tests/bench`), `tests/run_all.sh`.

### Fixed

- Lua 5.5: `mlib` no longer assigns to a loop variable, `unpack` resolves on Lua 5.2 and later, `World` is no longer a global.
- `World:draw` used 0-255 colors; LÖVE 11 takes 0-1, so the debug drawing was always white. `draw(alpha)` still takes 0-255.
- `newChainCollider(vertices, loop)` passed its arguments to `newChainShape` in the wrong order.
- Area queries raised an error when a circle collider was in the query region.
- A failing collider constructor no longer leaves a body without fixtures in the world (which crashed `World:update`).
- Adding a collision class after colliders exist now updates the categories and masks of those colliders.
- A class no longer lists itself twice in its own event lists, which doubled events between colliders of the same class.

### Changed

- Colliders and worlds resolve LÖVE methods through `__index` instead of carrying one closure per method. `pairs(collider)` no longer lists method names.
- `stay(class)` is now tracked from the enter and exit events: it is true from the moment of an enter whether or not `enter()` was called, and colliders destroyed while touching are dropped.
- `collider:destroy()` called during the physics step (for example from `preSolve`) is carried out when the step ends. Destroying twice is harmless.
- The area query rules are now documented in the README: an area entirely inside a polygon collider does not return it.

### Performance

LÖVE 11.5 under xvfb, median of 3 runs (`sh tests/bench/run.sh --table`), 2000 bodies unless noted.

| Scenario | Before | After | Change |
|---|---|---|---|
| Create 2000 colliders | 72 ms | 37 ms | 1.9x faster |
| Memory per collider | 12.8 KB | 1.9 KB | 6.8x less |
| Idle update (per update) | 4.8 ms | 0.23 ms | 21x faster |
| Idle garbage (per update) | 532 KB | 0 KB | none |
| Pile of 400 boxes, update | 10.5 ms | 7.8 ms | 1.3x faster |
| Pile garbage (per update) | 123 KB | 30 KB | 4x less |
| 2000 rectangle queries, 1000 bodies | 520 ms | 293 ms | 1.8x faster |
| 2000 line queries, 1000 bodies | 32 ms | 17 to 37 ms | within noise |
| Churn, 300 create and 300 destroy per frame | 11.5 ms | 5.3 ms | 2.2x faster |
| Churn garbage (per frame) | 4320 KB | 664 KB | 6.5x less |
| 300 movers and 300 obstacles, per frame | 1.8 ms | 0.56 ms | 3.2x faster |

Rectangle queries stay far from raw `love.physics` because partly overlapping shapes still go through MLib's exact test; replacing it would change which edge-touching cases hit.

### Baseline before 0.1.0 (raw and windfield, full table)

LÖVE 11.5 under xvfb, median of 3 runs, `sh tests/bench/run.sh --table`. Run to run noise is roughly 20 percent on the create row.

| scenario | unit | raw love.physics | windfield | windfield + polling enter() |
| --- | --- | --- | --- | --- |
| create time | ms per 2000 | 4.903 | 95.859 | 59.411 |
| create memory | KB per collider | 0.071 | 12.762 | 12.730 |
| idle time | ms per update | 0.180 | 4.945 | 5.143 |
| idle garbage | KB per update | 0.000 | 531.695 | 531.695 |
| pile time | ms per update | 1.420 | 9.912 | 9.871 |
| pile garbage | KB per update | 0.000 | 122.778 | 127.141 |
| query time | ms per 2000 rect queries | 6.456 | 469.119 | 418.421 |
| ray time | ms per 2000 rays | 6.152 | 27.060 | 40.078 |
| churn time | ms per frame (300 create + 300 destroy) | 0.906 | 10.237 | 9.373 |
| churn garbage | KB per frame | 60.320 | 4320.423 | 4320.487 |
| movers time | ms per frame (300 movers, 300 obstacles) | 0.241 | 1.871 | n/a |
| movers garbage | KB per frame | 0.000 | 165.884 | n/a |
