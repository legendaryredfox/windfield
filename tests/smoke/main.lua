-- Real LÖVE 11.5 check of the flows the mock covers, plus a screenshot of the
-- debug drawing. Run with: sh tests/smoke/run.sh
love.setDeprecationOutput(true)
love.filesystem.setIdentity('windfield-smoke')

local wf = require('windfield')

local failed = 0
local frame = 0
local world, ground, player, ghost
local seen = {}

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

    check('Ghost mask lists Player', #world.masks.Ghost.masks > 0)
end

function love.update(dt)
    frame = frame + 1
    world:update(1 / 60)
    if frame == 150 then world:queryRectangleArea(40, 290, 320, 40, {'Ground'}) end
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
        love.event.quit(failed == 0 and 0 or 1)
    end
end
