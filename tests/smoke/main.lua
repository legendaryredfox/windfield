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
    ray_world:destroy()

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
