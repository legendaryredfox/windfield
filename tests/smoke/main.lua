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

    local shape_world = wf.newWorld(0, 0, true)
    local square = shape_world:newRectangleCollider(100, 100, 100, 100, {body_type = 'static'})
    local disc = shape_world:newCircleCollider(500, 500, 10, {body_type = 'static'})
    local zigzag = shape_world:newChainCollider({0, 300, 100, 300, 100, 400, 200, 400, 200, 300}, false, {body_type = 'static'})
    shape_world:update(0)
    local circle = function(r) return {type = 'circle', radius = r} end
    local box = function(w, h, angle) return {type = 'rectangle', w = w, h = h, angle = angle} end
    local cases = {
        {'circle partly overlapping the square', circle(20), 100, 150, square, true},
        {'circle inside the square', circle(5), 150, 150, square, true},
        {'circle containing the square', circle(500), 150, 150, square, true},
        {'circle tangent to the square', circle(20), 80, 150, square, true},
        {'circle 2 px away from the square', circle(20), 78, 150, square, false},
        {'rectangle touching the square edge', box(100, 50), 50, 150, square, true},
        {'rectangle 3 px away from the square', box(100, 50), 47, 150, square, false},
        {'edge crossing the square', {type = 'edge', x1 = -50, y1 = 0, x2 = 50, y2 = 0}, 100, 150, square, true},
        {'edge inside the square', {type = 'edge', x1 = -10, y1 = 0, x2 = 10, y2 = 0}, 150, 150, square, true},
        {'edge beside the square', {type = 'edge', x1 = -10, y1 = 0, x2 = 10, y2 = 0}, 50, 150, square, false},
        {'long thin rectangle reaches the square only when rotated', box(100, 4), 70, 70, square, false},
        {'rotated rectangle reaches the square', box(100, 4, math.pi / 4), 70, 70, square, true},
        {'polygon covering the square', {type = 'polygon', vertices = {-60, -60, 60, -60, 60, 60, -60, 60}}, 150, 150, square, true},
        {'small rectangle inside the circle collider', box(4, 4), 500, 500, disc, true},
        {'rectangle whose corner is outside the circle collider', box(20, 20), 530, 530, disc, false},
        {'circle on the third chain segment', circle(5), 150, 400, zigzag, true},
        {'circle inside the chain bounding box but far from every segment', circle(5), 50, 350, zigzag, false},
    }
    for _, case in ipairs(cases) do
        local name, shape_def, x, y, target, expected = unpack(case)
        local hits = shape_world:queryShape(shape_def, x, y)
        local found = false
        for _, hit in ipairs(hits) do if hit == target then found = true end end
        check('queryShape: ' .. name, found == expected, tostring(found))
    end
    shape_world:destroy()

    local cast_world = wf.newWorld(0, 0, true)
    cast_world:addCollisionClass('Wall')
    local wall = cast_world:newRectangleCollider(300, 100, 20, 100, {collision_class = 'Wall', body_type = 'static'})
    local round = cast_world:newCircleCollider(300, 600, 30, {body_type = 'static'})
    local corner = cast_world:newRectangleCollider(1100, 100, 50, 50, {body_type = 'static'})
    local rail = cast_world:newChainCollider({1500, 300, 1600, 300, 1600, 400, 1700, 400, 1700, 300}, false, {body_type = 'static'})
    cast_world:update(0)
    local function castCheck(name, hit, collider, fraction, nx, ny, tolerance)
        local ok = hit and hit.collider == collider and math.abs(hit.fraction - fraction) < tolerance
            and (nx == nil or (math.abs(hit.nx - nx) < 0.05 and math.abs(hit.ny - ny) < 0.05))
        check('shapeCast: ' .. name, ok, hit and (hit.fraction .. ' ' .. hit.nx .. ' ' .. hit.ny) or 'no hit')
    end
    castCheck('circle toward a wall', cast_world:shapeCast({type = 'circle', radius = 10}, 100, 150, 400, 0), wall, (300 - 110) / 400, -1, 0, 0.005)
    castCheck('rectangle toward a circle collider', cast_world:shapeCast({type = 'rectangle', w = 20, h = 20}, 100, 600, 400, 0), round, (270 - 110) / 400, -1, 0, 0.005)
    castCheck('circle onto a corner', cast_world:shapeCast({type = 'circle', radius = 5}, 1000, 0, 200, 200), corner, (100 - 5 / math.sqrt(2) * 1) / 200 * 1, -0.7071, -0.7071, 0.01)
    castCheck('circle onto the third chain segment', cast_world:shapeCast({type = 'circle', radius = 5}, 1650, 350, 0, 100), rail, 0.45, 0, -1, 0.005)
    castCheck('rotated rectangle uses its angle', cast_world:shapeCast({type = 'rectangle', w = 40, h = 4, angle = math.pi / 2}, 100, 150, 400, 0), wall, (300 - 102) / 400, -1, 0, 0.005)
    local overlapping = cast_world:shapeCast({type = 'circle', radius = 10}, 305, 150, 100, 0)
    check('shapeCast: starting inside a collider', overlapping and overlapping.fraction == 0 and overlapping.overlap == true)
    check('shapeCast: miss beside the wall', cast_world:shapeCast({type = 'circle', radius = 10}, 100, 50, 400, 0) == nil)
    check('shapeCast: moving away', cast_world:shapeCast({type = 'circle', radius = 10}, 100, 150, -400, 0) == nil)
    check('shapeCast: class filter', cast_world:shapeCast({type = 'circle', radius = 10}, 100, 150, 400, 0, {'All', except = {'Wall'}}) == nil)
    cast_world:destroy()

    local char_world = wf.newWorld(0, 500, true)
    local floor = char_world:newRectangleCollider(0, 300, 400, 20, {body_type = 'static'})
    local ramp = char_world:newPolygonCollider({500, 320, 900, 320, 900, 320 - 400 * math.tan(math.rad(30))}, {body_type = 'static'})
    local walker = char_world:newCircleCollider(100, 280, 10)
    local slider = char_world:newCircleCollider(800, 100, 10, {friction = 1})
    for _ = 1, 90 do char_world:update(1 / 60) end
    local flat = walker:getGround()
    check('getGround on flat ground', flat.grounded and flat.collider == floor and math.abs(flat.ny + 1) < 0.01 and flat.angle < 0.02, flat.grounded and flat.angle or 'not grounded')
    local slope = slider:getGround()
    check('getGround on a 30 degree slope', slope.grounded and slope.collider == ramp and math.abs(math.deg(slope.angle) - 30) < 1, slope.grounded and math.deg(slope.angle) or 'not grounded')
    check('getGround rejects a slope steeper than max_slope', not slider:getGround(math.rad(20)).grounded)
    check('getGround is false in the air', not char_world:newCircleCollider(100, 0, 5):getGround().grounded)

    local lift = char_world:newRectangleCollider(200, 100, 20, 20, {body_type = 'kinematic'})
    lift:moveKinematic(250, 130, 1, 1 / 60)
    char_world:update(1 / 60)
    local mx, my = lift:getPosition()
    check('moveKinematic reaches the target within one step', math.abs(mx - 250) < 0.01 and math.abs(my - 130) < 0.01 and math.abs(lift:getAngle() - 1) < 0.001,
        mx .. ' ' .. my .. ' ' .. lift:getAngle())
    lift:moveKinematic(1000, 130, nil, 1 / 60)
    char_world:update(1 / 60)
    check('moveKinematic is capped by the Box2D limit of 2 meters per step', math.abs(lift:getPosition() - 250 - 2 * love.physics.getMeter()) < 0.5, lift:getPosition())
    char_world:destroy()

    local drive_world = wf.newWorld(0, 0, true)
    local limb = drive_world:newRectangleCollider(0, 0, 20, 20)
    for _ = 1, 180 do
        limb:driveTo(300, 200, 0.5, 8)
        drive_world:update(1 / 60)
    end
    local lx, ly = limb:getPosition()
    check('driveTo converges on the target pose', math.abs(lx - 300) < 1 and math.abs(ly - 200) < 1 and math.abs(limb:getAngle() - 0.5) < 0.01, lx .. ' ' .. ly .. ' ' .. limb:getAngle())
    drive_world:destroy()

    local concave_world = wf.newWorld(0, 500, true)
    local l_shape = concave_world:newConcavePolygonCollider({0, 0, 200, 0, 200, 100, 100, 100, 100, 200, 0, 200}, {body_type = 'static'})
    local pieces = 0
    for _ in pairs(l_shape.shapes) do pieces = pieces + 1 end
    check('concave polygon: an L shape becomes at most two convex pieces', pieces >= 1 and pieces <= 2, pieces)
    concave_world:update(0)
    check('concave polygon: the column is solid', concave_world:getColliderAt(50, 150) == l_shape and concave_world:getColliderAt(150, 50) == l_shape)
    check('concave polygon: the notch is empty', concave_world:getColliderAt(150, 150) == nil)
    local notch_ball = concave_world:newCircleCollider(150, 150, 10)
    local rest_ball = concave_world:newCircleCollider(50, -50, 10)
    for _ = 1, 120 do concave_world:update(1 / 60) end
    check('concave polygon: a ball in the notch falls through it', select(2, notch_ball:getPosition()) > 300, select(2, notch_ball:getPosition()))
    check('concave polygon: a ball dropped on the top bar rests on it', select(2, rest_ball:getPosition()) < 0, select(2, rest_ball:getPosition()))
    local bodies = #concave_world:getBodies()
    check('concave polygon: a self intersecting polygon raises and leaves nothing behind',
        not pcall(concave_world.newConcavePolygonCollider, concave_world, {0, 0, 20, 20, 20, 0, 0, 20}) and #concave_world:getBodies() == bodies)
    local twelve = {}
    for i = 0, 11 do
        twelve[#twelve + 1] = 500 + 50 * math.cos(i * math.pi / 6)
        twelve[#twelve + 1] = 500 + 50 * math.sin(i * math.pi / 6)
    end
    local wheel = concave_world:newConcavePolygonCollider(twelve, {body_type = 'static'})
    local dropped = concave_world:newCircleCollider(500, 300, 10)
    for _ = 1, 150 do concave_world:update(1 / 60) end
    check('concave polygon: twelve vertices work around the Box2D limit', select(2, dropped:getPosition()) < 450, select(2, dropped:getPosition()))
    wheel:destroy()
    concave_world:destroy()

    local joint_world = wf.newWorld(0, 0, true)
    local ja = joint_world:newRectangleCollider(0, 0, 20, 20)
    local jb = joint_world:newRectangleCollider(60, 0, 20, 20)
    local jc = joint_world:newRectangleCollider(120, 0, 20, 20)
    local joints = {
        DistanceJoint = joint_world:newDistanceJoint(ja, jb, 10, 10, 70, 10, false, {frequency = 4, damping_ratio = 0.5}),
        RevoluteJoint = joint_world:newRevoluteJoint(ja, jb, 40, 10, false, {limits = {-0.5, 0.5}, motor = {speed = 1, torque = 100}}),
        PrismaticJoint = joint_world:newPrismaticJoint(jb, jc, 100, 10, 1, 0, false, {limits = {-20, 20}, motor = {speed = 5, force = 500}}),
        WeldJoint = joint_world:newWeldJoint(jb, jc, 100, 10),
        RopeJoint = joint_world:newRopeJoint(ja, jc, 10, 10, 130, 10, 150),
        WheelJoint = joint_world:newWheelJoint(ja, jc, 70, 10, 0, 1, false, {frequency = 5, damping_ratio = 0.7}),
        FrictionJoint = joint_world:newFrictionJoint(ja, jb, 40, 10),
        MotorJoint = joint_world:newMotorJoint(jb, jc, 0.3),
        MouseJoint = joint_world:newMouseJoint(ja, 10, 10),
        PulleyJoint = joint_world:newPulleyJoint(ja, jb, 0, -50, 60, -50, 10, 10, 70, 10, 1),
    }
    joints.GearJoint = joint_world:newGearJoint(joints.RevoluteJoint, joints.PrismaticJoint, 1)
    local mismatched = {}
    for name, joint in pairs(joints) do
        if joint:type() ~= name then mismatched[#mismatched + 1] = name .. '=' .. joint:type() end
    end
    check('named joint constructors build every LÖVE joint type', #mismatched == 0, table.concat(mismatched, ', '))
    check('joint options reach LÖVE', joints.RevoluteJoint:areLimitsEnabled() and joints.RevoluteJoint:isMotorEnabled()
        and math.abs(joints.RevoluteJoint:getMotorSpeed() - 1) < 1e-6 and joints.PrismaticJoint:isMotorEnabled()
        and math.abs(joints.DistanceJoint:getFrequency() - 4) < 1e-6 and math.abs(joints.WheelJoint:getSpringFrequency() - 5) < 1e-6)
    check('getJointsOf lists the joints of a collider', #joint_world:getJointsOf(jb) >= 5 and #joint_world:getJointsOf(joint_world:newCircleCollider(500, 500, 5)) == 0)
    check('getJointsOf sees a joint removed with removeJoint', (function()
        local before = #joint_world:getJointsOf(ja)
        joint_world:removeJoint(joints.FrictionJoint)
        return #joint_world:getJointsOf(ja) == before - 1
    end)())
    joint_world:destroy()

    local build_world = wf.newWorld(0, 500, true)
    local rope = build_world:newRope({x1 = 100, y1 = 50, x2 = 100, y2 = 250, segments = 10, pin_a = true})
    check('rope: N segments and N-1 joints plus the pin', #rope.parts == 10 and #rope.joints == 10 and #build_world:getBodies() == 11,
        #rope.parts .. ' ' .. #rope.joints .. ' ' .. #build_world:getBodies())
    local bridge = build_world:newBridge({x1 = 300, y1 = 300, x2 = 700, y2 = 300, segments = 10})
    local load = build_world:newRectangleCollider(480, 200, 40, 40)
    for _ = 1, 240 do build_world:update(1 / 60) end
    local lowest, finite = -math.huge, true
    for _, plank in ipairs(bridge.parts) do
        local x, y = plank:getPosition()
        if x ~= x or y ~= y then finite = false end
        lowest = math.max(lowest, y)
    end
    check('bridge: sags under a load without exploding', finite and lowest > 305 and lowest < 520, lowest)
    local first_x = bridge.parts[1]:getPosition()
    local last_x = bridge.parts[10]:getPosition()
    check('bridge: the pinned ends stay put', math.abs(first_x - 320) < 12 and math.abs(last_x - 680) < 12, first_x .. ' ' .. last_x)
    local rope_tip_x, rope_tip_y = rope.parts[10]:getPosition()
    check('rope: hangs below its pin and stays attached', rope_tip_y > 100 and math.abs(rope_tip_x - 100) < 60, rope_tip_x .. ' ' .. rope_tip_y)
    local bodies_before, joints_before = #build_world:getBodies(), #build_world:getJoints()
    bridge:destroy()
    check('bridge: destroy removes every plank, pin and joint', #build_world:getBodies() == bodies_before - 12 and #build_world:getJoints() == joints_before - 11,
        #build_world:getBodies() .. ' ' .. #build_world:getJoints())
    rope:destroy()

    local doll = build_world:newRagdoll({
        parts = {
            torso = {shape = 'rectangle', x = 400, y = 0, w = 20, h = 40},
            head = {shape = 'circle', x = 410, y = -14, r = 8},
            arm = {shape = 'rectangle', x = 420, y = 0, w = 30, h = 8},
        },
        joints = {
            {type = 'RevoluteJoint', a = 'torso', b = 'head', args = {410, -6}, options = {limits = {-0.6, 0.6}}},
            {type = 'RevoluteJoint', a = 'torso', b = 'arm', args = {420, 4}, options = {limits = {-1, 1}}},
        },
    })
    local rest_floor = build_world:newRectangleCollider(200, 400, 600, 20, {body_type = 'static'})
    for _ = 1, 240 do build_world:update(1 / 60) end
    local hx, hy = doll.parts.head:getPosition()
    local tx, ty = doll.parts.torso:getPosition()
    check('ragdoll: parts stay joined and settle on the floor', math.abs(hx - tx) < 40 and math.abs(hy - ty) < 60 and ty > 300 and ty < 400, hx .. ' ' .. hy .. ' ' .. tx .. ' ' .. ty)
    doll:destroy()
    check('ragdoll: destroy removes the parts and joints', #doll.parts.torso.world:getJointsOf(rest_floor) == 0)
    build_world:destroy()

    local fx_world = wf.newWorld(0, 0, true)
    local gust = fx_world:addEffector({shape = 'rectangle', x = 0, y = 0, w = 300, h = 100, gravity = {100, 0}})
    local inside = fx_world:newCircleCollider(50, 50, 10)
    local outside = fx_world:newCircleCollider(50, 900, 10)
    local pushed = fx_world:newCircleCollider(50, 300, 10)
    fx_world:addEffector({shape = 'circle', x = 50, y = 300, r = 200, force = {pushed:getMass() * 100, 0}})
    local dragged = fx_world:newCircleCollider(2000, 2000, 10)
    dragged:setLinearVelocity(200, 0)
    fx_world:addEffector({shape = 'rectangle', x = 1500, y = 1900, w = 8000, h = 300, drag = 2})
    for _ = 1, 60 do fx_world:update(1 / 60) end
    check('effector gravity accelerates by the given pixels per second squared', math.abs(inside:getLinearVelocity() - 100) < 3, inside:getLinearVelocity())
    check('effector force is in newtons scaled like applyForce (mass times acceleration)', math.abs(pushed:getLinearVelocity() - 100) < 3, pushed:getLinearVelocity())
    check('effector leaves colliders outside the region alone', outside:getLinearVelocity() == 0)
    check('effector drag decays the velocity', dragged:getLinearVelocity() > 20 and dragged:getLinearVelocity() < 35, dragged:getLinearVelocity())
    gust:destroy()
    local speed_before = inside:getLinearVelocity()
    for _ = 1, 30 do fx_world:update(1 / 60) end
    check('a destroyed effector stops acting', math.abs(inside:getLinearVelocity() - speed_before) < 1)
    fx_world:destroy()

    local pool_world = wf.newWorld(0, 300, true)
    pool_world:addEffector({shape = 'rectangle', x = -500, y = 100, w = 1000, h = 400, buoyancy = {density = 2, level = 100}, drag = 3})
    local cork = pool_world:newCircleCollider(0, 20, 10)
    local stone = pool_world:newCircleCollider(100, 20, 10)
    stone.fixture:setDensity(8)
    stone.body:resetMassData()
    for _ = 1, 480 do pool_world:update(1 / 60) end
    local cork_y = select(2, cork:getPosition())
    check('buoyancy: a body half as dense as the fluid floats half submerged', math.abs(cork_y - 100) < 4, cork_y)
    check('buoyancy: a body much denser than the fluid sinks', select(2, stone:getPosition()) > 300, select(2, stone:getPosition()))
    pool_world:destroy()
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
