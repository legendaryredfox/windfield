**windfield** is a physics module for LÖVE. It wraps LÖVE's physics API so that using box2d becomes as simple as possible.

# Contents

* [Quick Start](#quick-start)
   * [Create a world](#create-a-world)
   * [Create colliders](#create-colliders)
   * [Create joints](#create-joints)
   * [Create collision classes](#create-collision-classes)
   * [Capture collision events](#capture-collision-events)
   * [Query the world](#query-the-world)
* [Examples & Tips](#examples--tips)
   * [Checking collisions between game objects](#checking-collisions-between-game-objects)
   * [One-way Platforms](#one-way-platforms)
* [Editor support](#editor-support)
* [Documentation](#documentation)
   * [World](#world)
      * [newWorld](#newworldxg-yg-sleep-options)
      * [newTimer](#newtimerduration)
      * [update](#updatedt)
      * [step](#stepdt)
      * [setFixedStep](#setfixedstepdt-max_steps)
      * [getAlpha](#getalpha)
      * [draw](#drawalpha_or_options)
      * [destroy](#destroy)
      * [addCollisionClass](#addcollisionclasscollision_class_name-collision_class)
      * [Collider settings](#collider-settings)
      * [newCircleCollider](#newcirclecolliderx-y-r)
      * [newRectangleCollider](#newrectanglecolliderx-y-w-h)
      * [newBSGRectangleCollider](#newbsgrectanglecolliderx-y-w-h-corner_cut_size)
      * [newPolygonCollider](#newpolygoncollidervertices)
      * [newConcavePolygonCollider](#newconcavepolygoncollidervertices-settings)
      * [newLineCollider](#newlinecolliderx1-y1-x2-y2)
      * [newChainCollider](#newchaincollidervertices-loop)
      * [queryCircleArea](#querycircleareax-y-r-collision_class_names)
      * [queryRectangleArea](#queryrectangleareax-y-w-h-collision_class_names)
      * [queryPolygonArea](#querypolygonareavertices-collision_class_names)
      * [queryLine](#querylinex1-y1-x2-y2-collision_class_names)
      * [raycast](#raycastx1-y1-x2-y2-collision_class_names-mode)
      * [queryShape](#queryshapeshape_def-x-y-collision_class_names)
      * [shapeCast](#shapecastshape_def-x-y-dx-dy-collision_class_names)
      * [queryPoint](#querypointx-y-collision_class_names)
      * [getColliderAt](#getcollideratx-y-collision_class_names)
      * [addJoint](#addjointjoint_type-)
      * [removeJoint](#removejointjoint)
      * [Joint constructors](#joint-constructors)
      * [getJointsOf](#getjointsofcollider)
      * [newRope](#newropedef)
      * [newChain](#newchaindef)
      * [newBridge](#newbridgedef)
      * [newRagdoll](#newragdolldef)
      * [newPool](#newpoolfactory-reset)
      * [snapshot](#snapshot)
      * [restore](#restoresnapshot)
      * [setExplicitCollisionEvents](#setexplicitcollisioneventsvalue)
      * [setQueryDebugDrawing](#setquerydebugdrawingvalue)
      * [onEnter](#onenterclass_a-class_b-callback)
      * [onExit](#onexitclass_a-class_b-callback)
      * [setColliderFilter](#setcolliderfilterfn)
      * [addEffector](#addeffectordef)
   * [Collider](#collider)
      * [destroy](#destroy-1)
      * [setCollisionClass](#setcollisionclasscollision_class_name)
      * [enter](#enterother_collision_class_name)
      * [getEnterCollisionData](#getentercollisiondataother_collision_class_name)
      * [exit](#exitother_collision_class_name)
      * [getExitCollisionData](#getexitcollisiondataother_collision_class_name)
      * [getEnters](#getentersother_collision_class_name)
      * [getExits](#getexitsother_collision_class_name)
      * [onEnter](#onenterother_collision_class_name-callback)
      * [onExit](#onexitother_collision_class_name-callback)
      * [stay](#stayother_collision_class_name)
      * [getStayCollisionData](#getstaycollisiondataother_collision_class_name)
      * [setSensor](#setsensorsensor)
      * [isSensor](#issensor)
      * [isPooled](#ispooled)
      * [getGround](#getgroundmax_slope)
      * [moveKinematic](#movekinematicx-y-angle-dt)
      * [driveTo](#drivetox-y-angle-strength)
      * [setInterpolated](#setinterpolatedinterpolated)
      * [isInterpolated](#isinterpolated)
      * [getRenderPosition](#getrenderposition)
      * [getRenderAngle](#getrenderangle)
      * [setDrawOrder](#setdraworderorder)
      * [getDrawOrder](#getdraworder)
      * [draw hook](#draw-hook)
      * [setPreSolve](#setpresolvecallback)
      * [setPostSolve](#setpostsolvecallback)
      * [addShape](#addshapeshape_name-shape_type-)
      * [removeShape](#removeshapeshape_name)
      * [setObject](#setobjectobject)
      * [getObject](#getobject)
      
<br>

# Quick Start

Windfield targets LÖVE 11.5. The source is also compatible with Lua 5.1 to 5.5.

Place the `windfield` folder inside your project and require it:

```lua
wf = require 'windfield'
```

<br>

## Create a world

A physics world can be created just like in box2d. The world returned by `wf.newWorld` contains all the functions of a [LÖVE physics World](https://love2d.org/wiki/World) as well as additional ones defined by this library.

```lua
function love.load()
    world = wf.newWorld(0, 0, true)
    world:setGravity(0, 512)
end

function love.update(dt)
    world:update(dt)
end
```

<br>

## Create colliders

A collider is a composition of a single body, fixture and shape. For most use cases whenever box2d is needed a body will only have one fixture/shape attached to it, so it makes sense to work primarily on that level of abstraction. Colliders contain all the functions of a LÖVE physics [Body](https://love2d.org/wiki/Body), [Fixture](https://love2d.org/wiki/Fixture) and [Shape](https://love2d.org/wiki/Shape) as well as additional ones defined by this library:

```lua
function love.load()
    ...

    box = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box:setRestitution(0.8)
    box:applyAngularImpulse(5000)

    ground = world:newRectangleCollider(0, 550, 800, 50)
    wall_left = world:newRectangleCollider(0, 0, 50, 600)
    wall_right = world:newRectangleCollider(750, 0, 50, 600)
    ground:setType('static') -- Types can be 'static', 'dynamic' or 'kinematic'. Defaults to 'dynamic'
    wall_left:setType('static')
    wall_right:setType('static')
end

...

function love.draw()
    world:draw() -- The world can be drawn for debugging purposes
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/ytfhmjc.gif"/>
</p>

<br>

## Create joints

Joints are mostly unchanged from how they work normally in box2d:

```lua
function love.load()
    ...

    box_1 = world:newRectangleCollider(400 - 50/2, 0, 50, 50)
    box_1:setRestitution(0.8)
    box_2 = world:newRectangleCollider(400 - 50/2, 50, 50, 50)
    box_2:setRestitution(0.8)
    box_2:applyAngularImpulse(5000)
    joint = world:addJoint('RevoluteJoint', box_1, box_2, 400, 50, true)

    ...
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/tSqkxJR.gif"/>
</p>

<br>

## Create collision classes

Collision classes are used to make colliders ignore other colliders of certain classes and to capture collision events between colliders. The same concept goes by the name of 'collision layer' or 'collision tag' in other engines. In the example below we add a Solid and Ghost collision class. The Ghost collision class is set to ignore the Solid collision class.

```lua
function love.load()
    ...

    world:addCollisionClass('Solid')
    world:addCollisionClass('Ghost', {ignores = {'Solid'}})

    box_1 = world:newRectangleCollider(400 - 100, 0, 50, 50)
    box_1:setRestitution(0.8)
    box_2 = world:newRectangleCollider(400 + 50, 0, 50, 50)
    box_2:setCollisionClass('Ghost')

    ground = world:newRectangleCollider(0, 550, 800, 50)
    ground:setType('static')
    ground:setCollisionClass('Solid')

    ...
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/j7IhVSe.gif"/>
</p>

The box that was set be of the Ghost collision class ignored the ground and went right through it, since the ground is set to be of the Solid collision class.

<br>

## Capture collision events

Collision events can be captured inside the update function by calling the `enter`, `exit` or `stay` functions of a collider. In the example below, whenever the box collider enters contact with another collider of the Solid collision class it will get pushed to the right:

```lua
function love.update(dt)
    ...
    if box:enter('Solid') then
        box:applyLinearImpulse(1000, 0)
        box:applyAngularImpulse(5000)
    end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/uF1bqKM.gif"/>
</p>

<br>

## Query the world

The world can be queried with a few area functions and then all colliders inside that area will be returned. In the example below, the world is queried at position 400, 300 with a circle of radius 100, and then all colliders in that area are pushed to the right and down.

```lua
function love.load()
    world = wf.newWorld(0, 0, true)
    world:setQueryDebugDrawing(true) -- Draws the area of a query for 10 frames

    colliders = {}
    for i = 1, 200 do
        table.insert(colliders, world:newRectangleCollider(love.math.random(0, 800), love.math.random(0, 600), 25, 25))
    end
end

function love.update(dt)
    world:update(dt)
end

function love.draw()
    world:draw()
end

function love.keypressed(key)
    if key == 'p' then
        local colliders = world:queryCircleArea(400, 300, 100)
        for _, collider in ipairs(colliders) do
            collider:applyLinearImpulse(1000, 1000)
        end
    end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/YVxAiuu.gif"/>
</p>

<br>

# Examples & Tips

## Checking collisions between game objects

The most common use case for a physics engine is doing things when things collide. For instance, when the Player collides with an enemy you might want to deal damage to the player. Here's the way to achieve that with this library:


```lua
-- in Player.lua
function Player:new()
  self.collider = world:newRectangleCollider(...)
  self.collider:setCollisionClass('Player')
  self.collider:setObject(self)
end

-- in Enemy.lua
function Enemy:new()
  self.collider = world:newRectangleCollider(...)
  self.collider:setCollisionClass('Enemy')
  self.collider:setObject(self)
end
```

First we define in the constructor of both classes the collider that should be attached to them. We set their collision classes (Player and Enemy) and then link the object to the colliders with `setObject`. With this, we can capture collision events between both and then do whatever we wish when a collision happens:

```lua
-- in Player.lua
function Player:update(dt)
  if self.collider:enter('Enemy') then
    local collision_data = self.collider:getEnterCollisionData('Enemy')
    local enemy = collision_data.collider:getObject()
    -- Kills the enemy on hit but also take damage
    enemy:die()
    self:takeDamage(10)
  end
end
```

<br>

## One-way Platforms

A common problem people have with using 2D physics engines seems to be getting one-way platforms to work. The `one_way` option of `addCollisionClass` does it for you: `world:addCollisionClass('Platform', {one_way = {0, -1}})`. This is how to do it by hand with a `preSolve` callback, which is also a good example of what `setPreSolve` can do:

```lua
function love.load()
  world = wf.newWorld(0, 512, true)
  world:addCollisionClass('Platform')
  world:addCollisionClass('Player')
  
  ground = world:newRectangleCollider(100, 500, 600, 50)
  ground:setType('static')
  platform = world:newRectangleCollider(350, 400, 100, 20)
  platform:setType('static')
  platform:setCollisionClass('Platform')
  player = world:newRectangleCollider(390, 450, 20, 40)
  player:setCollisionClass('Player')
  
  player:setPreSolve(function(collider_1, collider_2, contact)        
    if collider_1.collision_class == 'Player' and collider_2.collision_class == 'Platform' then
      local px, py = collider_1:getPosition()            
      local pw, ph = 20, 40            
      local tx, ty = collider_2:getPosition() 
      local tw, th = 100, 20
      if py + ph/2 > ty - th/2 then contact:setEnabled(false) end
    end   
  end)
end

function love.keypressed(key)
  if key == 'space' then
    player:applyLinearImpulse(0, -1000)
  end
end
```

And that looks like this:

<p align="center">
  <img src="http://i.imgur.com/ouwxVRH.gif"/>
</p>

The way this works is that by disabling the contact before collision response is applied (so in the preSolve callback) we can make a collider ignore another. And then all we do is check to see if the player is below platform, and if he is then we disable the contact.

<br>

# Editor support

The `types/windfield.lua` file in this repository holds [LuaLS](https://luals.github.io/) type definitions for the whole API: autocomplete, argument checks and hover documentation for `World`, `Collider`, `settings` tables and collision data. A collider also gets the LÖVE `Body`, `Fixture` and `Shape` methods it forwards.

Copy the `types` folder next to your `windfield` folder and add it, together with the LÖVE definitions, to your `.luarc.json`:

```json
{
    "runtime.version": "Lua 5.5",
    "workspace.library": ["${3rd}/love2d/library", "types"],
    "diagnostics.globals": ["love"]
}
```

<br>

# Documentation

## World

On top of containing all functions exposed in this documentation it also contains all functions of a [box2d World](https://love2d.org/wiki/World).

---

#### `.newWorld(xg, yg, sleep, options)`

Creates a new World.

```lua
world = wf.newWorld(0, 0, true)
```

Arguments:

* `xg` `(number)` - The world's x gravity component
* `yg` `(number)` - The world's y gravity component
* `sleep=true` `(boolean)` - If the world's bodies are allowed to sleep or not
* `options` `(table)` - Optional. `options.meter` `(number)` sets the LÖVE physics meter (pixels per meter, default `32`). The meter is global to LÖVE: the first world sets it to `32` when no option is given, and later worlds leave it alone, so a game that calls `love.physics.setMeter` after the first world keeps its value

Returns:

* `World` `(table)` - the World object, containing all attributes and methods defined below as well as all of a [box2d World](https://love2d.org/wiki/World)


---

#### `.newTimer(duration)`

Creates a countdown timer for the small grace periods of character controls: coyote time (still allowed to jump a moment after leaving a ledge) and jump buffering (a jump pressed just before landing still counts).

```lua
coyote = wf.newTimer(0.1)
jump_buffer = wf.newTimer(0.12)

function love.update(dt)
    coyote:update(dt)
    jump_buffer:update(dt)
    if player:getGround().grounded then coyote:start() end
    if jump_pressed then jump_buffer:start() end
    if coyote:isActive() and jump_buffer:consume() then
        coyote:consume()
        player:applyLinearImpulse(0, -400)
    end
    world:update(dt)
end
```

Arguments:

* `duration` `(number)` - How long the timer stays active after `start`, in seconds, greater than zero

Returns:

* `timer` `(table)` - With these methods: `start([duration])` (restart the countdown, optionally with another duration), `update(dt)`, `isActive()` and `consume()` (returns `true` and stops the timer when it was active)

---

#### `:update(dt)`

Updates the world.

```lua
world:update(dt)
```

Arguments:

* `dt` `(number)` - The time step delta

---

#### `:step(dt)`

Updates the world with a fixed time step. The time `dt` is added to an accumulator and `update` runs with the fixed step as many times as fit, at most `max_steps` times. Time beyond that limit is dropped, so a long frame cannot make the next frame even longer. `update(dt)` keeps working as before and the two should not be mixed on the same world.

```lua
function love.update(dt)
    local steps = world:step(dt)
end
```

Arguments:

* `dt` `(number)` - The frame time to add

Returns:

* `steps` `(number)` - How many fixed updates ran

---

#### `:setFixedStep(dt, max_steps)`

Sets the fixed step used by `step`.

```lua
world:setFixedStep(1/120, 8)
```

Arguments:

* `dt=1/60` `(number)` - The fixed time step, greater than zero
* `max_steps=5` `(number)` - The most updates `step` runs in one call, at least 1

---

#### `:getAlpha()`

Returns how far the accumulator is into the next fixed step, from 0 up to but not including 1. Use it to draw between the last two physics states.

```lua
local alpha = world:getAlpha()
```

Returns:

* `alpha` `(number)` - The leftover fraction of a fixed step

---

#### `:draw(alpha_or_options)`

Draws the world, drawing all colliders, joints and world queries (for debugging purposes). The line width is set to 1 while drawing, so the width you use for your own graphics does not leak into the debug drawing, and your previous line width and color are restored afterwards.

```lua
world:draw() -- default drawing
world:draw(128) -- semi transparent drawing
world:draw({alpha = 128, line_width = 2, class_colors = {Enemy = {1, 0.3, 0.3}}, contacts = true})
```

Arguments:

* `alpha_or_options=255` `(number or table)` - A number is the alpha value, from 0 to 255. A table can have:
  * `[alpha=255]` `(number)` - The alpha value, from 0 to 255
  * `[line_width=1]` `(number)` - The line width used for every shape
  * `[class_colors]` `(table)` - Colors by collision class name, each `{r, g, b}` with components from 0 to 1. Classes that are not listed keep the default color
  * `[contacts=false]` `(boolean)` - Draws a circle on every contact point of touching colliders and a line along the contact normal
  * `[aabb=false]` `(boolean)` - Draws the bounding box of every shape
  * `[velocities=false]` `(boolean)` - Draws a line from each moving body to where it would be a quarter of a second later
  * `[sleeping=false]` `(boolean)` - Draws the bodies that are asleep with 40 percent of the alpha

An unknown key in the table raises an error. Each collider is drawn once; the solid and sensor fixtures of a collider share the same shape.

---

#### `:destroy()`

Destroys the world and removes all bodies, fixtures, shapes and joints from it. This must be called whenever the World is to discarded otherwise it will result in it not getting collected (and so memory will leak).

```lua
world:destroy()
```

---

#### `:addCollisionClass(collision_class_name, collision_class)`

Adds a new collision class to the World. Collision classes are attached to Colliders and defined their behaviors in terms of which ones will physically ignore each other and which ones will generate collision events between each other. Classes can be added at any time; colliders that already exist are updated. If `world:setExplicitCollisionEvents` is set to false (the default setting) then `enter`, `exit`, `pre` and `post` settings don't need to be specified, otherwise they do.
```lua
world:addCollisionClass('Player', {ignores = {'NPC', 'Enemy'}})
```

Arguments:

* `collision_class_name` `(string)` - The unique name of the collision class
* `collision_class` `(table)` - The collision class. This table can contain:

Settings:

* `[sensor]` `(boolean)` - Makes colliders of this class sensors: they physically ignore every collision class and still generate enter, stay and exit events. Same as `ignores = {'All'}`, and it cannot be combined with `ignores`. See `Collider:setSensor` for the static body limitation
* `[one_way]` `({nx, ny})` - Makes colliders of this class one-way platforms: they are solid only for colliders on the side the vector points to, like `{0, -1}` for the top of a platform (y grows downwards). Colliders coming from the other side, or moving away through the platform, pass through. The vector does not have to be unit length. The `enter` and `exit` events still happen while the colliders overlap. A `pre` handler runs after the check and can call `contact:setEnabled(true)` to override it
* `[conveyor]` `(number)` - Makes colliders of this class conveyor belts. Whatever rests on them is carried at this speed in pixels per second, in the direction of the belt's surface seen from the carried collider: with the belt below, positive values move to the right. Friction on both colliders (the default is 0.2) sets how fast the carried collider reaches that speed
* `[ignores]` `(table[string])` - The collision classes that will be physically ignored
* `[enter]` `(table[string])` - The collision classes that will generate collision events with the collider of this collision class when they enter contact with each other
* `[exit]` `(table[string])` - The collision classes that will generate collision events with the collider of this collision class when they exit contact with each other
* `[pre]` `(table[string])` - The collision classes that will generate collision events with the collider of this collision class right before collision response is applied
* `[post]` `(table[string])` - The collision classes that will generate collision events with the collider of this collision class right after collision response is applied

---

#### Collider settings

Every collider constructor (`newCircleCollider`, `newRectangleCollider`, `newBSGRectangleCollider`, `newPolygonCollider`, `newLineCollider`, `newChainCollider`) takes an optional `settings` table as its last argument:

```lua
box = world:newRectangleCollider(100, 100, 50, 50, {collision_class = 'Player', body_type = 'dynamic', fixed_rotation = true, friction = 0.2})
```

* `collision_class='Default'` `(string)` - The name of the collision class
* `body_type='dynamic'` `(string)` - `'dynamic'`, `'static'` or `'kinematic'`
* `bullet` `(boolean)` - Continuous collision detection against other moving bodies (`setBullet`)
* `fixed_rotation` `(boolean)` - Prevents the body from rotating (`setFixedRotation`)
* `gravity_scale` `(number)` - Multiplier applied to the world's gravity (`setGravityScale`)
* `linear_damping` `(number)` - `setLinearDamping`
* `angular_damping` `(number)` - `setAngularDamping`
* `sleeping_allowed` `(boolean)` - `setSleepingAllowed`
* `active` `(boolean)` - `setActive`
* `angle` `(number)` - The initial angle in radians (`setAngle`)
* `restitution` `(number)` - `setRestitution` on the solid fixture
* `friction` `(number)` - `setFriction` on the solid fixture
* `density` `(number)` - `setDensity` on the solid fixture; the body mass is recomputed
* `object` `(any)` - Stored on the collider, same as `setObject`
* `sensor` `(boolean)` - Starts the collider as a sensor, same as `setSensor(true)`

Keys that are not listed raise an error, so a typo such as `restitutoin` is caught when the collider is created.

---

#### `:newCircleCollider(x, y, r)`

Creates a new CircleCollider.

```lua
circle = world:newCircleCollider(100, 100, 30)
```

Arguments:

* `x` `(number)` - The x position of the circle's center
* `y` `(number)` - The y position of the circle's center
* `r` `(number)` - The radius of the circle

Returns:

* `Collider` `(table)` - The newly created CircleCollider

---

#### `:newRectangleCollider(x, y, w, h)`

Creates a new RectangleCollider.

```lua
rectangle = world:newRectangleCollider(100, 100, 50, 50)
```

Arguments:

* `x` `(number)` - The x position of the rectangle's top-left corner
* `y` `(number)` - The y position of the rectangle's top-left corner
* `w` `(number)` - The width of the rectangle
* `h` `(number)` - The height of the rectangle

Returns:

* `Collider` `(table)` - The newly created RectangleCollider

---

#### `:newBSGRectangleCollider(x, y, w, h, corner_cut_size)`

Creates a new BSGRectangleCollider, which is a rectangle with its corners cut (an octagon).

```lua
bsg_rectangle = world:newBSGRectangleCollider(100, 100, 50, 50, 5)
```

Arguments:

* `x` `(number)` - The x position of the rectangle's top-left corner
* `y` `(number)` - The y position of the rectangle's top-left corner
* `w` `(number)` - The width of the rectangle
* `h` `(number)` - The height of the rectangle
* `corner_cut_size` `(number)` - The corner cut size

Returns:

* `Collider` `(table)` - The newly created BSGRectangleCollider

---

#### `:newPolygonCollider(vertices)`

Creates a new PolygonCollider.

```lua
polygon = world:newPolygonCollider({10, 10, 10, 20, 20, 20, 20, 10})
```

Arguments:

* `vertices` `(table[number])` - The polygon vertices as a table of numbers

Returns:

* `Collider` `(table)` - The newly created PolygonCollider

---

#### `:newConcavePolygonCollider(vertices, settings)`

Creates a collider from a polygon that does not have to be convex. Box2D only accepts convex polygons with at most 8 vertices, so the polygon is cut into convex pieces: it is triangulated and neighbouring triangles are merged again while the result stays convex and has at most 8 vertices (the Hertel-Mehlhorn method). The first piece is the `'main'` shape of the collider and the others are added as shapes named `'part2'`, `'part3'` and so on, so they follow the collider's collision class, queries and `destroy`. This also lets you create convex polygons with more than 8 vertices.

```lua
local ground = world:newConcavePolygonCollider({0, 0, 200, 0, 200, 100, 100, 100, 100, 200, 0, 200}, {body_type = 'static'})
```

Arguments:

* `vertices` `(table[number])` - The polygon vertices as a flat table of numbers, in either winding order. The polygon must be simple: an error is raised when its edges cross or touch each other or when it has no area. A repeated closing vertex is ignored
* `[settings]` `(table)` - The same settings as the other collider constructors

Returns:

* `Collider` `(table)` - The newly created collider, of type `'Polygon'`

The pieces are separate fixtures, so a collider that touches two pieces at once generates one `enter` event per piece, and `getEnters` returns one entry for each. Use `newPolygonCollider` for polygons that are already convex and have 8 vertices or fewer: it creates one shape and is cheaper.

---

#### `:newLineCollider(x1, y1, x2, y2)`

Creates a new LineCollider.

```lua
line = world:newLineCollider(100, 100, 200, 200)
```

Arguments:

* `x1` `(number)` - The x position of the first point of the line
* `y1` `(number)` - The y position of the first point of the line
* `x2` `(number)` - The x position of the second point of the line
* `y2` `(number)` - The y position of the second point of the line

Returns:

* `Collider` `(table)` - The newly created LineCollider

---

#### `:newChainCollider(vertices, loop)`

Creates a new ChainCollider.

```lua
chain = world:newChainCollider({10, 10, 10, 20, 20, 20}, true)
```

Arguments:

* `vertices` `(table[number])` - The chain vertices as a table of numbers
* `loop` `(boolean)` - If the chain should loop back from the last to the first point

Returns:

* `Collider` `(table)` - The newly created ChainCollider

---

#### `:queryCircleArea(x, y, r, collision_class_names)`

Queries a circular area around a point for colliders.

All the area queries (`queryCircleArea`, `queryRectangleArea`, `queryPolygonArea`) follow the same rules. A collider is returned when its shape overlaps the area, with one exception: if the whole area lies inside a polygon, rectangle or other polygon based collider, that collider is not returned. Circle colliders are returned for any overlap, including an area completely inside the circle. Sensors are never returned. `queryLine` returns every collider the line crosses.

```lua
colliders_1 = world:queryCircleArea(100, 100, 50, {'Enemy', 'NPC'})
colliders_2 = world:queryCircleArea(100, 100, 50, {'All', except = {'Player'}})
```

Arguments:

* `x` `(number)` - The x position of the circle's center
* `y` `(number)` - The y position of the circle's center
* `r` `(number)` - The radius of the circle
* `[collision_class_names='All']` `(table[string])` - A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.

Returns:

* `table[Collider]` - The table of colliders with the specified collision classes inside the area

---

#### `:queryRectangleArea(x, y, w, h, collision_class_names)`

Queries a rectangular area for colliders.

```lua
colliders_1 = world:queryRectangleArea(100, 100, 50, 50, {'Enemy', 'NPC'})
colliders_2 = world:queryRectangleArea(100, 100, 50, 50, {'All', except = {'Player'}})
```

Arguments:

* `x` `(number)` - The x position of the rectangle's top-left corner
* `y` `(number)` - The y position of the rectangle's top-left corner
* `w` `(number)` - The width of the rectangle
* `h` `(number)` - The height of the rectangle
* `[collision_class_names='All']` `(table[string])` - A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.

Returns:

* `table[Collider]` - The table of colliders with the specified collision classes inside the area

---

#### `:queryPolygonArea(vertices, collision_class_names)`

Queries a polygon area for colliders.

```lua
colliders_1 = world:queryPolygonArea({10, 10, 20, 10, 20, 20, 10, 20}, {'Enemy'})
colliders_2 = world:queryPolygonArea({10, 10, 20, 10, 20, 20, 10, 20}, {'All', except = {'Player'}})
```

Arguments:

* `vertices` `(table[number])` - The polygon vertices as a table of numbers
* `[collision_class_names='All']` `(table[string])` - A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.

Returns:

* `table[Collider]` - The table of colliders with the specified collision classes inside the area

---

#### `:queryLine(x1, y1, x2, y2, collision_class_names)`

Queries for colliders that intersect with a line.

```lua
colliders_1 = world:queryLine(100, 100, 200, 200, {'Enemy', 'NPC', 'Projectile'})
colliders_2 = world:queryLine(100, 100, 200, 200, {'All', except = {'Player'}})
```

Arguments:

* `x1` `(number)` - The x position of the first point of the line
* `y1` `(number)` - The y position of the first point of the line
* `x2` `(number)` - The x position of the second point of the line
* `y2` `(number)` - The y position of the second point of the line
* `[collision_class_names='All']` `(table[string])` - A table of strings with collision class names to be queried. The special value `'All'` (default) can be used to query for all existing collision classes. Another special value `except` can be used to exclude some collision classes when `'All'` is used.

Returns:

* `table[Collider]` - The table of colliders with the specified collision classes inside the area

---

#### `:raycast(x1, y1, x2, y2, collision_class_names, mode)`

Casts a ray from the first point to the second one and returns where it hits colliders, with the hit point and surface normal. `queryLine` only tells which colliders the line touches, in no particular order.

```lua
local hits = world:raycast(100, 100, 400, 100)
for _, hit in ipairs(hits) do
    print(hit.collider.collision_class, hit.x, hit.y, hit.nx, hit.ny, hit.fraction)
end

local wall = world:raycast(player_x, player_y, enemy_x, enemy_y, {'All', except = {'Zone'}}, 'closest')
if wall then print('line of sight blocked by', wall.collider) end
```

Arguments:

* `x1` `(number)` - The x position of the start of the ray
* `y1` `(number)` - The y position of the start of the ray
* `x2` `(number)` - The x position of the end of the ray
* `y2` `(number)` - The y position of the end of the ray
* `[collision_class_names='All']` `(table[string])` - Same format as in `queryLine`. Sensor colliders (`setSensor` or a `sensor` collision class) are hit like any other collider, so leave their classes out to let the ray pass through them
* `[mode='all']` `(string)` - `'all'` returns every hit sorted from the nearest to the farthest, `'closest'` returns only the nearest one

Returns:

* `all` mode: `table[table]` - The hits, each with `collider`, `x`, `y` (hit point), `nx`, `ny` (surface normal at the hit point) and `fraction` (0 at the start of the ray, 1 at its end). Empty when nothing is hit
* `closest` mode: `table` - The nearest hit, with the same fields, or `nil` when nothing is hit

---

#### `:queryShape(shape_def, x, y, collision_class_names)`

Returns the colliders that overlap a shape. Unlike the area queries this test is exact for every combination of shapes: it uses the distance between the query shape and each candidate (`love.physics.getDistance`), so a shape that is entirely inside a collider, a collider entirely inside the shape, circle colliders, edges and every segment of a chain are all handled the same way. The `query*Area` functions keep their own rules.

```lua
local hits = world:queryShape({type = 'circle', radius = 40}, player_x, player_y, {'Enemy'})
local door = world:queryShape({type = 'rectangle', w = 30, h = 8, angle = math.pi / 4}, x, y)
```

Arguments:

* `shape_def` `(table)` - The shape, with its position relative to `x`, `y`. `type` is one of:
  * `'circle'` with `radius`
  * `'rectangle'` with `w` and `h`, centered on `x`, `y`
  * `'polygon'` with `vertices` (a flat list, convex, at most 8 points)
  * `'edge'` with `x1`, `y1`, `x2`, `y2`

  Any shape can also have an `angle` in radians, applied around `x`, `y`
* `x` `(number)` - The x position the shape is placed at
* `y` `(number)` - The y position the shape is placed at
* `[collision_class_names='All']` `(table[string])` - Same format as in `queryLine`

Returns:

* `table[Collider]` - The colliders that overlap or touch the shape, each once, in no particular order

Shapes closer than about 0.3 pixels (0.6 between two polygons) count as touching, because LÖVE keeps a small skin around polygons. Sensor colliders are included like in the other queries. Colliders with several shapes are returned once.

---

#### `:shapeCast(shape_def, x, y, dx, dy, collision_class_names)`

Moves a shape from `x, y` by `dx, dy` and returns the first collider it hits, like a ray with thickness. Use it for projectiles with a size, ground checks under a character, or to find out how far something can move before it stops.

```lua
local hit = world:shapeCast({type = 'circle', radius = 8}, player_x, player_y, 0, 40, {'Ground'})
if hit then
    local fall_distance = hit.fraction * 40
end
```

Arguments:

* `shape_def` `(table)` - The shape, same format as in `queryShape` (`angle` is supported and stays fixed while moving)
* `x` `(number)` - The x position where the shape starts
* `y` `(number)` - The y position where the shape starts
* `dx` `(number)` - The x movement
* `dy` `(number)` - The y movement
* `[collision_class_names='All']` `(table[string])` - Same format as in `queryLine`

Returns:

* `table` - The nearest hit, or `nil` when the shape can make the whole movement:
  * `collider` `(Collider)` - The collider that was hit
  * `fraction` `(number)` - How much of the movement is possible before the contact: 0 means no movement, 1 the whole movement
  * `x`, `y` `(number)` - The contact point on the collider
  * `nx`, `ny` `(number)` - The unit normal at the contact, pointing from the collider towards the shape
  * `overlap` `(boolean)` - Only present, and `true`, when the shape already overlapped the collider at the start (`fraction` is 0 and the normal is the opposite of the movement). With `dx, dy` equal to 0 the call is an overlap test

The fraction is found by advancing the shape in steps limited by its distance to the collider (at most 32 steps), so it stops at the contact within LÖVE's polygon skin of about 0.3 pixels, a little before the exact touching position. Shapes that only graze a collider while moving parallel to it do not count as hits. The shape only moves, it does not rotate.

---

#### `:queryPoint(x, y, collision_class_names)`

Returns the colliders that contain a point. The test is exact (LÖVE `Fixture:testPoint`), so a point on the edge of a shape counts as inside, and it works for every collider type including circles. Unlike the area queries it has no special rule for areas fully inside a polygon: the point has no size.

```lua
local colliders = world:queryPoint(love.mouse.getPosition())
local pickable = world:queryPoint(mx, my, {'All', except = {'Wall'}})
```

Arguments:

* `x` `(number)` - The x position of the point
* `y` `(number)` - The y position of the point
* `[collision_class_names='All']` `(table[string])` - Same format as in `queryLine`

Returns:

* `table[Collider]` - The colliders containing the point, in no particular order. Sensor colliders are included like in the other queries

---

#### `:getColliderAt(x, y, collision_class_names)`

Returns one collider that contains a point, or `nil`. When several colliders overlap at the point, which one is returned is unspecified; use `queryPoint` to get all of them.

```lua
local collider = world:getColliderAt(mouse_x, mouse_y)
```

Arguments:

* `x` `(number)` - The x position of the point
* `y` `(number)` - The y position of the point
* `[collision_class_names='All']` `(table[string])` - Same format as in `queryLine`

Returns:

* `Collider` `(table)` - A collider containing the point, or `nil`

---

#### `:addJoint(joint_type, ...)`

Adds a joint to the world.

```lua
joint = world:addJoint('RevoluteJoint', collider_1, collider_2, 50, 50, true)
```

Arguments:

* `joint_type` `(string)` - The joint type, it can be `'DistanceJoint'`, `'FrictionJoint'`, `'GearJoint'`, `'MotorJoint'`, `'MouseJoint'`, `'PrismaticJoint'`, `'PulleyJoint'`, `'RevoluteJoint'`, `'RopeJoint'`, `'WeldJoint'` or `'WheelJoint'`
* `...` `(*)` - The joint creation arguments that are different for each joint type, check [here](https://love2d.org/wiki/Joint) for more details. Colliders are replaced by their body. A table as the last argument is read as the joint options described in "Joint constructors"

Returns:

* `joint` `(Joint)` - The newly created Joint

---

#### `:removeJoint(joint)`

Removes a joint from the world.

```lua
joint = world:addJoint('RevoluteJoint', collider_1, collider_2, 50, 50, true)
world:removeJoint(joint)
```

Arguments:

* `joint` `(Joint)` - The joint to be removed

---

#### Joint constructors

One constructor for every LÖVE joint type, so a joint reads like the other `world:new...` calls. Each one takes the same arguments as the LÖVE function `love.physics.new<Type>`, with colliders where LÖVE wants bodies, and it is the same as calling `addJoint` with the joint type name.

```lua
local hinge = world:newRevoluteJoint(door, frame, 100, 200, false, {limits = {-1.5, 0}, motor = {speed = 2, torque = 500}})
local spring = world:newDistanceJoint(ball, ceiling, bx, by, cx, cy, false, {frequency = 3, damping_ratio = 0.4})
local piston = world:newPrismaticJoint(piston, base, x, y, 0, -1, false, {limits = {0, 80}, motor = {speed = 40, force = 2000}})
```

The constructors are `newDistanceJoint`, `newRevoluteJoint`, `newPrismaticJoint`, `newWeldJoint`, `newRopeJoint`, `newWheelJoint`, `newFrictionJoint`, `newMotorJoint`, `newMouseJoint`, `newPulleyJoint` and `newGearJoint`.

The last argument can be a table of options, applied to the new joint:

* `limits` `({lower, upper})` - Angle limits in radians (revolute) or translation limits in pixels (prismatic, wheel)
* `motor` `({speed, torque, force})` - Turns the motor on with this speed. `torque` is the maximum motor torque (revolute, wheel) and `force` the maximum motor force (prismatic)
* `frequency` `(number)` and `damping_ratio` `(number)` - The spring of distance, weld and wheel joints
* An unknown key raises an error before the joint is created

---

#### `:getJointsOf(collider)`

Returns the joints attached to a collider.

```lua
for _, joint in ipairs(world:getJointsOf(collider)) do world:removeJoint(joint) end
```

Arguments:

* `collider` `(Collider)` - The collider

Returns:

* `table[Joint]` - The joints

---

#### `:newRope(def)`

Builds a rope: a row of thin rectangles from one point to another, each pair joined by a revolute joint. All the pieces are normal colliders with the collision class and settings you give.

```lua
local rope = world:newRope({x1 = 400, y1 = 50, x2 = 400, y2 = 300, segments = 12, thickness = 4, pin_a = true,
                            settings = {collision_class = 'Rope'}})
rope.parts[12]:applyLinearImpulse(200, 0)
rope:destroy()
```

Arguments:

* `def` `(table)`:
  * `x1`, `y1`, `x2`, `y2` `(number)` - The two end points
  * `[segments=10]` `(number)` - How many pieces, a whole number of at least 1
  * `[thickness=6]` `(number)` - The thickness of every piece
  * `[settings]` `(table)` - Collider settings given to every piece
  * `[pin_a]`, `[pin_b]` `(boolean)` - Create a small static collider at the first or last end point and join the rope to it
  * `[anchor_a]`, `[anchor_b]` `(Collider)` - Join the first or last end point to a collider you already have

Returns:

* `assembly` `(table)` - `parts` (the colliders in order, plus `pin_a` and `pin_b` when they were created), `joints` (a rope of N segments has N-1 joints between pieces, plus one for each pin or anchor) and `destroy()`, which removes every joint and collider of the rope

An unknown key, equal end points or a failing piece raise an error and leave nothing behind.

---

#### `:newChain(def)`

Same as `newRope`, but the pieces are circles placed along the line, from the first end point to the last one. Use `radius` (default 4) instead of `thickness`.

```lua
local chain = world:newChain({x1 = 100, y1 = 100, x2 = 300, y2 = 100, segments = 8, radius = 6, pin_a = true})
```

Arguments:

* `def` `(table)` - As in `newRope`, with `radius` in place of `thickness`

Returns:

* `assembly` `(table)` - As in `newRope`, with N links and N-1 joints between them

---

#### `:newBridge(def)`

Same as `newRope`, but both ends are pinned by default (`pin_a` and `pin_b` are `true`), so the planks hang between two fixed points and sag under load.

```lua
local bridge = world:newBridge({x1 = 300, y1 = 300, x2 = 700, y2 = 300, segments = 10, thickness = 8})
```

Arguments:

* `def` `(table)` - As in `newRope`. Pass `pin_a = false` or `pin_b = false` to leave an end free

Returns:

* `assembly` `(table)` - As in `newRope`

---

#### `:newRagdoll(def)`

Builds a set of named parts held together by joints, for characters and other jointed objects. The parts are colliders, the joints are created through `addJoint`, so every joint type and option is available.

```lua
local doll = world:newRagdoll({
    parts = {
        torso = {shape = 'rectangle', x = 400, y = 100, w = 20, h = 40},
        head = {shape = 'circle', x = 410, y = 86, r = 8, settings = {collision_class = 'Ragdoll'}},
    },
    joints = {
        {type = 'RevoluteJoint', a = 'torso', b = 'head', args = {410, 94}, options = {limits = {-0.6, 0.6}}},
    },
})
doll.parts.head:applyLinearImpulse(0, -50)
doll:destroy()
```

Arguments:

* `def` `(table)`:
  * `parts` `(table)` - Parts by name. A part has a `shape` (`'circle'` with `x`, `y`, `r`, or `'rectangle'` with `x`, `y` (top left), `w`, `h`), an optional `angle` and optional `settings` for the collider
  * `joints` `(table)` - A list of joints. Each has `type` (a joint type name as in `addJoint`), `a` and `b` (part names), `args` (the arguments after the two bodies, for example the anchor), optionally `collide` (the `collideConnected` flag) and `options` (as in "Joint constructors")

Returns:

* `assembly` `(table)` - `parts` (colliders by name), `joints` (a list) and `destroy()`

Parts that are joined together do not collide with each other unless `collide` is `true`. An unknown part name, shape or key raises an error and leaves nothing behind.

---

#### `:setExplicitCollisionEvents(value)`

Sets collision events to be explicit or not. If explicit, then collision events will only be generated between collision classes when they are specified in `addCollisionClasses`. By default this is set to false, meaning that collision events are generated between all collision classes. The main reason why you might want to set this to true is for performance, since not generating collision events between every collision class will require less computation. This function must be called before any collision class is added to the world.

```lua
world:setExplicitCollisionEvents(true)
```

Arguments:

* `value` `(boolean)` - If collision events are explicit or not

---

#### `:setQueryDebugDrawing(value)`

Sets query debug drawing to be active or not. If active, then collider queries will be drawn to the screen for 10 frames. This is used for debugging purposes and incurs a performance penalty. Don't forget to turn it off!

```lua
world:setQueryDebugDrawing(true)
```

Arguments:

* `value` `(boolean)` - If query debug drawing is active or not

---

#### `:onEnter(class_a, class_b, callback)`

Registers a function that is called when a collider of `class_a` starts touching a collider of `class_b`. Callbacks run after the physics step finished, in the order the contacts were reported, so it is safe to create or destroy colliders inside them. A pair of colliders of the same class is reported once.

```lua
local handle = world:onEnter('Player', 'Coin', function(player, coin, data)
    coin:destroy()
end)
handle:remove()
```

Arguments:

* `class_a` `(string)` - The collision class of the first collider
* `class_b` `(string)` - The collision class of the second collider
* `callback` `(function)` - Called as `callback(collider_a, collider_b, data)`. `data` has the same fields as the collision data returned by `collider:getEnterCollisionData`, where `collider` is `collider_b`

Returns:

* `handle` `(table)` - A table with a `remove()` function that unregisters the callback

---

#### `:onExit(class_a, class_b, callback)`

Same as `onEnter`, but called when the colliders stop touching.

```lua
world:onExit('Player', 'Platform', function(player, platform, data)
    print('left the platform')
end)
```

Arguments:

* `class_a` `(string)` - The collision class of the first collider
* `class_b` `(string)` - The collision class of the second collider
* `callback` `(function)` - Called as `callback(collider_a, collider_b, data)`

Returns:

* `handle` `(table)` - A table with a `remove()` function that unregisters the callback

---

#### `:addEffector(def)`

Adds a region that acts on the colliders inside it every `world:update`: wind, a zone with different gravity, a swamp that slows things down or a pool that makes things float. A collider is inside when the center of its body is inside the region. Only dynamic bodies are affected. All effects of the effector are added together, and the effects of several effectors add up.

```lua
local wind = world:addEffector({shape = 'rectangle', x = 0, y = 200, w = 800, h = 200, force = {400, 0}})
local moon = world:addEffector({shape = 'circle', x = 400, y = 300, r = 150, gravity = {0, -600}, classes = {'Player', 'Crate'}})
local water = world:addEffector({shape = 'rectangle', x = 0, y = 500, w = 800, h = 300, buoyancy = {density = 2, level = 500}, drag = 3})

wind:setEnabled(false)
water:setGeometry({y = 450, h = 350})
moon:destroy()
```

Arguments:

* `def` `(table)` - The effector definition:
  * `shape` `(string)` - The region: `'circle'` with `x`, `y` (center) and `r`, `'rectangle'` with `x`, `y` (top left corner), `w` and `h`, or `'polygon'` with `vertices` (a flat table of numbers, any simple polygon)
  * `[classes={'All'}]` `(table[string])` - The collision classes that are affected, same format as in `queryLine`
  * `[gravity]` `({gx, gy})` - An acceleration in pixels per second squared, added to the world gravity. It does not depend on the mass
  * `[force]` `({fx, fy})` - A constant force on every body, as in `Body:applyForce`. A heavier body accelerates less
  * `[drag]` `(number)` - Slows the body down: it adds the acceleration `-drag * velocity`, so with `drag = 2` the speed falls to about 13 percent in one second
  * `[buoyancy]` `({density, level})` - A fluid with horizontal surface at `y = level` that fills the region below it. A body that is partly under the surface is pushed against the world gravity with the force of its submerged fraction times its weight times `density` divided by the body's own density, so a body half as dense as the fluid floats half submerged. It needs a world gravity different from zero

  At least one of `gravity`, `force`, `drag` and `buoyancy` is required. Unknown keys raise an error

Returns:

* `handle` `(table)` - With these methods:
  * `setEnabled(enabled)` and `isEnabled()` - Pause or resume the effector
  * `setGeometry(geometry)` - Change the region: a table with any of `x`, `y`, `r`, `w`, `h` and `vertices` that replaces those values
  * `destroy()` - Remove the effector. Using the handle afterwards raises an error, except for calling `destroy` again

---

#### `:newPool(factory, reset)`

Creates a pool that reuses colliders, for things that appear and disappear all the time such as bullets, particles with physics or enemies. Creating and destroying a collider is the most expensive thing windfield does; taking one from a pool and putting it back is several times cheaper and produces much less garbage.

```lua
bullets = world:newPool(function(x, y)
    return world:newCircleCollider(x, y, 3, {collision_class = 'Bullet'})
end, function(bullet, x, y)
    bullet:setPosition(x, y)
end)

local bullet = bullets:get(player_x, player_y)
bullet:setLinearVelocity(400, 0)
bullets:release(bullet)
```

Arguments:

* `factory` `(function)` - Called as `factory(...)` with the arguments of `get` when the pool has no released collider; it has to create and return a collider
* `[reset]` `(function)` - Called as `reset(collider, ...)` with the arguments of `get` when a released collider is taken again. It must give the collider the state that `factory` would have given a new one (position, velocity, angle, class, and so on). It is not called for colliders the factory has just created

Returns:

* `pool` `(table)` - With these methods:
  * `get(...)` - Returns a collider: a released one, activated again, or a new one from the factory. Collider handlers registered with `onEnter` and `onExit` stay on the collider, so register them in the factory
  * `release(collider)` - Deactivates the collider (`setActive(false)`), zeroes its velocities, clears its events and stores it. A released collider is not simulated, does not collide, is not returned by queries or raycasts, generates no events and is not drawn by `world:draw`. Releasing a collider twice does nothing. Called while the world is stepping, the release happens after the step
  * `size()` - How many released colliders wait in the pool
  * `clear()` - Destroys the released colliders that are waiting

Colliders that other colliders were touching send them an `exit` event when they are released. As with creating colliders, do not call `get` from the `pre` and `post` callbacks; use `world:onEnter` handlers or code after `update`.

---

#### `:snapshot()`

Records the state of every collider of the world: position, angle, linear and angular velocity, whether the body is awake and active, whether it is parked in a pool and its collision class. Use it for rewinding time, for checkpoints and to undo a move in a puzzle.

```lua
local checkpoint = world:snapshot()
-- ... play for a while ...
local missing = world:restore(checkpoint)
```

Returns:

* `snapshot` `(table)` - A table keyed by collider `id`. Each entry has `x`, `y`, `angle`, `vx`, `vy`, `av`, `awake`, `active`, `pooled` and `collision_class`. It is plain data, so it can be copied or serialized

---

#### `:restore(snapshot)`

Writes a snapshot back into the colliders that still exist: it moves them, sets their velocities, sleep state and collision class, and clears their collision events. It does not create colliders that were destroyed since the snapshot and does not touch colliders that were created after it. Call it outside the physics callbacks.

Arguments:

* `snapshot` `(table)` - A table returned by `world:snapshot`

Returns:

* `missing` `(table[string])` - The sorted ids of the snapshot entries whose collider no longer exists

Box2D keeps the impulses of resting contacts from one step to the next (warm starting) and LÖVE does not let you read or write them, so a restored world is not bit-identical to the original run. The restored state itself is exact. Free flying bodies and simple scenes continue exactly as before: in the tests, a few boxes and balls restored in mid fall stay within 0.01 pixels of the original run. A pile of dozens of bodies in contact drifts apart after a restore (a pile of 60 bodies was about a hundred pixels off after 30 to 200 steps), so do not rely on restore for lockstep or rollback of stacked bodies.

For replays, recreate the world instead of restoring it. With the fixed step (`world:step`), the same creation order, the same random seed and the same inputs on the same machine, two runs gave identical results in the tests (a pile of 60 bodies, 400 steps, differences of exactly 0), so a replay is "build the scene again, feed the recorded inputs frame by frame". Colliders get random ids, so key your recorded inputs by creation order or by your own names, not by `collider.id`. Results across different machines or LÖVE builds are not promised.

---

#### `:setColliderFilter(fn)`

Sets a function that decides, for every pair of solid colliders that touch, whether the contact is kept. Return `false` to reject it: the colliders pass through each other, no `enter`, `exit`, `pre` or `post` events are generated for that contact and the colliders' pre solve callbacks do not run. Any other return value, including `nil`, keeps the contact. Use it for rules that depend on the game state, like a ghost mode or a one-way platform.

```lua
world:setColliderFilter(function(a, b)
    if a.object and a.object.ghost then return false end
    if b.object and b.object.ghost then return false end
end)
```

The function runs when two colliders begin touching and again every step they keep touching, so keep it cheap. The order of the two colliders is unspecified. Sensor pairs (see `Collider:setSensor`) never reach the filter. Do not confuse it with the LÖVE `World:setContactFilter`, which still works and filters fixtures.

Arguments:

* `fn` `(function)` - Called as `fn(collider_a, collider_b)`. Pass `nil` to remove the filter

---

## Collider

On top of containing all functions exposed in this documentation it also contains all functions of a [Body](https://love2d.org/wiki/Body), [Fixture](https://love2d.org/wiki/Fixture) and [Shape](https://love2d.org/wiki/Shape).

---

#### `:destroy()`

Destroys the collider and removes it from the world. This must be called whenever the Collider is to discarded otherwise it will result in it not getting collected (and so memory will leak).

```lua
collider:destroy()
```

If it is called while the physics step is running (for example from a `preSolve` or `postSolve` callback), the collider is destroyed as soon as the step ends. Calling it twice is harmless.

---

#### `:setCollisionClass(collision_class_name)`

Sets this collider's collision class. The collision class must be a valid one previously added with `world:addCollisionClass`.

```lua
world:addCollisionClass('Player')
collider = world:newRectangleCollider(100, 100, 50, 50)
collider:setCollisionClass('Player')
```

Arguments:

* `collision_class_name` `(string)` - The name of the collision class

---

#### `:enter(other_collision_class_name)`

Checks for collision enter events from this collider with another. Enter events are generated on the frame when one collider enters contact with another.

```lua
-- in some update function
if collider:enter('Enemy') then
    print('Collision entered!')
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `boolean` - If the enter collision event between both colliders happened on this frame or not

---

#### `:getEnterCollisionData(other_collision_class_name)`

Gets the collision data generated from the last collision enter event

```lua
-- in some update function
if collider:enter('Enemy') then
    local collision_data = collider:getEnterCollisionData('Enemy')
    print(collision_data.collider, collision_data.contact)
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `collision_data` `(table)` - The data of the last enter collision event. The table has the fields `collider` (the other collider), `contact` (the [Contact](https://love2d.org/wiki/Contact), only valid during the physics step: do not call its functions later), `nx` and `ny` (the contact normal) and `x1`, `y1`, `x2`, `y2` (the contact points, `nil` when the contact has none).

---

#### `:exit(other_collision_class_name)`

Checks for collision exit events from this collider with another. Exit events are generated on the frame when one collider exits contact with another.

```lua
-- in some update function
if collider:exit('Enemy') then
    print('Collision exited!')
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `boolean` - If the exit collision event between both colliders happened on this frame or not

---

#### `:getExitCollisionData(other_collision_class_name)`

Gets the collision data generated from the last collision exit event

```lua
-- in some update function
if collider:exit('Enemy') then
    local collision_data = collider:getEnterCollisionData('Enemy')
    print(collision_data.collider, collision_data.contact)
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `collision_data` `(table)` - The data of the last exit collision event. The table has the fields `collider` (the other collider), `contact` (the [Contact](https://love2d.org/wiki/Contact), only valid during the physics step: do not call its functions later), `nx` and `ny` (the contact normal) and `x1`, `y1`, `x2`, `y2` (the contact points, `nil` when the contact has none).

---

#### `:getEnters(other_collision_class_name)`

Gets every enter event of this collider with colliders of a collision class on the current frame. `enter` only reports whether at least one happened; this returns all of them.

```lua
for _, collision_data in ipairs(player:getEnters('Coin')) do
    collision_data.collider:destroy()
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `collision_data_list` `(table[table])` - One table per enter event, with the fields described in `getEnterCollisionData`. Empty when there were none

---

#### `:getExits(other_collision_class_name)`

Same as `getEnters`, but for exit events.

```lua
for _, collision_data in ipairs(player:getExits('Platform')) do
    print('left', collision_data.collider)
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `collision_data_list` `(table[table])` - One table per exit event, with the fields described in `getEnterCollisionData`. Empty when there were none

---

#### `:onEnter(other_collision_class_name, callback)`

Calls a function every time this collider starts touching a collider of the given collision class. Like `world:onEnter` the callback runs after the physics step, so it is safe to create or destroy colliders in it. The handlers of a collider are removed when it is destroyed.

```lua
player:onEnter('Coin', function(player, coin, data)
    coin:destroy()
    score = score + 1
end)
```

Arguments:

* `other_collision_class_name` `(string)` - The collision class of the other collider
* `callback` `(function)` - Called as `callback(self, other, data)`, with `data` as in `getEnterCollisionData`. For two colliders of the same class each one is called once

Returns:

* `handle` `(table)` - A table with a `remove()` function that unregisters the callback

---

#### `:onExit(other_collision_class_name, callback)`

Same as `onEnter`, but called when the colliders stop touching.

Arguments:

* `other_collision_class_name` `(string)` - The collision class of the other collider
* `callback` `(function)` - Called as `callback(self, other, data)`

Returns:

* `handle` `(table)` - A table with a `remove()` function that unregisters the callback

---

#### `:stay(other_collision_class_name)`

Checks for collision stay events from this collider with another. Stay events are generated on every frame when one collider is in contact with another.

```lua
-- in some update function
if collider:stay('Enemy') then
    print('Collision staying!')
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `boolean` - If the stay collision event between both colliders is happening on this frame or not

---

#### `:getStayCollisionData(other_collision_class_name)`

Gets the collision data generated from the last collision stay event

```lua
-- in some update function
if collider:stay('Enemy') then
    local collision_data_list = collider:getStayCollisionData('Enemy')
    for _, collision_data in ipairs(collision_data_list) do
        print(collision_data.collider, collision_data.contact)
    end
end
```

Arguments:

* `other_collision_class_name` `(string)` - The name of the target collision class

Returns:

* `collision_data_list` `(table[table])` - The data of every collider this collider is currently touching, one table per collider with the fields described in `getEnterCollisionData`. Usually this list will be of size 1, but sometimes this collider will be staying in contact with multiple other colliders on the same frame, and so those multiple stay events (with multiple colliders) are returned. Contacts are tracked from the enter and exit events, so `enter` does not have to be called for `stay` to work.

---

#### `:setSensor(sensor)`

Makes the collider a sensor or a solid body again. A sensor passes through every other collider and still generates `enter`, `exit` and `stay` events for the collision classes it was set up with. This replaces the LÖVE `Fixture:setSensor` that used to be reachable through the collider: that call turned only the solid fixture into a sensor, which silently dropped every event of the collider.

```lua
pickup:setSensor(true)
if player:enter('Pickup') then ... end
```

Box2D only creates a contact when at least one of the two bodies is dynamic. A sensor on a static or kinematic body therefore reports nothing for another static or kinematic body, for example a static zone and a kinematic mover. Use a dynamic body for one of them.

Arguments:

* `sensor` `(boolean)` - Whether the collider is a sensor

---

#### `:isSensor()`

Returns whether the collider is a sensor, either through `setSensor`, the `sensor` setting or a sensor collision class.

Returns:

* `sensor` `(boolean)` - The sensor state

---

#### `:isPooled()`

Returns whether the collider is parked in a pool (released and not yet taken again).

Returns:

* `pooled` `(boolean)` - `true` while the collider is released

---

#### `:getGround(max_slope)`

Looks at the contacts of the collider and returns the ground under it. "Under" is relative to gravity: the direction opposite to `world:getGravity()`, or up the screen (negative y) when the world has no gravity. Contacts with sensors, contacts that are not touching and contacts disabled by a one-way platform or the collider filter are ignored. When several contacts qualify the flattest one is returned.

```lua
local ground = player:getGround()
if ground.grounded then
    print(ground.collider.collision_class, math.deg(ground.angle))
end
```

Arguments:

* `[max_slope=math.rad(50)]` `(number)` - The steepest slope, in radians from flat, that still counts as ground

Returns:

* `ground` `(table)` - `{grounded = false}` when there is no ground. Otherwise `grounded = true` and
  * `nx`, `ny` `(number)` - The unit normal of the ground, pointing from the ground to this collider
  * `angle` `(number)` - The slope in radians, 0 for flat ground
  * `collider` `(Collider)` - The collider that supports this one
  * `x`, `y` `(number)` - The first contact point
  * `contact` `(Contact)` - The LÖVE contact, only valid until the next physics step

---

#### `:moveKinematic(x, y, angle, dt)`

Sets the velocities of the body so that it arrives at a pose after `dt` seconds. Meant for kinematic bodies such as moving platforms, which the physics step then moves exactly, pushing whatever they touch. Call it before `world:update(dt)` every frame with the same `dt`.

```lua
platform:moveKinematic(target_x, target_y, math.pi / 2, dt)
world:update(dt)
```

Arguments:

* `x` `(number)` - The target x of the body center
* `y` `(number)` - The target y of the body center
* `[angle]` `(number)` - The target angle in radians; the body turns the short way round. `nil` leaves the rotation alone
* `dt` `(number)` - The time to get there, greater than zero

Box2D moves a body at most 2 meters per step (64 pixels at the default meter) and turns it at most a quarter turn, so a farther target is approached over several steps. Use `setPosition` to teleport.

---

#### `:driveTo(x, y, angle, strength)`

Soft keying: steers the body toward a pose with a velocity proportional to the remaining distance, so it follows the pose but can still be pushed by the world. Use it for ragdoll limbs that follow an animation, or for objects that follow the mouse. Call it every frame.

```lua
limb:driveTo(animation_x, animation_y, animation_angle, 10)
```

Arguments:

* `x` `(number)` - The target x of the body center
* `y` `(number)` - The target y of the body center
* `[angle]` `(number)` - The target angle in radians. `nil` leaves the rotation alone
* `strength` `(number)` - The gain in 1/second. The remaining distance shrinks by about 63 percent every `1/strength` seconds; keep `strength * dt` below 1 to avoid overshooting

---

#### `:setInterpolated(interpolated)`

Makes the world remember this collider's position and angle at the start of every fixed step done by `world:step`, so `getRenderPosition` and `getRenderAngle` can blend between the last two states. Interpolation only follows `world:step`; with `world:update` the previous state is not refreshed.

```lua
collider:setInterpolated(true)
```

Arguments:

* `interpolated` `(boolean)` - Whether to interpolate this collider

---

#### `:isInterpolated()`

Returns whether this collider is interpolated.

Returns:

* `interpolated` `(boolean)` - The interpolation flag

---

#### `:getRenderPosition()`

Returns the position to draw the collider at: the position between the last two fixed steps for an interpolated collider, using `world:getAlpha()`, and the plain `getPosition` otherwise.

```lua
local x, y = collider:getRenderPosition()
```

Returns:

* `x` `(number)` - The x position
* `y` `(number)` - The y position

---

#### `:getRenderAngle()`

Returns the angle to draw the collider at, interpolated the same way as `getRenderPosition`.

Returns:

* `angle` `(number)` - The angle in radians

---

#### `:setDrawOrder(order)`

Sets the position of this collider in the `world:draw` debug drawing. Colliders with a lower order are drawn first, colliders with the same order keep the order they were created in. The default is 0. This only matters for the debug drawing and for the draw hook below.

```lua
background_zone:setDrawOrder(-1)
```

Arguments:

* `order` `(number)` - The draw order

---

#### `:getDrawOrder()`

Returns:

* `order` `(number)` - The draw order, 0 by default

---

#### draw hook

If a collider has a `draw` function, `world:draw` calls it instead of drawing the debug shape of that collider. This lets you draw your own graphics where the colliders are, in the order given by `setDrawOrder`. The color and line width are not reset between colliders, so set what you need inside the function.

```lua
enemy.collider.draw = function(collider, alpha)
    love.graphics.setColor(1, 0.3, 0.3, alpha / 255)
    local x, y = collider:getPosition()
    love.graphics.circle('fill', x, y, 12)
end
world:draw()
```

The function is called as `collider:draw(alpha)` with the alpha given to `world:draw`, from 0 to 255 (255 when none was given). Bodies that were not created through the library are still drawn as debug shapes.

---

#### `:setPreSolve(callback)`

Sets the preSolve callback. Unlike with `:enter` or `:exit` that can be delayed and checked after the physics simulation is done for this frame, both preSolve and postSolve must be callbacks that are resolved immediately, since they may change how the rest of the simulation plays out on this frame.

```lua
collider:setPreSolve(function(collider_1, collider_2, contact)
    contact:setEnabled(false)
end
```

Arguments:

* `callback` `(function)` - The preSolve callback. Receives `collider_1`, `collider_2` and `contact` as arguments

---

#### `:setPostSolve(callback)`

Sets the postSolve callback. Unlike with `:enter` or `:exit` that can be delayed and checked after the physics simulation is done for this frame, both preSolve and postSolve must be callbacks that are resolved immediately, since they may change how the rest of the simulation plays out on this frame.

```lua
collider:setPostSolve(function(collider_1, collider_2, contact, ni1, ti1, ni2, ti2)
    contact:setEnabled(false)
end
```

Arguments:

* `callback` `(function)` - The postSolve callback. Receives `collider_1`, `collider_2`, `contact`, `normal_impulse1`, `tangent_impulse1`, `normal_impulse2` and `tangent_impulse2` as arguments

---

#### `:addShape(shape_name, shape_type, ...)`

Adds a shape to the collider. A shape can be accessed via collider.shapes[shape_name]. A fixture of the same name is also added to attach the shape to the collider body. A fixture can be accessed via collider.fixtures[fixture_name].

Arguments:

* `shape_name` `(string)` - The unique name of the shape
* `shape_type` `(string)` - The shape type, can be `'ChainShape'`, `'CircleShape'`, `'EdgeShape'`, `'PolygonShape'` or `'RectangleShape'`
* `...` `(*)` - The shape creation arguments that are different for each shape. Check [here](https://love2d.org/wiki/Shape) for more details

---

#### `:removeShape(shape_name)`

Removes a shape from the collider (also removes the accompanying fixture).

Arguments:

* `shape_name` `(string)` - The unique name of the shape to be removed. Must be a name previously added with `:addShape`

---

#### `:setObject(object)`

Sets the collider's object. This is useful to set to the object the collider belongs to, so that when a query call is made and colliders are returned you can immediately get the pertinent object.

```lua
-- in the constructor of some object
self.collider = world:newRectangleCollider(...)
self.collider:setObject(self)
```

Arguments:

* `object` `(*)` - The object that this collider belongs to

---

#### `:getObject()`

Gets the object a collider belongs to.

```lua
-- in an update function
if self.collider:enter('Enemy') then
    local collision_data = self.collider:getEnterCollisionData('SomeTag')
    -- gets the reference to the enemy object, the enemy object must have used :setObject(self) to attach itself to the collider otherwise this wouldn't work
    local enemy = collision_data.collider:getObject()
end
```

Returns:

* `object` `(*)` - The object that is attached to this collider

---

# LICENSE

You can do whatever you want with this. See the license at the top of the main file.
