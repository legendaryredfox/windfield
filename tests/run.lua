-- Run from the repository root: lua tests/run.lua
-- Works on luajit, lua5.1, lua5.4 and lua5.5.
package.path = './?.lua;./?/init.lua;' .. package.path

love = require('tests.mock_love')()

local unpack = table.unpack or unpack
local wf = require('windfield')

local failures, count = 0, 0

local function test(name, fn)
    count = count + 1
    local ok, err = pcall(fn)
    if not ok then
        failures = failures + 1
        print('FAIL ' .. name .. '\n     ' .. tostring(err))
    end
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or 'value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
    end
end

local function truthy(value, label)
    if not value then error((label or 'value') .. ': expected a truthy value', 2) end
end

local function raises(fn, label)
    if pcall(fn) then error((label or 'call') .. ': expected an error', 2) end
end

local function newWorld()
    return wf.newWorld(0, 100, true)
end

test('the module does not leak globals', function()
    eq(rawget(_G, 'World'), nil, 'World global')
    eq(rawget(_G, 'Collider'), nil, 'Collider global')
end)

test('the meter is set by the first world and by options.meter, never reset by later worlds', function()
    love.physics.setMeter(30)
    love.physics.meter_calls = 0
    wf.newWorld(0, 0, true, {meter = 64})
    eq(love.physics.getMeter(), 64, 'options.meter')
    love.physics.setMeter(50)
    wf.newWorld(0, 0, true)
    eq(love.physics.getMeter(), 50, 'second world without options')
    raises(function() wf.newWorld(0, 0, true, {meter = 'x'}) end, 'invalid meter')
end)

test('newWorld has the Default class and forwards Box2D methods', function()
    local world = newWorld()
    truthy(world.collision_classes.Default, 'Default class')
    world:setGravity(1, 2)
    local gx, gy = world:getGravity()
    eq(gx, 1, 'gx')
    eq(gy, 2, 'gy')
end)

test('addCollisionClass rejects duplicates and setCollisionClass rejects unknown names', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    raises(function() world:addCollisionClass('Player') end, 'duplicate class')
    local collider = world:newCircleCollider(0, 0, 5)
    raises(function() collider:setCollisionClass('Nope') end, 'unknown class')
end)

test('collider methods resolve to the shape, then the fixture, then the body', function()
    local world = newWorld()
    local rectangle = world:newRectangleCollider(0, 0, 10, 10)
    eq(rectangle:probe(), 'shape')
    eq(rectangle:probeFixtureBody(), 'fixture')
    eq(rectangle:getPosition(), 5, 'body method')
    eq(rectangle.getRadius, nil, 'shape specific method on another shape type')
    eq(rectangle.nonexistent, nil, 'unknown name')
    eq(world:newCircleCollider(0, 0, 3):getRadius(), 3, 'circle method')
end)

test('colliders do not carry a copy of every method', function()
    local collider = newWorld():newRectangleCollider(0, 0, 10, 10)
    local keys = 0
    for _ in pairs(collider) do keys = keys + 1 end
    truthy(keys < 30, 'keys on a collider: ' .. keys)
end)

test('proxied names never shadow class methods', function()
    local names = dofile('tests/fixtures/proxy_keys.lua')
    local overrides = {preSolve = true, postSolve = true, setSensor = true, isSensor = true}
    for _, name in ipairs(names.collider) do
        if not overrides[name] then eq(rawget(wf.Collider, name), nil, 'Collider.' .. name) end
    end
    for _, name in ipairs(names.world) do
        eq(rawget(wf.World, name), nil, 'World.' .. name)
    end
end)

test('every collider type can be created', function()
    local world = newWorld()
    eq(world:newCircleCollider(10, 10, 5).type, 'Circle')
    eq(world:newRectangleCollider(10, 10, 20, 20).type, 'Rectangle')
    eq(world:newBSGRectangleCollider(10, 10, 20, 20, 4).type, 'BSGRectangle')
    eq(world:newPolygonCollider({0, 0, 10, 0, 5, 10}).type, 'Polygon')
    eq(world:newLineCollider(0, 0, 10, 10).type, 'Line')
end)

test('rectangle collider body sits at the rectangle center and honors settings', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local collider = world:newRectangleCollider(100, 200, 40, 20, {collision_class = 'Wall', body_type = 'static'})
    local x, y = collider:getPosition()
    eq(x, 120, 'x')
    eq(y, 210, 'y')
    eq(collider.collision_class, 'Wall')
    eq(collider.body.body_type, 'static')
end)

test('settings keys map to Box2D calls', function()
    local world = newWorld()
    local payload = {}
    local collider = world:newRectangleCollider(0, 0, 10, 10, {
        bullet = true, fixed_rotation = true, gravity_scale = 0.5, linear_damping = 1, angular_damping = 2,
        sleeping_allowed = false, active = false, angle = 1.5, restitution = 0.3, friction = 0.4, density = 2,
        object = payload,
    })
    local body_calls = collider.body.calls
    eq(body_calls.setBullet[1], true, 'bullet')
    eq(body_calls.setFixedRotation[1], true, 'fixed_rotation')
    eq(body_calls.setGravityScale[1], 0.5, 'gravity_scale')
    eq(body_calls.setLinearDamping[1], 1, 'linear_damping')
    eq(body_calls.setAngularDamping[1], 2, 'angular_damping')
    eq(body_calls.setSleepingAllowed[1], false, 'sleeping_allowed')
    eq(body_calls.setActive[1], false, 'active')
    eq(body_calls.setAngle[1], 1.5, 'angle')
    truthy(body_calls.resetMassData, 'mass reset after density')
    local fixture_calls = collider.fixtures.main.calls
    eq(fixture_calls.setRestitution[1], 0.3, 'restitution')
    eq(fixture_calls.setFriction[1], 0.4, 'friction')
    eq(fixture_calls.setDensity[1], 2, 'density')
    eq(collider.sensors.main.calls, nil, 'sensor fixture is left alone')
    eq(collider:getObject(), payload, 'object')
end)

test('settings without the new keys make no extra Box2D calls', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5, {body_type = 'static'})
    eq(collider.body.calls, nil, 'body calls')
    eq(collider.fixtures.main.calls, nil, 'fixture calls')
end)

test('unknown settings keys raise and leave no body behind', function()
    local world = newWorld()
    local before = #world:getBodies()
    raises(function() world:newCircleCollider(0, 0, 5, {restitutoin = 1}) end, 'typo')
    eq(#world:getBodies(), before, 'bodies')
end)

test('step runs fixed updates from accumulated time', function()
    local world = newWorld()
    local updates = 0
    world.box2d_world.step_hook = function() updates = updates + 1 end
    eq(world:step(1 / 30), 2, 'steps for 1/30')
    eq(updates, 2, 'updates')
    eq(world:step(1 / 120), 0, 'half a step')
    eq(world:getAlpha(), 0.5, 'alpha after half a step')
    eq(world:step(1 / 120), 1, 'second half')
    eq(updates, 3, 'updates after halves')
end)

test('step caps the number of updates and drops the excess time', function()
    local world = newWorld()
    local updates = 0
    world.box2d_world.step_hook = function() updates = updates + 1 end
    eq(world:step(10), 5, 'default max_steps')
    eq(world:step(0), 0, 'accumulator was clamped')
    truthy(world:getAlpha() < 1, 'alpha below one')
    world:setFixedStep(1 / 30, 2)
    updates = 0
    eq(world:step(1), 2, 'custom max_steps')
    eq(world:step(1 / 30), 1, 'custom fixed step')
    raises(function() world:setFixedStep(0, 5) end, 'zero step')
    raises(function() world:setFixedStep(1 / 60, 0) end, 'zero max_steps')
end)

test('interpolated colliders render between the last two fixed steps', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    local other = world:newCircleCollider(0, 0, 5)
    world.box2d_world.step_hook = function()
        collider.body.x = collider.body.x + 10
        collider.body.angle = (collider.body.angle or 0) + 1
        other.body.x = other.body.x + 10
    end
    collider:setInterpolated(true)
    truthy(collider:isInterpolated(), 'isInterpolated')
    world:step(1 / 60)
    local x = collider:getRenderPosition()
    eq(x, 0, 'alpha 0 returns the previous position')
    eq(collider:getRenderAngle(), 0, 'alpha 0 returns the previous angle')
    world:step(1 / 60 + 1 / 120)
    local rx = collider:getRenderPosition()
    eq(rx, 15, 'half way between 10 and 20')
    eq(collider:getRenderAngle(), 1.5, 'half way between angles')
    eq(select(1, other:getRenderPosition()), 20, 'colliders that are not interpolated render at their position')
    collider:setInterpolated(false)
    eq(select(1, collider:getRenderPosition()), 20, 'interpolation off')
end)

test('destroying an interpolated collider releases it', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    collider:setInterpolated(true)
    collider:destroy()
    eq(next(world.interpolated), nil, 'interpolated set')
    world:step(1 / 60)
end)

test('ignores produce category and mask entries', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Ghost', {ignores = {'Player'}})
    local ghost, player = world.masks.Ghost, world.masks.Player
    truthy(ghost and player, 'masks')
    local ignored = false
    for _, category in ipairs(ghost.masks) do
        if category == player.categories[1] then ignored = true end
    end
    truthy(ignored, 'Ghost mask lists the Player category')
    local collider = world:newCircleCollider(0, 0, 5, {collision_class = 'Ghost'})
    eq(collider.fixture.category[1], ghost.categories[1], 'fixture category')
end)

test('adding a class updates the categories and masks of existing colliders', function()
    local world = newWorld()
    world:addCollisionClass('A')
    local early = world:newCircleCollider(0, 0, 5, {collision_class = 'A'})
    world:addCollisionClass('B', {ignores = {'A'}})
    local late = world:newCircleCollider(0, 0, 5, {collision_class = 'B'})
    for _, collider in ipairs({early, late}) do
        local expected = world.masks[collider.collision_class]
        eq(collider.fixture.category[1], expected.categories[1], collider.collision_class .. ' category')
        eq(#collider.fixture.mask, #expected.masks, collider.collision_class .. ' mask size')
        for i, category in ipairs(expected.masks) do
            eq(collider.fixture.mask[i], category, collider.collision_class .. ' mask ' .. i)
        end
    end
    truthy(early.fixture.category[1] ~= late.fixture.category[1], 'A and B are in different categories')
end)

test('setCollisionClass reapplies category and mask', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    local collider = world:newCircleCollider(0, 0, 5)
    collider:setCollisionClass('Player')
    eq(collider.collision_class, 'Player')
    eq(collider.fixture.category[1], world.masks.Player.categories[1])
end)

test('queries return matching colliders', function()
    local world = newWorld()
    world:addCollisionClass('Crate')
    world:addCollisionClass('Wall')
    local crate = world:newRectangleCollider(100, 100, 50, 50, {collision_class = 'Crate'})
    local wall = world:newRectangleCollider(300, 300, 50, 50, {collision_class = 'Wall'})

    local found = world:queryRectangleArea(90, 90, 80, 80, {'All'})
    eq(#found, 1, 'rectangle query count')
    eq(found[1], crate, 'rectangle query result')

    eq(#world:queryRectangleArea(0, 0, 10, 10), 0, 'rectangle query far away')

    found = world:queryCircleArea(125, 100, 10, {'Crate'})
    eq(#found, 1, 'circle query count')

    found = world:queryPolygonArea({80, 80, 200, 80, 140, 200})
    eq(#found, 1, 'polygon query count')
    eq(found[1], crate, 'polygon query result')

    found = world:queryLine(0, 0, 500, 500, {'All', except = {'Crate'}})
    eq(#found, 1, 'line query count')
    eq(found[1], wall, 'line query result')
end)

test('area queries handle circle colliders', function()
    local world = newWorld()
    local circle = world:newCircleCollider(100, 100, 10)

    eq(world:queryCircleArea(115, 100, 10)[1], circle, 'circle query overlapping')
    eq(#world:queryCircleArea(150, 100, 10), 0, 'circle query far away')

    eq(world:queryRectangleArea(95, 95, 10, 10)[1], circle, 'rectangle query over the center')
    eq(world:queryRectangleArea(105, 90, 30, 20)[1], circle, 'rectangle query crossing the edge')
    eq(#world:queryRectangleArea(120, 90, 30, 20), 0, 'rectangle query far away')

    eq(world:queryPolygonArea({80, 80, 120, 80, 100, 120})[1], circle, 'polygon query over the center')
    eq(#world:queryPolygonArea({200, 200, 240, 200, 220, 240}), 0, 'polygon query far away')
end)

test('event tables are created only for colliders that receive events', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    local idle = world:newCircleCollider(0, 0, 5)
    world:update(0)
    eq(next(idle.collision_events), nil, 'idle collider')

    love._fire(world, 'enter', player.fixture, coin.fixture)
    truthy(player:enter('Coin'), 'enter')
    eq(next(idle.collision_events), nil, 'idle collider after an event elsewhere')
    eq(#world.dirty_colliders, 2, 'colliders with events')

    world:update(0)
    eq(#world.dirty_colliders, 0, 'dirty list after update')
    eq(next(player.collision_events), nil, 'events cleared')
end)

test('area queries match the reference implementation', function()
    local reference = dofile('tests/reference_queries.lua')
    math.randomseed(1234)

    local function key(colliders)
        local ids = {}
        for i, collider in ipairs(colliders) do ids[i] = collider:getObject() end
        table.sort(ids)
        return table.concat(ids, ',')
    end

    local function regular(cx, cy, radius, sides)
        local vertices = {}
        for i = 0, sides - 1 do
            local angle = i * 2 * math.pi / sides
            vertices[#vertices + 1] = cx + radius * math.cos(angle)
            vertices[#vertices + 1] = cy + radius * math.sin(angle)
        end
        return vertices
    end

    local filters = {false, {'All'}, {'A', 'B'}, {'All', except = {'A'}}, {'C'}}
    local names = {'Default', 'A', 'B', 'C'}
    local compared = 0

    for round = 1, 25 do
        local world = newWorld()
        for _, name in ipairs({'A', 'B', 'C'}) do world:addCollisionClass(name) end
        for i = 1, 25 do
            local settings = {collision_class = names[math.random(#names)]}
            local x, y, kind = math.random(0, 300), math.random(0, 300), math.random(4)
            local collider
            if kind == 1 then
                collider = world:newCircleCollider(x, y, math.random(3, 25), settings)
            elseif kind == 2 then
                collider = world:newRectangleCollider(x, y, math.random(5, 60), math.random(5, 60), settings)
            elseif kind == 3 then
                collider = world:newPolygonCollider(regular(x, y, math.random(8, 30), math.random(3, 6)), settings)
            else
                collider = world:newRectangleCollider(x, y, math.random(10, 40), math.random(10, 40), settings)
                collider:addShape('extra', 'CircleShape', 8)
            end
            collider:setObject(i)
        end

        for _ = 1, 12 do
            local filter = filters[math.random(#filters)] or nil
            local x, y = math.random(-20, 340), math.random(-20, 340)
            local sides = math.random(3, 6)
            local radius, w, h = math.random(5, 90), math.random(10, 160), math.random(10, 160)
            local polygon = regular(x, y, math.random(10, 90), sides)
            local results = {
                circle = {world:queryCircleArea(x, y, radius, filter), reference.queryCircleArea(world, x, y, radius, filter)},
                rectangle = {world:queryRectangleArea(x, y, w, h, filter), reference.queryRectangleArea(world, x, y, w, h, filter)},
                polygon = {world:queryPolygonArea(polygon, filter), reference.queryPolygonArea(world, polygon, filter)},
                line = {world:queryLine(x, y, x + w, y + h, filter), reference.queryLine(world, x, y, x + w, y + h, filter)},
            }
            for kind, pair in pairs(results) do
                eq(key(pair[1]), key(pair[2]), kind .. ' query, round ' .. round)
                compared = compared + 1
            end
        end
    end
    eq(compared, 25 * 12 * 4, 'comparisons made')
end)

test('area query rules', function()
    local failed_cases = {}
    for _, case in ipairs(dofile('tests/fixtures/query_cases.lua')) do
        local name, shape, query, expected = case[1], case[2], case[3], case[4]
        if not case.line then
            local world = newWorld()
            if shape.kind == 'rectangle' then
                world:newRectangleCollider(shape[1], shape[2], shape[3], shape[4])
            else
                world:newCircleCollider(shape[1], shape[2], shape[3])
            end
            local found
            if query.kind == 'circle' then
                found = world:queryCircleArea(query[1], query[2], query[3])
            elseif query.kind == 'rectangle' then
                found = world:queryRectangleArea(query[1], query[2], query[3], query[4])
            else
                found = world:queryPolygonArea({unpack(query)})
            end
            if (#found > 0) ~= expected then failed_cases[#failed_cases + 1] = name end
        end
    end
    eq(table.concat(failed_cases, '; '), '', 'cases that differ from the documented rules')
end)

local function rayHit(collider, fraction)
    collider.fixtures.main.ray = {x = fraction * 100, y = 5, xn = 0, yn = -1, fraction = fraction}
end

test('raycast returns every hit sorted by distance', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local far = world:newCircleCollider(0, 0, 5)
    local near = world:newCircleCollider(0, 0, 5, {collision_class = 'Wall'})
    local mid = world:newCircleCollider(0, 0, 5)
    rayHit(far, 0.7)
    rayHit(near, 0.2)
    rayHit(mid, 0.5)
    local hits = world:raycast(0, 0, 100, 0)
    eq(#hits, 3, 'hit count (sensor fixtures are skipped)')
    eq(hits[1].collider, near, 'nearest first')
    eq(hits[2].collider, mid, 'middle second')
    eq(hits[3].collider, far, 'farthest last')
    eq(hits[1].fraction, 0.2, 'fraction')
    eq(hits[1].x, 20, 'x')
    eq(hits[1].y, 5, 'y')
    eq(hits[1].nx, 0, 'nx')
    eq(hits[1].ny, -1, 'ny')
end)

test('raycast closest returns one hit and honors the class filter', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local far = world:newCircleCollider(0, 0, 5)
    local near = world:newCircleCollider(0, 0, 5, {collision_class = 'Wall'})
    rayHit(far, 0.7)
    rayHit(near, 0.2)
    local hit = world:raycast(0, 0, 100, 0, nil, 'closest')
    eq(hit.collider, near, 'closest collider')
    eq(hit.fraction, 0.2, 'closest fraction')
    hit = world:raycast(0, 0, 100, 0, {'Default'}, 'closest')
    eq(hit.collider, far, 'filtered closest')
    eq(#world:raycast(0, 0, 100, 0, {'All', except = {'Wall'}}), 1, 'except filter')
    eq(world:raycast(0, 0, 100, 0, {'Nothing'}, 'closest'), nil, 'no hit')
    eq(#world:raycast(0, 0, 100, 0, {'Nothing'}), 0, 'empty list')
    raises(function() world:raycast(0, 0, 1, 1, nil, 'first') end, 'unknown mode')
end)

test('raycast skips colliders waiting to be destroyed and matches queryLine', function()
    local world = newWorld()
    local kept = world:newCircleCollider(0, 0, 5)
    local gone = world:newCircleCollider(0, 0, 5)
    gone.destroy_pending = true
    rayHit(kept, 0.4)
    local hits = world:raycast(0, 0, 100, 0)
    eq(#hits, 1, 'hits')
    eq(hits[1].collider, kept, 'collider')
    local line = world:queryLine(0, 0, 100, 0)
    eq(#line, 1, 'queryLine agrees')
    eq(line[1], kept, 'queryLine collider')
end)

test('queryPoint returns colliders whose solid fixture contains the point', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local box = world:newRectangleCollider(0, 0, 10, 10, {collision_class = 'Wall'})
    local ball = world:newCircleCollider(50, 50, 5)
    eq(#world:queryPoint(5, 5), 1, 'inside the rectangle')
    eq(world:queryPoint(5, 5)[1], box, 'rectangle collider')
    eq(#world:queryPoint(10, 5), 1, 'on the edge')
    eq(#world:queryPoint(11, 5), 0, 'outside the rectangle')
    eq(world:queryPoint(52, 52)[1], ball, 'inside the circle')
    eq(#world:queryPoint(56, 50), 0, 'outside the circle')
    eq(#world:queryPoint(5, 5, {'Default'}), 0, 'class filter')
    eq(#world:queryPoint(5, 5, {'All', except = {'Default'}}), 1, 'except filter')
    box.destroy_pending = true
    eq(#world:queryPoint(5, 5), 0, 'destroy pending colliders are skipped')
end)

test('getColliderAt returns one collider or nil', function()
    local world = newWorld()
    local box = world:newRectangleCollider(0, 0, 10, 10)
    eq(world:getColliderAt(5, 5), box, 'hit')
    eq(world:getColliderAt(50, 50), nil, 'miss')
    eq(world:getColliderAt(5, 5, {'Nothing'}), nil, 'filtered')
end)

test('queryShape finds colliders that overlap the shape with an exact distance test', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local box = world:newRectangleCollider(0, 0, 10, 10, {collision_class = 'Wall'})
    local ball = world:newCircleCollider(100, 100, 5)
    local hits = world:queryShape({type = 'circle', radius = 10}, 5, 5)
    eq(#hits, 1, 'circle overlapping the box')
    eq(hits[1], box, 'collider')
    eq(#world:queryShape({type = 'circle', radius = 10}, 5, 5, {'Default'}), 0, 'class filter')
    eq(#world:queryShape({type = 'rectangle', w = 10, h = 10}, 100, 100), 1, 'rectangle centered on the point')
    eq(world:queryShape({type = 'rectangle', w = 10, h = 10}, 100, 100)[1], ball, 'rectangle hit')
    eq(#world:queryShape({type = 'polygon', vertices = {0, 0, 20, 0, 20, 20, 0, 20}}, 2, 2), 1, 'polygon relative to the point')
    eq(#world:queryShape({type = 'edge', x1 = -5, y1 = 5, x2 = 5, y2 = 5}, 0, 0), 1, 'edge crossing the box')
    eq(#world:queryShape({type = 'circle', radius = 1}, 500, 500), 0, 'nothing nearby')
    box.destroy_pending = true
    eq(#world:queryShape({type = 'circle', radius = 10}, 5, 5), 0, 'colliders waiting to be destroyed')
end)

test('queryShape returns a collider once and tests every segment of a chain', function()
    local world = newWorld()
    local multi = world:newRectangleCollider(0, 0, 10, 10)
    multi:addShape('extra', 'RectangleShape', 10, 10)
    eq(#world:queryShape({type = 'circle', radius = 20}, 5, 5), 1, 'two shapes, one hit')

    local chain = world:newChainCollider({0, 500, 10, 500, 10, 600, 20, 600}, false, {body_type = 'static'})
    local hits = world:queryShape({type = 'circle', radius = 2}, 15, 600)
    eq(hits[1], chain, 'near the last segment')
    eq(#world:queryShape({type = 'circle', radius = 2}, 5, 550), 0, 'inside the chain box but away from every segment')
    eq(#world:queryShape({type = 'circle', radius = 2}, 10, 550), 1, 'on the middle segment')
end)

local function near(actual, expected, tolerance, label)
    if math.abs(actual - expected) > tolerance then
        error((label or 'value') .. ': expected about ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
    end
end

test('shapeCast reports the first hit with fraction, point and normal', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local wall = world:newRectangleCollider(100, 0, 10, 10, {collision_class = 'Wall', body_type = 'static'})
    local far = world:newRectangleCollider(200, 0, 10, 10, {body_type = 'static'})
    local box = {type = 'rectangle', w = 10, h = 10}

    local hit = world:shapeCast(box, 0, 5, 300, 0)
    eq(hit.collider, wall, 'nearest collider')
    near(hit.fraction, 95 / 300, 1e-6, 'fraction')
    near(hit.x, 100, 1e-6, 'point x')
    eq(hit.nx, -1, 'normal x points back at the mover')
    near(hit.ny, 0, 1e-6, 'normal y')
    eq(hit.overlap, nil, 'not an initial overlap')

    hit = world:shapeCast(box, 0, 5, 300, 0, {'All', except = {'Wall'}})
    eq(hit.collider, far, 'class filter skips the nearer wall')
    near(hit.fraction, 195 / 300, 1e-6, 'fraction past the filtered wall')

    eq(world:shapeCast(box, 0, 5, 50, 0), nil, 'movement too short')
    eq(world:shapeCast(box, 0, 5, -300, 0), nil, 'moving away')
    eq(world:shapeCast(box, 0, 50, 300, 0), nil, 'moving past on the side')
    eq(world:shapeCast(box, 0, 5, 300, 0, {'Nothing'}), nil, 'no class matches')
end)

test('shapeCast handles initial overlap, zero movement, diagonal moves and chains', function()
    local world = newWorld()
    local wall = world:newRectangleCollider(100, 0, 10, 10, {body_type = 'static'})
    local box = {type = 'rectangle', w = 10, h = 10}

    local hit = world:shapeCast(box, 100, 5, 50, 0)
    eq(hit.collider, wall, 'overlapping collider')
    eq(hit.fraction, 0, 'overlap fraction')
    eq(hit.overlap, true, 'overlap flag')
    eq(hit.nx, -1, 'overlap normal opposes the movement')
    eq(world:shapeCast(box, 100, 5, 0, 0).overlap, true, 'zero movement is an overlap test')
    eq(world:shapeCast(box, 0, 5, 0, 0), nil, 'zero movement without overlap')

    hit = world:shapeCast(box, 0, -95, 200, 200)
    eq(hit.collider, wall, 'diagonal hit')
    truthy(hit.fraction > 0 and hit.fraction < 1, 'diagonal fraction')

    local chain = world:newChainCollider({0, 500, 10, 500, 10, 600, 20, 600}, false, {body_type = 'static'})
    hit = world:shapeCast({type = 'circle', radius = 2}, 15, 550, 0, 100)
    eq(hit.collider, chain, 'chain')
    near(hit.y, 600, 1e-6, 'chain point')
    eq(world:shapeCast({type = 'circle', radius = 2}, 5, 540, 0, 100), nil, 'between chain segments')
end)

test('shapeCast validates its arguments and releases its fixtures', function()
    local world = newWorld()
    raises(function() world:shapeCast({type = 'triangle'}, 0, 0, 1, 0) end, 'unknown type')
    raises(function() world:shapeCast({type = 'circle', radius = 1}, 0, 0, 'x', 0) end, 'bad movement')
    world:shapeCast({type = 'circle', radius = 1}, 0, 0, 10, 0)
    eq(#world.query_body:getFixtures(), 0, 'query fixtures are destroyed')
end)

local function touch(body, fixture_a, fixture_b, nx, ny, extra)
    local contact = love._newContact({nx = nx, ny = ny, positions = {0, 0}, fixtures = {fixture_a, fixture_b}})
    for key, value in pairs(extra or {}) do contact[key] = value end
    body.contacts = body.contacts or {}
    body.contacts[#body.contacts + 1] = contact
    return contact
end

test('getGround reports the supporting contact, its normal and slope', function()
    local world = newWorld()
    world:setGravity(0, 500)
    local player = world:newCircleCollider(0, 0, 5)
    local floor = world:newRectangleCollider(0, 10, 100, 10, {body_type = 'static'})
    eq(player:getGround().grounded, false, 'no contacts')

    touch(player.body, floor.fixture, player.fixture, 0, -1)
    local ground = player:getGround()
    eq(ground.grounded, true, 'standing on the floor')
    eq(ground.nx, 0, 'normal x')
    eq(ground.ny, -1, 'normal y points from the ground to the player')
    near(ground.angle, 0, 1e-9, 'flat angle')
    eq(ground.collider, floor, 'ground collider')

    player.body.contacts = {}
    touch(player.body, player.fixture, floor.fixture, 0, 1)
    eq(player:getGround().ny, -1, 'normal flips when the player is fixture A')

    player.body.contacts = {}
    touch(player.body, floor.fixture, player.fixture, math.sin(math.rad(30)), -math.cos(math.rad(30)))
    near(player:getGround().angle, math.rad(30), 1e-9, 'slope angle')
    eq(player:getGround(math.rad(20)).grounded, false, 'slope steeper than max_slope')

    player.body.contacts = {}
    local wall = world:newRectangleCollider(50, 0, 10, 10, {body_type = 'static'})
    touch(player.body, wall.fixture, player.fixture, 1, 0)
    eq(player:getGround().grounded, false, 'a wall is not ground')
    touch(player.body, floor.fixture, player.fixture, 0, -1, {touching = false})
    touch(player.body, floor.fixture, player.fixture, 0, -1, {enabled = false})
    touch(player.body, floor.sensors.main, player.fixture, 0, -1)
    eq(player:getGround().grounded, false, 'untouching, disabled and sensor contacts are skipped')

    touch(player.body, floor.fixture, player.fixture, math.sin(math.rad(40)), -math.cos(math.rad(40)))
    touch(player.body, floor.fixture, player.fixture, 0, -1)
    eq(player:getGround().ny, -1, 'the flattest contact wins')

    world:setGravity(0, 0)
    player.body.contacts = {}
    touch(player.body, floor.fixture, player.fixture, 0, -1)
    eq(player:getGround().grounded, true, 'without gravity up is negative y')
    world:setGravity(0, -500)
    eq(player:getGround().grounded, false, 'upside down gravity makes the floor a ceiling')
end)

test('moveKinematic and driveTo set velocities toward a pose', function()
    local world = newWorld()
    local body = world:newRectangleCollider(0, 0, 10, 10, {body_type = 'kinematic'})
    local x, y = body:getPosition()
    body.body.angle = 3
    body:moveKinematic(x + 60, y + 120, -3, 0.5)
    local vx, vy = body:getLinearVelocity()
    near(vx, 120, 1e-9, 'vx reaches the target in dt')
    near(vy, 240, 1e-9, 'vy')
    near(body.body.calls.setAngularVelocity[1], (2 * math.pi - 6) / 0.5, 1e-9, 'angular velocity takes the short way round')
    raises(function() body:moveKinematic(0, 0, 0, 0) end, 'zero dt')

    body.body.angle = 0
    body:setPosition(10, 20)
    body:driveTo(40, 80, 1, 4)
    vx, vy = body:getLinearVelocity()
    near(vx, 120, 1e-9, 'driveTo vx is gain times error')
    near(vy, 240, 1e-9, 'driveTo vy')
    near(body.body.calls.setAngularVelocity[1], 4, 1e-9, 'driveTo angular velocity')
    body:driveTo(40, 80, nil, 4)
    near(body.body.calls.setAngularVelocity[1], 4, 1e-9, 'a missing angle leaves the rotation alone')
end)

test('timers count down for coyote time and jump buffering', function()
    local timer = wf.newTimer(0.1)
    eq(timer:isActive(), false, 'idle at first')
    timer:start()
    eq(timer:isActive(), true, 'active after start')
    timer:update(0.06)
    eq(timer:isActive(), true, 'still active')
    timer:update(0.06)
    eq(timer:isActive(), false, 'expired')
    timer:start()
    eq(timer:consume(), true, 'consume while active')
    eq(timer:isActive(), false, 'consume clears the timer')
    eq(timer:consume(), false, 'nothing to consume')
    timer:start(0.5)
    timer:update(0.3)
    eq(timer:isActive(), true, 'start takes a duration override')
    raises(function() wf.newTimer(0) end, 'zero duration')
end)

local function shapeArea(points)
    local area, count = 0, #points / 2
    for i = 1, count do
        local j = i % count + 1
        area = area + points[2 * i - 1] * points[2 * j] - points[2 * j - 1] * points[2 * i]
    end
    return math.abs(area) / 2
end

local function piecesOf(collider)
    local pieces = {}
    for _, shape in pairs(collider.shapes) do pieces[#pieces + 1] = shape.points end
    return pieces
end

local function totalArea(collider)
    local sum = 0
    for _, points in ipairs(piecesOf(collider)) do sum = sum + shapeArea(points) end
    return sum
end

test('concave polygon colliders are split into convex pieces', function()
    local world = newWorld()
    local l_shape = world:newConcavePolygonCollider({0, 0, 20, 0, 20, 10, 10, 10, 10, 20, 0, 20})
    truthy(#piecesOf(l_shape) <= 2, 'an L shape needs at most two convex pieces, got ' .. #piecesOf(l_shape))
    near(totalArea(l_shape), 300, 1e-6, 'the pieces cover the L exactly')
    truthy(l_shape.shapes.main and l_shape.fixtures.main and l_shape.sensors.main, 'main piece')
    eq(l_shape.type, 'Polygon', 'collider type')

    local star = world:newConcavePolygonCollider({0, -20, 5, -5, 20, -5, 8, 3, 12, 18, 0, 8, -12, 18, -8, 3, -20, -5, -5, -5})
    near(totalArea(star), 479, 1e-6, 'star area')
    for _, points in ipairs(piecesOf(star)) do truthy(#points / 2 <= 8, 'at most 8 vertices per piece') end
    truthy(#piecesOf(star) >= 2, 'a star is split')

    local square = world:newConcavePolygonCollider({0, 0, 10, 0, 10, 10, 0, 10})
    eq(#piecesOf(square), 1, 'a convex polygon stays in one piece')
    local clockwise = world:newConcavePolygonCollider({0, 0, 0, 20, 10, 20, 10, 10, 20, 10, 20, 0})
    near(totalArea(clockwise), 300, 1e-6, 'clockwise winding')
    local closed = world:newConcavePolygonCollider({0, 0, 10, 0, 10, 10, 0, 10, 0, 0})
    near(totalArea(closed), 100, 1e-6, 'a repeated closing vertex is ignored')
end)

test('concave polygon colliders work around the 8 vertex limit and keep their settings', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    local circle = {}
    for i = 0, 11 do
        circle[#circle + 1] = 50 * math.cos(i * math.pi / 6)
        circle[#circle + 1] = 50 * math.sin(i * math.pi / 6)
    end
    local twelve = world:newConcavePolygonCollider(circle, {collision_class = 'Wall', body_type = 'static'})
    truthy(#piecesOf(twelve) >= 2, 'twelve vertices need at least two pieces')
    for _, points in ipairs(piecesOf(twelve)) do truthy(#points / 2 <= 8, 'at most 8 vertices per piece') end
    eq(twelve.collision_class, 'Wall', 'collision class')
    eq(twelve.body.body_type, 'static', 'body type')
    for name, fixture in pairs(twelve.fixtures) do
        truthy(fixture.category, 'category of ' .. name)
    end
    local fixtures = 0
    for _ in pairs(twelve.fixtures) do fixtures = fixtures + 1 end
    twelve:destroy()
    eq(twelve.body, nil, 'destroyed')
    eq(next(twelve.fixtures), nil, 'every piece released')
end)

test('concave polygon colliders reject bad input without leaving a body behind', function()
    local world = newWorld()
    local bodies = #world:getBodies()
    raises(function() world:newConcavePolygonCollider({0, 0, 20, 20, 20, 0, 0, 20}) end, 'bowtie')
    raises(function() world:newConcavePolygonCollider({0, 0, 10, 0}) end, 'two points')
    raises(function() world:newConcavePolygonCollider({0, 0, 10, 0, 5}) end, 'odd count')
    raises(function() world:newConcavePolygonCollider({0, 0, 10, 0, 20, 0}) end, 'collinear points')
    raises(function() world:newConcavePolygonCollider('x') end, 'not a table')
    raises(function() world:newConcavePolygonCollider({0, 0, 10, 0, 5, 8}, {restitutoin = 1}) end, 'unknown settings key')
    eq(#world:getBodies(), bodies, 'no bodies left behind')
end)

local function forcesOn(collider)
    local sum_x, sum_y = 0, 0
    for _, force in ipairs(collider.body.forces or {}) do
        sum_x, sum_y = sum_x + force[1], sum_y + force[2]
    end
    return sum_x, sum_y, #(collider.body.forces or {})
end

test('effectors push the colliders whose center is inside the region', function()
    local world = newWorld()
    local inside = world:newCircleCollider(50, 50, 5)
    local outside = world:newCircleCollider(500, 500, 5)
    local anchored = world:newCircleCollider(60, 60, 5, {body_type = 'static'})
    inside.body.mass = 2
    local wind = world:addEffector({shape = 'rectangle', x = 0, y = 0, w = 100, h = 100, force = {10, -4}})
    world:addEffector({shape = 'circle', x = 50, y = 50, r = 30, gravity = {0, 100}})
    world:update(1 / 60)
    local fx, fy = forcesOn(inside)
    eq(fx, 10, 'wind force x')
    eq(fy, -4 + 2 * 100, 'wind plus gravity (mass times acceleration)')
    eq(select(3, forcesOn(outside)), 0, 'outside the regions')
    eq(select(3, forcesOn(anchored)), 0, 'static bodies are skipped')

    inside.body.forces = {}
    wind:setEnabled(false)
    eq(wind:isEnabled(), false, 'isEnabled')
    world:update(1 / 60)
    eq((forcesOn(inside)), 0, 'a disabled effector does nothing')
    wind:setEnabled(true)
    inside.body.forces = {}
    wind:setGeometry({x = 200, y = 200, w = 10, h = 10})
    world:update(1 / 60)
    eq((forcesOn(inside)), 0, 'the region moved away')
    wind:destroy()
    inside.body.forces = {}
    world:update(1 / 60)
    eq(select(3, forcesOn(inside)), 1, 'a destroyed effector stops acting, the other one still acts')
    wind:destroy()
    raises(function() wind:setEnabled(true) end, 'a destroyed handle')
end)

test('effector regions can be circles, rectangles and polygons and can filter classes', function()
    local world = newWorld()
    world:addCollisionClass('Crate')
    local crate = world:newCircleCollider(10, 10, 2, {collision_class = 'Crate'})
    local ball = world:newCircleCollider(10, 10, 2)
    world:addEffector({shape = 'polygon', vertices = {0, 0, 40, 0, 0, 40}, force = {1, 0}, classes = {'Crate'}})
    world:update(1 / 60)
    eq(select(3, forcesOn(crate)), 1, 'class in the filter, inside the triangle')
    eq(select(3, forcesOn(ball)), 0, 'class outside the filter')
    crate:setPosition(35, 35)
    crate.body.forces = {}
    world:update(1 / 60)
    eq(select(3, forcesOn(crate)), 0, 'outside the triangle but inside its bounding box')
    crate:setPosition(10, 20)
    crate.body.forces = {}
    world:update(1 / 60)
    eq(select(3, forcesOn(crate)), 1, 'inside the triangle')
end)

test('drag and buoyancy effectors', function()
    local world = newWorld()
    world:setGravity(0, 100)
    local box = world:newRectangleCollider(0, 0, 10, 10)
    box.body.mass = 2
    box:setLinearVelocity(30, -10)
    world:addEffector({shape = 'rectangle', x = -50, y = -50, w = 200, h = 200, drag = 3})
    world:update(1 / 60)
    local fx, fy = forcesOn(box)
    near(fx, -3 * 2 * 30, 1e-9, 'drag opposes the velocity along x')
    near(fy, 3 * 2 * 10, 1e-9, 'drag opposes the velocity along y')

    local pool = world:addEffector({shape = 'rectangle', x = -50, y = -50, w = 200, h = 200, buoyancy = {density = 2, level = 5}})
    box.body.forces = {}
    box:setLinearVelocity(0, 0)
    world:update(1 / 60)
    local _, by = forcesOn(box)
    near(by, -(0.5 * 2 * 100 * 2) - 0, 1e-6, 'half submerged: fraction times mass times gravity times density ratio, upwards')

    pool:setGeometry({x = -50, y = -50, w = 200, h = 200})
    box.body.forces = {}
    world:setGravity(0, 0)
    world:update(1 / 60)
    eq(select(3, forcesOn(box)), 0, 'no gravity means no buoyancy and no drag at rest')
end)

test('effector definitions are validated', function()
    local world = newWorld()
    raises(function() world:addEffector({shape = 'rectangle', x = 0, y = 0, w = 1, h = 1}) end, 'no effect')
    raises(function() world:addEffector({shape = 'star', force = {1, 0}}) end, 'unknown shape')
    raises(function() world:addEffector({shape = 'circle', x = 0, y = 0, force = {1, 0}}) end, 'missing radius')
    raises(function() world:addEffector({shape = 'circle', x = 0, y = 0, r = 1, force = {1}}) end, 'bad force')
    raises(function() world:addEffector({shape = 'circle', x = 0, y = 0, r = 1, drag = 'x'}) end, 'bad drag')
    raises(function() world:addEffector({shape = 'circle', x = 0, y = 0, r = 1, buoyancy = {density = 1}}) end, 'missing level')
    raises(function() world:addEffector({shape = 'circle', x = 0, y = 0, r = 1, force = {1, 0}, forse = 1}) end, 'unknown key')
    raises(function() world:addEffector({shape = 'polygon', vertices = {0, 0, 1, 1}, force = {1, 0}}) end, 'polygon with two points')
    raises(function() world:addEffector('wind') end, 'not a table')
end)

test('queryShape validates the shape definition and releases its fixtures', function()
    local world = newWorld()
    raises(function() world:queryShape({type = 'triangle'}, 0, 0) end, 'unknown type')
    raises(function() world:queryShape({type = 'circle', radius = 'big'}, 0, 0) end, 'bad radius')
    raises(function() world:queryShape({type = 'rectangle', w = 1}, 0, 0) end, 'missing height')
    raises(function() world:queryShape('circle', 0, 0) end, 'not a table')
    world:queryShape({type = 'circle', radius = 5}, 0, 0)
    eq(#world.query_body:getFixtures(), 0, 'query fixtures are destroyed')
    world:destroy()
    truthy(world.query_world.destroyed, 'hidden world destroyed with the world')
end)

test('enter, stay and exit events on solid fixtures', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    world:update(0)

    love._fire(world, 'enter', player.fixture, coin.fixture)
    truthy(player:enter('Coin'), 'enter')
    eq(player:getEnterCollisionData('Coin').collider, coin, 'enter data')

    world:update(0)
    eq(player:enter('Coin'), nil, 'events cleared after update')
    truthy(player:stay('Coin'), 'stay')

    love._fire(world, 'exit', player.fixture, coin.fixture)
    truthy(player:exit('Coin'), 'exit')
    eq(player:getExitCollisionData('Coin').collider, coin, 'exit data')
    eq(player:stay('Coin'), nil, 'stay ends after exit')
end)

test('collision data keeps the contact geometry after the step', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    world:update(0)

    local contact = love._fire(world, 'enter', player.fixture, coin.fixture, {nx = 0, ny = -1, positions = {10, 20, 30, 40}})
    truthy(player:enter('Coin'), 'enter')
    world:update(0)
    contact.destroyed = true

    local data = player:getEnterCollisionData('Coin')
    eq(data.nx, 0, 'nx')
    eq(data.ny, -1, 'ny')
    eq(data.x1, 10, 'x1')
    eq(data.y1, 20, 'y1')
    eq(data.x2, 30, 'x2')
    eq(data.y2, 40, 'y2')
    raises(function() data.contact:getNormal() end, 'reading the destroyed contact')

    love._fire(world, 'exit', player.fixture, coin.fixture, {nx = 1, ny = 0, positions = {}})
    truthy(player:exit('Coin'), 'exit')
    eq(player:getExitCollisionData('Coin').nx, 1, 'exit nx')
end)

test('stay is tracked without polling enter and ends with exit or destroy', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin_a = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    local coin_b = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    world:update(0)

    love._fire(world, 'enter', player.fixture, coin_a.fixture)
    love._fire(world, 'enter', player.fixture, coin_b.fixture)
    truthy(player:stay('Coin'), 'stay after enter events')
    eq(#player:getStayCollisionData('Coin'), 2, 'touching coins')
    player:enter('Coin')
    player:enter('Coin')
    eq(#player:getStayCollisionData('Coin'), 2, 'polling enter does not add entries')

    love._fire(world, 'exit', player.fixture, coin_a.fixture)
    eq(#player:getStayCollisionData('Coin'), 1, 'touching coins after one exit')
    coin_b:destroy()
    eq(player:stay('Coin'), nil, 'stay after the other coin is destroyed')
end)

test('getEnters and getExits return every event of the step', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin_a = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    local coin_b = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    world:update(0)

    eq(#player:getEnters('Coin'), 0, 'no events yet')
    love._fire(world, 'enter', player.fixture, coin_a.fixture, {nx = 1, ny = 0, positions = {3, 4}})
    love._fire(world, 'enter', player.fixture, coin_b.fixture)
    local enters = player:getEnters('Coin')
    eq(#enters, 2, 'enters')
    eq(enters[1].collider, coin_a, 'first collider')
    eq(enters[1].nx, 1, 'first nx')
    eq(enters[2].collider, coin_b, 'second collider')

    love._fire(world, 'exit', player.fixture, coin_b.fixture)
    eq(#player:getExits('Coin'), 1, 'exits')
    eq(player:getExits('Coin')[1].collider, coin_b, 'exit collider')

    world:update(0)
    eq(#player:getEnters('Coin'), 0, 'cleared by the next update')
end)

test('world callbacks run after the step, once per contact', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    world:addCollisionClass('Ball')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    local ball_a = world:newCircleCollider(0, 0, 5, {collision_class = 'Ball'})
    local ball_b = world:newCircleCollider(0, 0, 5, {collision_class = 'Ball'})
    world:update(0)

    local entered, exited, balls = {}, {}, 0
    local handle = world:onEnter('Player', 'Coin', function(a, b, data)
        entered[#entered + 1] = {a, b, data.nx}
    end)
    world:onExit('Player', 'Coin', function(a, b) exited[#exited + 1] = {a, b} end)
    world:onEnter('Ball', 'Ball', function() balls = balls + 1 end)

    love._fire(world, 'enter', player.fixture, coin.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(#entered, 0, 'not called inside the step')
    world:update(0)
    eq(#entered, 1, 'called once')
    eq(entered[1][1], player, 'first collider')
    eq(entered[1][2], coin, 'second collider')
    eq(entered[1][3], 0, 'event data')
    world:update(0)
    eq(#entered, 1, 'not called again')

    love._fire(world, 'exit', player.fixture, coin.fixture)
    world:update(0)
    eq(#exited, 1, 'exit callback')

    love._fire(world, 'enter', ball_a.fixture, ball_b.fixture)
    world:update(0)
    eq(balls, 1, 'same class pair is reported once')

    handle:remove()
    love._fire(world, 'enter', player.fixture, coin.fixture)
    world:update(0)
    eq(#entered, 1, 'removed callback')
end)

test('collider callbacks run after the step for that collider and class', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Coin')
    world:addCollisionClass('Ball')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local coin = world:newCircleCollider(0, 0, 5, {collision_class = 'Coin'})
    local ball_a = world:newCircleCollider(0, 0, 5, {collision_class = 'Ball'})
    local ball_b = world:newCircleCollider(0, 0, 5, {collision_class = 'Ball'})
    world:update(0)

    local entered, exited, coin_calls, ball_calls = {}, {}, 0, {}
    local handle = player:onEnter('Coin', function(self, other, data) entered[#entered + 1] = {self, other, data.ny} end)
    player:onExit('Coin', function(self, other) exited[#exited + 1] = {self, other} end)
    coin:onEnter('Ball', function() coin_calls = coin_calls + 1 end)
    ball_a:onEnter('Ball', function(self, other) ball_calls[#ball_calls + 1] = {self, other} end)

    love._fire(world, 'enter', player.fixture, coin.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(#entered, 0, 'not called inside the step')
    world:update(0)
    eq(#entered, 1, 'called once')
    eq(entered[1][1], player, 'receiver')
    eq(entered[1][2], coin, 'other collider')
    eq(entered[1][3], 1, 'event data')
    eq(coin_calls, 0, 'the other collider has no handler for Player')
    world:update(0)
    eq(#entered, 1, 'not called again')

    love._fire(world, 'exit', player.fixture, coin.fixture)
    world:update(0)
    eq(#exited, 1, 'exit callback')

    love._fire(world, 'enter', ball_a.fixture, ball_b.fixture)
    world:update(0)
    eq(#ball_calls, 1, 'called once for a same class pair')
    eq(ball_calls[1][1], ball_a, 'same class receiver')
    eq(ball_calls[1][2], ball_b, 'same class other')

    handle:remove()
    love._fire(world, 'enter', player.fixture, coin.fixture)
    world:update(0)
    eq(#entered, 1, 'removed callback')

    player:onEnter('Coin', function() end)
    player:destroy()
    ball_a:destroy()
    coin:onEnter('Ball', function() end):remove()
    eq(#world.collision_handlers, 1, 'handlers of destroyed colliders are dropped')
    coin:destroy()
    eq(#world.collision_handlers, 0, 'no handlers left')
    eq(world.has_collision_handlers, false, 'handlers flag cleared')
end)

test('ignored class pairs get events from the sensor fixtures', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Ghost', {ignores = {'Player'}})
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local ghost = world:newCircleCollider(0, 0, 5, {collision_class = 'Ghost'})
    world:update(0)

    love._fire(world, 'enter', player.fixture, ghost.fixture)
    eq(player:enter('Ghost'), nil, 'solid fixtures of an ignored pair')

    love._fire(world, 'enter', player.sensors.main, ghost.sensors.main)
    truthy(player:enter('Ghost'), 'sensor fixtures')
end)

test('a sensor collision class passes through everything and reports events', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Zone', {sensor = true})
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local zone = world:newRectangleCollider(0, 0, 10, 10, {collision_class = 'Zone', body_type = 'static'})
    truthy(zone:isSensor(), 'zone is a sensor')
    eq(player:isSensor(), false, 'player is not a sensor')
    love._fire(world, 'enter', player.fixture, zone.fixture)
    eq(zone:enter('Player'), nil, 'solid fixtures give no event')
    love._fire(world, 'enter', player.sensors.main, zone.sensors.main)
    truthy(zone:enter('Player'), 'zone enter')
    truthy(player:enter('Zone'), 'player enter')
    love._fire(world, 'exit', player.sensors.main, zone.sensors.main)
    truthy(zone:exit('Player'), 'zone exit')
    raises(function() world:addCollisionClass('Both', {sensor = true, ignores = {'Player'}}) end, 'sensor and ignores')
end)

test('setSensor switches a collider between solid and sensor behavior', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Pickup')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local pickup = world:newCircleCollider(0, 0, 5, {collision_class = 'Pickup'})
    eq(pickup:isSensor(), false, 'solid at first')

    pickup:setSensor(true)
    truthy(pickup:isSensor(), 'sensor after setSensor(true)')
    eq(#pickup.fixture.mask, 16, 'solid fixture collides with nothing')
    love._fire(world, 'enter', player.sensors.main, pickup.sensors.main)
    truthy(pickup:enter('Player'), 'sensor pair event')
    truthy(player:enter('Pickup'), 'player side of the event')

    world:update(0)
    pickup:setSensor(false)
    eq(pickup:isSensor(), false, 'solid after setSensor(false)')
    truthy(#pickup.fixture.mask < 16, 'class mask restored')
    love._fire(world, 'enter', player.sensors.main, pickup.sensors.main)
    eq(pickup:enter('Player'), nil, 'sensor fixtures of solid classes give no event')
    love._fire(world, 'enter', player.fixture, pickup.fixture)
    truthy(pickup:enter('Player'), 'solid pair event again')
end)

test('sensor mode survives class changes and can be set from settings', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Pickup')
    local pickup = world:newCircleCollider(0, 0, 5, {collision_class = 'Pickup', sensor = true})
    truthy(pickup:isSensor(), 'sensor from settings')
    eq(#pickup.fixture.mask, 16, 'mask from settings')
    pickup:setCollisionClass('Player')
    eq(#pickup.fixture.mask, 16, 'mask after class change')
    world:addCollisionClass('Late')
    eq(#pickup.fixture.mask, 16, 'mask after a class is added')
    pickup:addShape('extra', 'CircleShape', 3)
    eq(#pickup.fixtures.extra.mask, 16, 'extra shape mask')
end)

test('the collider filter disables rejected solid contacts and hides their events', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Ghost')
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local ghost = world:newCircleCollider(0, 0, 5, {collision_class = 'Ghost'})
    local solid = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local seen = {}
    world:setColliderFilter(function(a, b)
        seen[#seen + 1] = {a, b}
        return not (a == ghost or b == ghost)
    end)
    local pre_calls = 0
    player:setPreSolve(function() pre_calls = pre_calls + 1 end)

    local contact = love._fire(world, 'enter', player.fixture, ghost.fixture)
    eq(player:enter('Ghost'), nil, 'rejected enter event')
    eq(contact:isEnabled(), false, 'rejected contact disabled on begin')
    love._fire(world, 'pre', player.fixture, ghost.fixture, contact)
    eq(pre_calls, 0, 'user preSolve skipped')
    eq(contact:isEnabled(), false, 'rejected contact disabled in pre solve')
    love._fire(world, 'exit', player.fixture, ghost.fixture, contact)
    eq(player:exit('Ghost'), nil, 'rejected exit event')
    eq(#seen, 2, 'filter called on begin and pre solve only')
    eq(seen[1][1], player, 'first collider')
    eq(seen[1][2], ghost, 'second collider')

    contact = love._fire(world, 'enter', player.fixture, solid.fixture)
    truthy(player:enter('Player'), 'accepted enter event')
    eq(contact:isEnabled(), true, 'accepted contact stays enabled')
    love._fire(world, 'pre', player.fixture, solid.fixture, contact)
    eq(pre_calls, 1, 'user preSolve runs for accepted contacts')
    love._fire(world, 'exit', player.fixture, solid.fixture, contact)
    truthy(player:exit('Player'), 'accepted exit event')
end)

test('the collider filter ignores sensor fixtures, only rejects on false and can be cleared', function()
    local world = newWorld()
    world:addCollisionClass('Player')
    world:addCollisionClass('Zone', {ignores = {'Player'}})
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})
    local zone = world:newCircleCollider(0, 0, 5, {collision_class = 'Zone'})
    local calls = 0
    world:setColliderFilter(function() calls = calls + 1 return false end)
    love._fire(world, 'enter', player.sensors.main, zone.sensors.main)
    truthy(player:enter('Zone'), 'sensor events are not filtered')
    eq(calls, 0, 'filter not called for sensor fixtures')

    world:update(0)
    world:setColliderFilter(function() end)
    local other = world:newCircleCollider(0, 0, 5)
    local contact = love._fire(world, 'enter', other.fixture, world:newCircleCollider(0, 0, 5).fixture)
    eq(contact:isEnabled(), true, 'nil result keeps the contact')

    world:setColliderFilter(nil)
    eq(world.collider_filter, nil, 'cleared')
    raises(function() world:setColliderFilter(5) end, 'not a function')
end)

test('one way decision depends on the contact normal and the relative velocity', function()
    local solid = wf.World._oneWaySolid
    eq(solid(0, -1, 0, -1, 0, 50), true, 'landing from above')
    eq(solid(0, -1, 0, -1, 0, 0), true, 'resting on top')
    eq(solid(0, -1, 0, 1, 0, -50), false, 'coming from below')
    eq(solid(0, -1, 0, -1, 0, -100), false, 'inside the platform moving up')
    eq(solid(0, -1, 1, 0, 0, 0), false, 'touching a side')
    eq(solid(1, 0, 1, 0, -30, 0), true, 'a platform that is solid to the right')
end)

test('one way classes disable contacts approached from behind', function()
    local world = newWorld()
    world:addCollisionClass('Platform', {one_way = {0, -2}})
    world:addCollisionClass('Player')
    eq(world.one_way.Platform.ny, -1, 'normalized')
    local platform = world:newRectangleCollider(0, 0, 100, 10, {collision_class = 'Platform', body_type = 'static'})
    local player = world:newCircleCollider(0, 0, 5, {collision_class = 'Player'})

    player:setLinearVelocity(0, 50)
    local contact = love._fire(world, 'pre', platform.fixture, player.fixture, {nx = 0, ny = -1, positions = {1, 2}})
    eq(contact:isEnabled(), true, 'landing keeps the contact')
    contact = love._fire(world, 'pre', player.fixture, platform.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(contact:isEnabled(), true, 'landing with the fixtures swapped')

    player:setLinearVelocity(0, -300)
    contact = love._fire(world, 'pre', platform.fixture, player.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(contact:isEnabled(), false, 'jumping from below passes through')
    contact = love._fire(world, 'pre', player.fixture, platform.fixture, {nx = 0, ny = -1, positions = {1, 2}})
    eq(contact:isEnabled(), false, 'passing through with the fixtures swapped')

    player:setPreSolve(function(_, _, c) c:setEnabled(true) end)
    contact = love._fire(world, 'pre', platform.fixture, player.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(contact:isEnabled(), true, 'a pre solve handler can override')
end)

test('conveyor classes set the tangent speed relative to the contact side', function()
    local world = newWorld()
    world:addCollisionClass('Belt', {conveyor = 100})
    world:addCollisionClass('Crate')
    local belt = world:newRectangleCollider(0, 0, 100, 10, {collision_class = 'Belt', body_type = 'static'})
    local crate = world:newRectangleCollider(0, 0, 10, 10, {collision_class = 'Crate'})
    local contact = love._fire(world, 'pre', belt.fixture, crate.fixture, {nx = 0, ny = -1, positions = {1, 2}})
    eq(contact:getTangentSpeed(), -100 / love.physics.getMeter(), 'conveyor is fixture A, speed converted from pixels to meters')
    contact = love._fire(world, 'pre', crate.fixture, belt.fixture, {nx = 0, ny = 1, positions = {1, 2}})
    eq(contact:getTangentSpeed(), -100 / love.physics.getMeter(), 'conveyor is fixture B: normal and relative velocity flip together')
    contact = love._fire(world, 'pre', crate.fixture, world:newCircleCollider(0, 0, 5, {collision_class = 'Crate'}).fixture)
    eq(contact:getTangentSpeed(), 0, 'other classes are untouched')
end)

test('one_way and conveyor options are validated', function()
    local world = newWorld()
    raises(function() world:addCollisionClass('A', {one_way = {0, 0}}) end, 'zero normal')
    raises(function() world:addCollisionClass('B', {one_way = 'up'}) end, 'not a table')
    raises(function() world:addCollisionClass('C', {conveyor = 'fast'}) end, 'not a number')
    eq(world.collision_classes.A, nil, 'failed class not added')
    world:addCollisionClass('Ok', {one_way = {0, -1}, conveyor = 5})
    truthy(world.collision_classes.Ok, 'valid class added')
end)

test('pre and post solve callbacks are stored', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    local pre, post = function() end, function() end
    collider:setPreSolve(pre)
    collider:setPostSolve(post)
    eq(collider.preSolve, pre)
    eq(collider.postSolve, post)
end)

test('addShape and removeShape manage extra fixtures', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    collider:addShape('extra', 'CircleShape', 3)
    truthy(collider.shapes.extra and collider.fixtures.extra and collider.sensors.extra, 'extra shape')
    raises(function() collider:addShape('extra', 'CircleShape', 3) end, 'duplicate shape name')
    collider:removeShape('extra')
    eq(collider.shapes.extra, nil, 'shape removed')
    eq(#collider.body:getFixtures(), 2, 'fixtures left on the body')
end)

test('object accessors', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    local object = {}
    collider:setObject(object)
    eq(collider:getObject(), object)
end)

test('joints can be added and removed', function()
    local world = newWorld()
    local collider = world:newCircleCollider(10, 10, 5)
    local joint = world:addJoint('MouseJoint', collider, 20, 20)
    eq(#world:getJoints(), 1, 'joints after add')
    world:removeJoint(joint)
    eq(#world:getJoints(), 0, 'joints after remove')
end)

test('draw uses 0-1 colors and maps the 0-255 alpha argument', function()
    local world = newWorld()
    world:newRectangleCollider(0, 0, 10, 10)
    love._colors = {}
    world:draw()
    for _, color in ipairs(love._colors) do
        for _, component in ipairs(color) do
            truthy(component >= 0 and component <= 1, 'color component ' .. tostring(component))
        end
    end
    love._colors = {}
    world:draw(128)
    local drawn = #love._colors - 1
    truthy(drawn >= 1, 'draw colors')
    for i = 1, drawn do
        local alpha = love._colors[i][4]
        truthy(math.abs(alpha - 128 / 255) < 1e-9, 'alpha ' .. tostring(alpha))
    end
end)

local function drawCalls(world, options)
    love.graphics.calls = {}
    world:draw(options)
    return love.graphics.calls
end

local function callsNamed(calls, name)
    local out = {}
    for _, call in ipairs(calls) do
        if call.name == name then out[#out + 1] = call end
    end
    return out
end

test('draw options: alpha, line width and restoring the previous line width', function()
    local world = newWorld()
    world:newRectangleCollider(0, 0, 10, 10)
    love.graphics.setLineWidth(5)
    local calls = drawCalls(world, {alpha = 51})
    local widths = callsNamed(calls, 'setLineWidth')
    eq(widths[1][1], 1, 'default line width while drawing')
    eq(widths[#widths][1], 5, 'previous line width restored')
    for _, color in ipairs(callsNamed(calls, 'setColor')) do
        if #color == 4 and color[4] ~= 1 then eq(color[4], 51 / 255, 'alpha from the options table') end
    end
    calls = drawCalls(world, {line_width = 3})
    eq(callsNamed(calls, 'setLineWidth')[1][1], 3, 'custom line width')
    eq(love.graphics.getLineWidth(), 5, 'restored after the custom width')
    love.graphics.setLineWidth(1)
    raises(function() world:draw({alhpa = 1}) end, 'unknown option')
end)

test('draw draws each collider once and colors it by class', function()
    local world = newWorld()
    world:addCollisionClass('Wall')
    world:newRectangleCollider(0, 0, 10, 10, {collision_class = 'Wall'})
    world:newRectangleCollider(50, 0, 10, 10)
    local calls = drawCalls(world, {class_colors = {Wall = {1, 0, 0}}})
    eq(#callsNamed(calls, 'polygon'), 2, 'one polygon per collider, not per fixture')
    local wall_color_before_polygon = false
    for i, call in ipairs(calls) do
        if call.name == 'setColor' and call[1] == 1 and call[2] == 0 and call[3] == 0 then
            wall_color_before_polygon = calls[i + 1].name == 'polygon'
        end
    end
    truthy(wall_color_before_polygon, 'the class color is set right before its shape')
end)

test('draw shows contacts, bounding boxes, velocities and sleeping bodies', function()
    local world = newWorld()
    local box = world:newRectangleCollider(0, 0, 10, 10)
    box:setLinearVelocity(40, 0)
    local sleeper = world:newRectangleCollider(100, 0, 10, 10)
    sleeper.body.asleep = true
    local ground = world:newRectangleCollider(0, 50, 10, 10, {body_type = 'static'})
    world.box2d_world.contacts = {
        love._newContact({nx = 0, ny = 1, positions = {3, 4, 5, 6}}),
        love._newContact({nx = 0, ny = 1, positions = {9, 9}, touching = false}),
    }

    local plain = drawCalls(world)
    eq(#callsNamed(plain, 'rectangle'), 0, 'no bounding boxes by default')
    eq(#callsNamed(plain, 'line'), 0, 'no velocity or contact lines by default')

    local calls = drawCalls(world, {aabb = true})
    eq(#callsNamed(calls, 'rectangle'), 3, 'one box per solid fixture')
    local x1, y1, x2, y2 = box.fixture:getBoundingBox()
    local found = false
    for _, call in ipairs(callsNamed(calls, 'rectangle')) do
        if call[2] == x1 and call[3] == y1 and call[4] == x2 - x1 and call[5] == y2 - y1 then found = true end
    end
    truthy(found, 'bounding box of the box collider')

    calls = drawCalls(world, {velocities = true})
    local lines = callsNamed(calls, 'line')
    eq(#lines, 1, 'only the moving body gets a velocity line')
    eq(lines[1][1], 5, 'line starts at the body center x')
    eq(lines[1][3], 5 + 40 * 0.25, 'line ends one quarter second ahead')

    calls = drawCalls(world, {contacts = true})
    eq(#callsNamed(calls, 'circle'), 2, 'two contact points of the touching contact')
    eq(#callsNamed(calls, 'line'), 1, 'one normal line')

    calls = drawCalls(world, {sleeping = true, alpha = 255})
    local awake_alpha, asleep_alpha
    for i, call in ipairs(calls) do
        if call.name == 'polygon' then
            local color = calls[i - 1]
            if call[1] == 'line' and not asleep_alpha and color.name == 'setColor' and color[4] < 1 then asleep_alpha = color[4] end
            if color.name == 'setColor' and color[4] == 1 then awake_alpha = 1 end
        end
    end
    truthy(awake_alpha == 1, 'awake bodies at full alpha')
    truthy(asleep_alpha and asleep_alpha < 1, 'sleeping bodies are dimmer')
end)

test('a collider with its own draw replaces the debug shape and draw order sorts colliders', function()
    local world = newWorld()
    local function mark(name)
        return function(_, alpha) love.graphics.calls[#love.graphics.calls + 1] = {name = name, alpha = alpha} end
    end
    local first = world:newRectangleCollider(0, 0, 10, 10)
    local second = world:newRectangleCollider(20, 0, 10, 10)
    local plain = world:newRectangleCollider(40, 0, 10, 10)
    first.draw = mark('first')
    second.draw = mark('second')
    eq(first:getDrawOrder(), 0, 'default draw order')
    plain:setDrawOrder(1)
    first:setDrawOrder(2)
    second:setDrawOrder(-1)
    eq(first:getDrawOrder(), 2, 'draw order')

    local calls = drawCalls(world, 128)
    local sequence = {}
    for _, call in ipairs(calls) do
        if call.name == 'first' or call.name == 'second' or call.name == 'polygon' then sequence[#sequence + 1] = call.name end
    end
    eq(table.concat(sequence, ','), 'second,polygon,first', 'custom draws and debug shapes in draw order')
    eq(callsNamed(calls, 'first')[1].alpha, 128, 'alpha passed to the draw hook')
    eq(love.graphics.getLineWidth(), 1, 'line width after the hook')
end)

test('a failing constructor leaves no body behind', function()
    local world = newWorld()
    raises(function() world:newChainCollider({10, 10, 10, 20, 20, 20}, nil) end, 'bad chain')
    eq(#world.box2d_world.bodies, 0, 'bodies after failure')
    world:update(0)
end)

test('chain collider takes vertices and loop', function()
    local world = newWorld()
    local collider = world:newChainCollider({10, 10, 10, 20, 20, 20}, true)
    eq(collider.type, 'Chain')
    eq(collider.shape.loop, true, 'loop')
    eq(#collider.shape.points, 6, 'point count')
end)

test('draw runs with every shape kind, a joint and query debug', function()
    local world = newWorld()
    world:newRectangleCollider(30, 30, 10, 10)
    world:newLineCollider(0, 0, 10, 10)
    world:addJoint('MouseJoint', world:newPolygonCollider({0, 0, 10, 0, 5, 10}), 1, 1)
    world:setQueryDebugDrawing(true)
    world:queryCircleArea(30, 30, 5)
    world:queryRectangleArea(0, 0, 5, 5)
    world:queryPolygonArea({0, 0, 10, 0, 5, 10})
    world:queryLine(0, 0, 10, 10)
    world:newCircleCollider(10, 10, 5)
    world:draw()
    world:draw(128)
end)

test('destroying a collider during the step is deferred until the step ends', function()
    local world = newWorld()
    local victim = world:newCircleCollider(0, 0, 5)
    local survivor = world:newCircleCollider(10, 10, 5)
    world.box2d_world.step_hook = function()
        victim:destroy()
        victim:destroy()
    end
    world:update(0)
    eq(#world.box2d_world.bodies, 1, 'bodies after the step')
    eq(victim.body, nil, 'victim body')
    truthy(survivor.body, 'survivor body')
    world.box2d_world.step_hook = nil
    victim:destroy()
    eq(#world.box2d_world.bodies, 1, 'destroying twice is harmless')
end)

test('destroy releases colliders and the world', function()
    local world = newWorld()
    local collider = world:newCircleCollider(0, 0, 5)
    local box2d_world = world.box2d_world
    collider:destroy()
    eq(#box2d_world.bodies, 0, 'bodies after collider destroy')
    world:newCircleCollider(0, 0, 5)
    world:destroy()
    eq(world.box2d_world, nil, 'box2d world cleared')
    truthy(box2d_world.destroyed, 'box2d world destroyed')
end)

print(string.format('%d tests, %d failed', count, failures))
os.exit(failures == 0 and 0 or 1)
