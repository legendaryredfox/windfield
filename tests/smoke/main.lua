-- Real LÖVE 11.5 check of the flows the mock covers, plus a screenshot of the
-- debug drawing. Run with: sh tests/smoke/run.sh
love.setDeprecationOutput(true)
love.filesystem.setIdentity('windfield-smoke')

local unpack = table.unpack or unpack
local wf = require('windfield')

local failed = 0
local frame = 0
local world, ground, player, ghost
local late_world, early_collider
local destroy_world, victim
local seen = {}
local callbacks = {enter = 0, exit = 0}

local function check(name, ok, detail)
    if not ok then failed = failed + 1 end
    print((ok and 'ok   ' or 'FAIL ') .. name .. (detail and (': ' .. tostring(detail)) or ''))
end

function love.load()
    world = wf.newWorld(0, 500, true)
    world:addCollisionClass('Ground')
    world:addCollisionClass('Player')
    world:addCollisionClass('Ghost', {ignores = {'Player'}})
    world:setQueryDebugDrawing(true)

    world:onEnter('Player', 'Ground', function() callbacks.enter = callbacks.enter + 1 end)
    world:onExit('Player', 'Ghost', function() callbacks.exit = callbacks.exit + 1 end)

    ground = world:newRectangleCollider(50, 300, 300, 20, {collision_class = 'Ground', body_type = 'static'})
    ghost = world:newRectangleCollider(180, 220, 40, 40, {collision_class = 'Ghost', body_type = 'static'})
    player = world:newCircleCollider(200, 100, 10, {collision_class = 'Player'})

    check('polygon collider', pcall(world.newPolygonCollider, world, {20, 20, 60, 20, 40, 50}))
    check('line collider', pcall(world.newLineCollider, world, 0, 0, 40, 40))
    check('bsg rectangle collider', pcall(world.newBSGRectangleCollider, world, 300, 50, 40, 40, 8))
    local chain_ok, chain_err = pcall(world.newChainCollider, world, {10, 10, 10, 20, 20, 20}, true)
    check('chain collider', chain_ok, chain_err)

    local anchor = world:newCircleCollider(320, 100, 5, {body_type = 'static'})
    local joint_ok, joint_err = pcall(world.addJoint, world, 'MouseJoint', anchor, 320, 100)
    check('mouse joint', joint_ok, joint_err)

    local found = world:queryRectangleArea(40, 290, 320, 40, {'Ground'})
    check('queryRectangleArea', #found == 1 and found[1] == ground, #found)
    found = world:queryPolygonArea({40, 280, 360, 280, 360, 340, 40, 340}, {'Ground'})
    check('queryPolygonArea', #found == 1 and found[1] == ground, #found)
    found = world:queryLine(200, 0, 200, 400, {'Ground'})
    check('queryLine', #found == 1 and found[1] == ground, #found)

    local circle_ok, circle_err = pcall(function()
        assert(world:queryCircleArea(205, 100, 10, {'Player'})[1] == player, 'circle query')
        assert(world:queryRectangleArea(190, 90, 20, 20, {'Player'})[1] == player, 'rectangle query')
        assert(world:queryPolygonArea({180, 80, 220, 80, 200, 120}, {'Player'})[1] == player, 'polygon query')
        assert(#world:queryCircleArea(300, 300, 5, {'Player'}) == 0, 'miss')
    end)
    check('area queries over a circle collider', circle_ok, circle_err)

    local proxy_names = require('fixtures.proxy_keys')
    local sample = world:newRectangleCollider(10, 10, 20, 20)
    local missing = {}
    for _, name in ipairs(proxy_names.collider) do
        if type(sample[name]) ~= 'function' then missing[#missing + 1] = name end
    end
    for _, name in ipairs(proxy_names.world) do
        if type(world[name]) ~= 'function' then missing[#missing + 1] = 'world.' .. name end
    end
    check('proxied methods still resolve', #missing == 0, table.concat(missing, ', '))
    local px, py = sample:getPosition()
    sample:setLinearVelocity(3, 4)
    local vx, vy = sample:getLinearVelocity()
    sample:setSensor(true)
    local sensor_on = sample:isSensor()
    sample:setSensor(false)
    check('proxied calls reach the right object', px == 20 and py == 20 and vx == 3 and vy == 4 and sensor_on and sample:getDensity() > 0)
    check('collider keeps its own fields', sample.type == 'Rectangle' and sample.body ~= nil and sample.shape:type() == 'PolygonShape')
    sample:destroy()

    local tagged = {}
    local configured = world:newRectangleCollider(500, 50, 20, 20, {
        bullet = true, fixed_rotation = true, gravity_scale = 0.5, linear_damping = 1, angular_damping = 2,
        sleeping_allowed = false, angle = 1.5, restitution = 0.3, friction = 0.4, density = 2, object = tagged,
    })
    local fixture = configured.fixture
    check('settings keys reach Box2D',
        configured:isBullet() and configured:isFixedRotation() and configured:getGravityScale() == 0.5
        and configured:getLinearDamping() == 1 and configured:getAngularDamping() == 2
        and not configured:isSleepingAllowed() and math.abs(configured:getAngle() - 1.5) < 1e-6
        and math.abs(fixture:getRestitution() - 0.3) < 1e-6 and math.abs(fixture:getFriction() - 0.4) < 1e-6
        and fixture:getDensity() == 2 and configured:getObject() == tagged)
    check('density settings update the body mass', configured:getMass() > 0)
    check('unknown settings key raises', not pcall(world.newCircleCollider, world, 0, 0, 5, {restitutoin = 1}))
    configured:destroy()

    local step_world = wf.newWorld(0, 500, true)
    local faller = step_world:newCircleCollider(0, 0, 5)
    faller:setInterpolated(true)
    check('step runs two fixed updates for 1/30', step_world:step(1 / 30) == 2)
    local y_before = select(2, faller:getPosition())
    check('step runs one update and keeps the remainder', step_world:step(1 / 60 + 1 / 120) == 1 and math.abs(step_world:getAlpha() - 0.5) < 1e-6)
    local y_now = select(2, faller:getPosition())
    local y_render = select(2, faller:getRenderPosition())
    check('render position sits between the last two steps', y_render > y_before and y_render < y_now, y_before .. ' ' .. y_render .. ' ' .. y_now)
    step_world:destroy()

    local function dropPlayer(configure)
        local w = wf.newWorld(0, 0, true)
        w:addCollisionClass('Player')
        w:addCollisionClass('Zone', {sensor = true})
        w:addCollisionClass('Pickup')
        local target = configure(w)
        local player = w:newCircleCollider(100, 0, 8, {collision_class = 'Player'})
        player:setLinearVelocity(0, 200)
        local enters, stays, exits = 0, 0, 0
        for _ = 1, 120 do
            w:update(1 / 60)
            if target:enter('Player') then enters = enters + 1 end
            if target:stay('Player') then stays = stays + 1 end
            if target:exit('Player') then exits = exits + 1 end
        end
        local _, y = player:getPosition()
        w:destroy()
        return enters, stays, exits, y
    end
    local enters, stays, exits, y = dropPlayer(function(w)
        return w:newRectangleCollider(0, 100, 200, 20, {collision_class = 'Zone', body_type = 'static'})
    end)
    check('sensor class: enter, stay, exit and passes through', enters == 1 and stays > 0 and exits == 1 and y > 130, enters .. ' ' .. stays .. ' ' .. exits .. ' ' .. y)
    enters, stays, exits, y = dropPlayer(function(w)
        local pickup = w:newRectangleCollider(0, 100, 200, 20, {collision_class = 'Pickup', body_type = 'static'})
        pickup:setSensor(true)
        return pickup
    end)
    check('setSensor(true) at runtime: events and passes through', enters == 1 and stays > 0 and exits == 1 and y > 130, enters .. ' ' .. stays .. ' ' .. exits .. ' ' .. y)
    enters, stays, exits, y = dropPlayer(function(w)
        local pickup = w:newRectangleCollider(0, 100, 200, 20, {collision_class = 'Pickup', body_type = 'static'})
        pickup:setSensor(true)
        pickup:setSensor(false)
        return pickup
    end)
    check('setSensor(false) makes the collider solid again', y < 100 and enters >= 1, enters .. ' ' .. y)

    local ray_world = wf.newWorld(0, 0, true)
    ray_world:addCollisionClass('Wall')
    ray_world:addCollisionClass('Zone', {sensor = true})
    local rect = ray_world:newRectangleCollider(100, -10, 20, 20, {collision_class = 'Wall', body_type = 'static'})
    local ball = ray_world:newCircleCollider(200, 0, 10, {body_type = 'static'})
    local zone = ray_world:newRectangleCollider(50, -10, 10, 20, {collision_class = 'Zone', body_type = 'static'})
    ray_world:update(0)
    local hits = ray_world:raycast(0, 0, 300, 0)
    check('raycast: every collider, sorted by distance', #hits == 3 and hits[1].collider == zone and hits[2].collider == rect
        and hits[3].collider == ball, #hits)
    check('raycast: hit point and normal', math.abs(hits[2].x - 100) < 1e-3 and math.abs(hits[2].nx + 1) < 1e-3 and math.abs(hits[2].fraction - 100 / 300) < 1e-3)
    local closest = ray_world:raycast(0, 0, 300, 0, nil, 'closest')
    check('raycast: closest', closest and closest.collider == zone)
    local filtered = ray_world:raycast(0, 0, 300, 0, {'All', except = {'Zone', 'Wall'}}, 'closest')
    check('raycast: class filter skips nearer colliders', filtered and filtered.collider == ball)
    local point_hits = ray_world:queryPoint(110, 0)
    check('queryPoint: rectangle', #point_hits == 1 and point_hits[1] == rect, #point_hits)
    check('queryPoint: circle inside and outside', ray_world:getColliderAt(205, 5) == ball and ray_world:getColliderAt(209, 9) == nil)
    check('queryPoint: class filter', #ray_world:queryPoint(110, 0, {'Zone'}) == 0 and ray_world:getColliderAt(55, 0, {'Zone'}) == zone)
    ray_world:destroy()

    local filter_world = wf.newWorld(0, 300, true)
    filter_world:addCollisionClass('Wall')
    filter_world:addCollisionClass('Solid')
    filter_world:addCollisionClass('Ghost')
    filter_world:newRectangleCollider(0, 100, 300, 20, {collision_class = 'Wall', body_type = 'static'})
    local solid_ball = filter_world:newCircleCollider(60, 0, 8, {collision_class = 'Solid'})
    local ghost_ball = filter_world:newCircleCollider(200, 0, 8, {collision_class = 'Ghost'})
    filter_world:setColliderFilter(function(a, b)
        return a.collision_class ~= 'Ghost' and b.collision_class ~= 'Ghost'
    end)
    local solid_enters, ghost_enters, ghost_exits = 0, 0, 0
    for _ = 1, 120 do
        filter_world:update(1 / 60)
        if solid_ball:enter('Wall') then solid_enters = solid_enters + 1 end
        if ghost_ball:enter('Wall') then ghost_enters = ghost_enters + 1 end
        if ghost_ball:exit('Wall') then ghost_exits = ghost_exits + 1 end
    end
    local _, solid_y = solid_ball:getPosition()
    local _, ghost_y = ghost_ball:getPosition()
    check('collider filter: accepted contact lands with an enter event', solid_y < 100 and solid_enters >= 1, solid_y .. ' ' .. solid_enters)
    check('collider filter: rejected contact passes through with no events', ghost_y > 130 and ghost_enters == 0 and ghost_exits == 0, ghost_y .. ' ' .. ghost_enters .. ' ' .. ghost_exits)
    filter_world:destroy()

    local draw_world = wf.newWorld(0, 300, true)
    draw_world:addCollisionClass('Wall')
    draw_world:newRectangleCollider(20, 150, 160, 20, {collision_class = 'Wall', body_type = 'static'})
    draw_world:newRectangleCollider(60, 110, 30, 40)
    local mover = draw_world:newCircleCollider(40, 40, 10, {body_type = 'kinematic'})
    mover:setLinearVelocity(20, 0)
    for _ = 1, 150 do draw_world:update(1 / 60) end
    local function render(name, options)
        local canvas = love.graphics.newCanvas(200, 200)
        love.graphics.setCanvas(canvas)
        love.graphics.clear(0, 0, 0, 0)
        draw_world:draw(options)
        love.graphics.setCanvas()
        local data = canvas:newImageData()
        data:encode('png', 'draw_' .. name .. '.png')
        return data
    end
    local function count(data, predicate)
        local n = 0
        for y = 0, data:getHeight() - 1 do
            for x = 0, data:getWidth() - 1 do
                local r, g, b, a = data:getPixel(x, y)
                if predicate(r, g, b, a) then n = n + 1 end
            end
        end
        return n
    end
    local function covered(r, g, b, a) return a > 0.05 end
    local plain = render('plain')
    local thick = render('line_width', {line_width = 6})
    check('draw option line_width draws thicker lines', count(thick, covered) > 2 * count(plain, covered), count(plain, covered) .. ' ' .. count(thick, covered))
    check('draw option class_colors colors the wall', count(render('class_colors', {class_colors = {Wall = {0, 1, 1}}}),
        function(r, g, b, a) return a > 0.3 and g > 2.5 * r and b > 2.5 * r end) > 20)
    check('draw option aabb adds gray boxes', count(render('aabb', {aabb = true}),
        function(r, g, b, a) return math.abs(r - 0.5) < 0.06 and math.abs(g - 0.5) < 0.06 and math.abs(b - 0.5) < 0.06 and a > 0.9 end) > 20)
    check('draw option velocities adds a green line', count(render('velocities', {velocities = true}),
        function(r, g, b, a) return a > 0.3 and g > 2.5 * r and g > 2.5 * b end) > 5)
    check('draw option contacts adds red marks', count(render('contacts', {contacts = true}),
        function(r, g, b, a) return r > 0.8 and g < 0.35 and b < 0.35 and a > 0.9 end) > 5)
    local function dim(r, g, b, a) return a > 0.25 and a < 0.55 end
    local dim_with, dim_without = count(render('sleeping', {sleeping = true}), dim), count(plain, dim)
    check('draw option sleeping dims sleeping bodies', dim_with > dim_without + 20, dim_without .. ' ' .. dim_with)
    check('draw restores the line width', love.graphics.getLineWidth() == 1)
    local function pixelAt(data, x, y)
        local r, g, b = data:getPixel(x, y)
        return r > 0.9, g > 0.9, b > 0.9
    end
    local magenta = draw_world:newRectangleCollider(120, 20, 20, 20, {body_type = 'static'})
    local yellow = draw_world:newRectangleCollider(130, 30, 20, 20, {body_type = 'static'})
    magenta.draw = function() love.graphics.setColor(1, 0, 1) love.graphics.rectangle('fill', 120, 20, 20, 20) end
    yellow.draw = function() love.graphics.setColor(1, 1, 0) love.graphics.rectangle('fill', 130, 30, 20, 20) end
    yellow:setDrawOrder(1)
    local yr, yg, yb = pixelAt(render('order_yellow_top'), 135, 35)
    check('custom draw hook: the higher draw order is drawn on top', yr and yg and not yb)
    yellow:setDrawOrder(-1)
    local mr, mg, mb = pixelAt(render('order_magenta_top'), 135, 35)
    check('custom draw hook: changing the draw order changes the stacking', mr and not mg and mb)
    local tr, tg, tb = pixelAt(render('hook_replaces_shape'), 121, 21)
    check('custom draw hook replaces the debug shape', tr and not tg and tb)

    local cb_world = wf.newWorld(0, 300, true)
    cb_world:addCollisionClass('Wall')
    cb_world:addCollisionClass('Ball')
    cb_world:newRectangleCollider(0, 100, 300, 20, {collision_class = 'Wall', body_type = 'static'})
    local cb_ball = cb_world:newCircleCollider(60, 0, 8, {collision_class = 'Ball'})
    local cb_calls = {}
    cb_ball:onEnter('Wall', function(self, other, data) cb_calls[#cb_calls + 1] = {self, other, data} end)
    for _ = 1, 120 do cb_world:update(1 / 60) end
    check('collider:onEnter runs once with the receiver, the other collider and the data',
        #cb_calls == 1 and cb_calls[1][1] == cb_ball and cb_calls[1][2].collision_class == 'Wall' and type(cb_calls[1][3].ny) == 'number', #cb_calls)
    cb_world:destroy()
    draw_world:destroy()

    local rules_world = wf.newWorld(0, 300, true)
    rules_world:addCollisionClass('Platform', {one_way = {0, -1}})
    rules_world:addCollisionClass('Belt', {conveyor = 100})
    rules_world:addCollisionClass('Ball')
    rules_world:newRectangleCollider(0, 100, 150, 10, {collision_class = 'Platform', body_type = 'static'})
    local lander = rules_world:newCircleCollider(40, 0, 8, {collision_class = 'Ball'})
    local jumper = rules_world:newCircleCollider(110, 200, 8, {collision_class = 'Ball'})
    jumper:setLinearVelocity(0, -400)
    local early_crate = rules_world:newRectangleCollider(300, 60, 20, 20, {friction = 1})
    rules_world:newRectangleCollider(200, 100, 2000, 10, {collision_class = 'Belt', body_type = 'static'})
    local late_crate = rules_world:newRectangleCollider(500, 60, 20, 20, {friction = 1})
    local jumper_y_at_30
    for frame = 1, 120 do
        rules_world:update(1 / 60)
        if frame == 30 then jumper_y_at_30 = select(2, jumper:getPosition()) end
    end
    check('one way: a ball dropped from above lands on the platform', select(2, lander:getPosition()) < 100, select(2, lander:getPosition()))
    check('one way: a ball thrown up from below passes through', jumper_y_at_30 < 90, jumper_y_at_30)
    local early_dx = early_crate:getPosition() - 310
    local late_dx = late_crate:getPosition() - 510
    check('conveyor: crate created before the belt moves with the belt', early_dx > 30 and early_dx < 200, early_dx)
    check('conveyor: crate created after the belt moves with the belt', late_dx > 30 and late_dx < 200, late_dx)
    rules_world:destroy()

    late_world = wf.newWorld(0, 500, true)
    late_world:addCollisionClass('X')
    early_collider = late_world:newCircleCollider(100, 0, 5, {collision_class = 'X'})
    late_world:addCollisionClass('Y', {ignores = {'X'}})
    late_world:newRectangleCollider(50, 100, 100, 10, {collision_class = 'Y', body_type = 'static'})

    local failed_cases = {}
    for _, case in ipairs(require('fixtures.query_cases')) do
        local name, shape, query, expected = case[1], case[2], case[3], case[4]
        local case_world = wf.newWorld(0, 0, true)
        if shape.kind == 'rectangle' then
            case_world:newRectangleCollider(shape[1], shape[2], shape[3], shape[4], {body_type = 'static'})
        else
            case_world:newCircleCollider(shape[1], shape[2], shape[3], {body_type = 'static'})
        end
        local found
        if query.kind == 'circle' then
            found = case_world:queryCircleArea(query[1], query[2], query[3])
        elseif query.kind == 'rectangle' then
            found = case_world:queryRectangleArea(query[1], query[2], query[3], query[4])
        elseif query.kind == 'polygon' then
            found = case_world:queryPolygonArea({unpack(query)})
        else
            found = case_world:queryLine(query[1], query[2], query[3], query[4])
        end
        if (#found > 0) ~= expected then failed_cases[#failed_cases + 1] = name end
        case_world:destroy()
    end
    check('area query rules', #failed_cases == 0, table.concat(failed_cases, '; '))

    destroy_world = wf.newWorld(0, 500, true)
    destroy_world:addCollisionClass('Hitter')
    destroy_world:addCollisionClass('Victim')
    local hitter = destroy_world:newRectangleCollider(50, 100, 100, 10, {collision_class = 'Hitter', body_type = 'static'})
    victim = destroy_world:newCircleCollider(100, 50, 5, {collision_class = 'Victim'})
    hitter:setPreSolve(function(_, other) other:destroy() end)

    check('Ghost mask lists Player', #world.masks.Ghost.masks > 0)
end

function love.update(dt)
    frame = frame + 1
    world:update(1 / 60)
    late_world:update(1 / 60)
    destroy_world:update(1 / 60)
    if frame == 150 then world:queryRectangleArea(40, 290, 320, 40, {'Ground'}) end
    if #player:getEnters('Ground') > 0 then seen.ground_enters = (seen.ground_enters or 0) + 1 end
    if player:enter('Ground') then seen.ground_enter = true end
    if player:enter('Ghost') then seen.ghost_enter = true end
    if player:exit('Ghost') then seen.ghost_exit = true end
end

function love.draw()
    world:draw()
    if frame == 150 then
        world:draw(64)
        love.graphics.captureScreenshot(function(data)
            data:encode('png', 'smoke.png')
            print('screenshot: ' .. love.filesystem.getSaveDirectory() .. '/smoke.png')
        end)
    end
    if frame == 152 then
        check('solid enter event', seen.ground_enter)
        check('sensor enter event (ignored pair)', seen.ghost_enter)
        check('sensor exit event (ignored pair)', seen.ghost_exit)
        check('stay after enter', player:stay('Ground'))
        check('collider destroyed from preSolve is gone after the step', victim.body == nil and #destroy_world:getBodies() == 1, #destroy_world:getBodies())
        check('world:onEnter callback', callbacks.enter == 1, callbacks.enter)
        check('world:onExit callback', callbacks.exit == 1, callbacks.exit)
        check('getEnters reports the ground contact', (seen.ground_enters or 0) >= 1, seen.ground_enters)
        local data = player:getEnterCollisionData('Ground')
        check('contact geometry readable after the step', data and type(data.nx) == 'number' and type(data.ny) == 'number' and type(data.x1) == 'number', data and data.nx)
        check('collider created before a class passes through an ignoring class', select(2, early_collider:getPosition()) > 150)
        love.event.quit(failed == 0 and 0 or 1)
    end
end
