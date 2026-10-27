-- Run from the repository root: lua tests/run.lua
-- Works on luajit, lua5.1, lua5.4 and lua5.5.
package.path = './?.lua;./?/init.lua;' .. package.path

love = require('tests.mock_love')()

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
    for _, name in ipairs(names.collider) do
        if name ~= 'preSolve' and name ~= 'postSolve' then
            eq(rawget(wf.Collider, name), nil, 'Collider.' .. name)
        end
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
