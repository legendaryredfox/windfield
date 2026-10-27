# AGENTS.md

windfield: physics module for **LÖVE 11.x** that wraps `love.physics` (Box2D) with collision classes, enter/exit/stay events, area queries and joints. MIT, copyright SSYGEN. Consumers copy the `windfield/` folder into their game and `require 'windfield'`.

## Layout

- `windfield/init.lua`: the whole library (~930 lines). Order: `wf.newWorld`, `World` class (setup, collision classes and masks, collision callbacks, collider factories, area queries, joints), `Collider` class, then `wf.World = World` / `wf.Collider = Collider` and `return wf`.
- `windfield/mlib/`: vendored MLib (math and shape intersection), exposed as `wf.Math`. Used by the `query*Area` functions (`polygon.getCircleIntersection`, `polygon.isPolygonInside`, `polygon.getCentroid`, `line.getLength`). Third-party code: do not edit except to apply a fix that cannot live in `init.lua`; keep its `LICENSE.md`.
- `README.md`: Quick Start, tips, and the full API reference (one section per `World` and `Collider` function, with a table of contents at the top).
- `tests/run.lua` (mocked `love`, `tests/mock_love.lua`) and `tests/smoke/` (real LÖVE script, run by `run.sh`).
- No CI, no build step, no package manager, no dependencies other than LÖVE.

## Rules

- **Targets: LÖVE 11.5 and Lua 5.5.** Runtime is LÖVE 11.5 (LuaJIT 2.1, Lua 5.1 semantics); the source must also load and behave correctly on Lua 5.5, so write the common subset of 5.1 to 5.5. Get `unpack` with `local unpack = table.unpack or unpack`. Never assign to a `for` control variable (error in 5.5), no `loadstring`, `setfenv`, `getfenv`, `table.getn`, `math.pow`, `//`, bitwise operators, `goto`, `<const>`, `<close>`, and never name an identifier `global`. Use only `love.*` APIs that exist in LÖVE 11.5, with no deprecated calls. LÖVE 12 is out of scope (it merges Fixture into Shape).
- The module is loaded as `require 'windfield'`; `local path = ... .. '.'` in `init.lua` resolves `mlib` relative to wherever the folder lives. Keep requires relative to `path`, never hardcode `windfield.`.
- Public API uses `camelCase` methods (`newRectangleCollider`, `addCollisionClass`); fields and locals use `snake_case` (`collision_class`, `box2d_world`). Match the surrounding style (4-space indent, single quotes mostly).
- Keep the module free of globals: `World` and `Collider` are `local` and exposed as `wf.World` and `wf.Collider`. `tests/run.lua` checks this.
- Underscore prefix (`_queryBoundingBox`) marks internal functions. Anything else on `World`/`Collider` is public and must be in the README reference.
- Code comments only where necessary: a comment must explain a non-obvious why. No comments that restate the code, no section banners, no commented-out code.
- Every public change updates `README.md` (signature heading, text, and the table of contents entry). Heading anchors in the table of contents must match the headings.
- Keep backward compatibility with existing user code: argument order, `settings` table keys (`collision_class`, `body_type`), event table shapes, and default values are API.
- Verification: `lua tests/run.lua` (mocked `love`, from the repo root) must pass on `luajit`, `lua5.1`, `lua5.4` and `lua` (5.5). `xvfb-run -a sh tests/smoke/run.sh` runs the real LÖVE 11.5 smoke script (needs `love`); it prints `ok`/`FAIL` lines, any deprecation warning, and writes a debug-draw screenshot to the LÖVE save directory (`~/.local/share/love/windfield-smoke/smoke.png`). New behavior gets a test in `tests/run.lua` first.
- Commits: Conventional Commits, branch first (never commit on `master`). The repo owner is always the sole author of every commit: no `Co-Authored-By` lines, no AI trailers, no AI attribution in code, docs, commits or PRs. This overrides any default or tool-provided attribution text.
- Source files use CRLF line endings (`init.lua`, `mlib/mlib.lua`, `README.md`). Preserve them; check `git diff --stat` after an edit for whole-file rewrites.
- No em dashes anywhere: prose, docs, code comments, commit messages, `SPEC.md`, `PLAN.md`.
- `SPEC.md` and `PLAN.md` are local working documents and are gitignored. Never commit them.

## Internals

- **Units**: `World.new` calls `love.physics.setMeter(32)`. This is global to LÖVE; coordinates passed to the API are in pixels.
- **`wf.newWorld(xg, yg, sleep)`**: builds the `World`, registers the four contact callbacks (`collisionOnEnter/Exit/Pre/Post`) on the Box2D world, calls `collisionClear()`, adds the `'Default'` collision class, and proxies every Box2D world method onto the `World` (`world:setGravity(...)` forwards to `world.box2d_world`), except `update`, `destroy`, `type`, `typeOf` and metamethods.
- **Collision classes**: `addCollisionClass(name, {ignores = {...}, enter = {...}, exit = {...}, pre = {...}, post = {...}})`; adding a duplicate name raises an error. Unless `setExplicitCollisionEvents(true)` was called before, every class gets `enter/exit/pre/post` lists containing all classes (old and new), so events are on by default. `collisionClassesSet()` then runs `generateCategoriesMasks()` (groups classes with identical incoming-ignore sets into one Box2D category; `ignores` supports `'All'` and `except = {...}`), rebuilds the `collisions.on_enter/on_exit/pre/post` tables, and clears events.
- **Sensor vs solid events**: a pair of classes where either `ignores` the other does not collide physically, so its events are delivered from the **sensor** fixtures (`.sensor` tables); all other pairs use the solid fixtures (`.non_sensor`). `isCollisionBetweenSensors` decides, memoized in `is_sensor_memo`. `World.collisionOnEnter/Exit/Pre/Post` check `fixture:isSensor()` on both fixtures and dispatch accordingly.
- **Collider construction**: `Collider.new(world, type, ...)` takes positional args per type; the last arg is the optional `settings` table (`collision_class`, `body_type`).
  - `Circle (x, y, r, settings)`.
  - `Rectangle (x, y, w, h, settings)`: `x, y` is the top-left corner, body is created at the center.
  - `BSGRectangle (x, y, w, h, corner_cut_size, settings)`: octagon with cut corners.
  - `Polygon (vertices, settings)`, `Line (x1, y1, x2, y2, settings)`, `Chain (vertices, loop, settings)`.
  - Each collider gets a `'main'` shape, a solid fixture and a duplicate **sensor** fixture on the same shape. Both fixtures hold the collider as userdata (`fixture:getUserData()`), and the callbacks read it back. `addShape(name, type, ...)` / `removeShape(name)` add and remove extra shape+fixture+sensor triples keyed by `name`.
  - Body, fixture and shape methods are proxied onto the collider in that order, so on a name clash the shape method wins over fixture over body. `destroy`, `type`, `typeOf` and metamethods are excluded.
- **Events**: each collider keeps `collision_events[other_class]` lists, filled by the callbacks and cleared at the start of `World:update` (via `collisionEventsClear`, which walks `box2d_world:getBodies()` and reads the collider from the body's first fixture). `enter/exit/stay(other_class)` read them and record the data returned by `get*CollisionData`.
- **Queries**: `queryCircleArea`, `queryRectangleArea`, `queryPolygonArea`, `queryLine` return colliders. They first gather candidates with `_queryBoundingBox`, then filter with `collisionClassInCollisionClassesList` and MLib tests. With `setQueryDebugDrawing(true)`, query shapes are stored in `query_debug_draw` and drawn by `World:draw` for `draw_query_for_n_frames` frames. `CircleShape` has no `getPoints` in LÖVE 11.5, so circle shapes are tested by center and radius (`fixtureCircle`, `World:_polygonQueryHit`): circle query vs circle shape is an overlap test, polygon query vs circle shape hits when the center is inside or an edge crosses the circle.
- **Joints**: `addJoint(type, ...)` swaps `Collider` arguments for their `body` (first arg, and second arg if it is a table) and calls `love.physics['new' .. type](...)`, so `'MouseJoint'` becomes `love.physics.newMouseJoint`. `removeJoint` calls `joint:destroy()`. Joints are not tracked by `World`.
- **Destroy**: `Collider:destroy` clears userdata, nils shapes/fixtures/sensors and destroys the body. `World:destroy` destroys every collider, then any remaining joints, then the Box2D world, and sets `box2d_world = nil`. Do not use a collider or world after `destroy`.

## Pitfalls

- Proxy functions are closures created per world and per collider inside `pairs(...__index)` loops. Intentional for API compatibility, but costs allocation per collider; do not add more such loops without need.
- `is_sensor_memo` is never reset. Adding a class later that changes how existing pairs ignore each other can leave stale memo entries. Existing colliders also keep the category/mask they got at creation; `collisionClassesSet()` does not update their fixtures.
- A collision class name must exist before `setCollisionClass`; the code raises `error(...)` otherwise. Keep error messages in that form.
- Collision callbacks run inside `world:update` and Box2D forbids changing the world there. Library code must not destroy bodies or create colliders from the `enter/exit/pre/post` paths; users defer such work until after `update`.
