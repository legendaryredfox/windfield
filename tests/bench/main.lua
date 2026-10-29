-- Benchmark of windfield against raw love.physics. Run with: sh tests/bench/run.sh
-- Prints RESULT lines: RESULT <library> <scenario> <metric> <value> <unit>
local REPS = 3

local function mem()
    collectgarbage()
    collectgarbage()
    return collectgarbage('count')
end

local function median(list)
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function out(lib, scenario, metric, value, unit)
    print(string.format('RESULT\t%s\t%s\t%s\t%.3f\t%s', lib, scenario, metric, value, unit))
end

-- Box2D family adapters ------------------------------------------------------
local adapters = {}

adapters.raw = {
    name = 'raw love.physics',
    newWorld = function(gx, gy) return love.physics.newWorld(gx, gy, true) end,
    addBox = function(w, x, y, bw, bh, kind)
        local body = love.physics.newBody(w, x + bw / 2, y + bh / 2, kind or 'dynamic')
        love.physics.newFixture(body, love.physics.newRectangleShape(bw, bh))
        return body
    end,
    update = function(w, dt) w:update(dt) end,
    queryRect = function(w, x, y, bw, bh)
        local n = 0
        w:queryBoundingBox(x, y, x + bw, y + bh, function() n = n + 1 return true end)
        return n
    end,
    ray = function(w, x1, y1, x2, y2)
        local n = 0
        w:rayCast(x1, y1, x2, y2, function() n = n + 1 return 1 end)
        return n
    end,
    destroy = function(o) o:destroy() end,
}

local wf = require('windfield')
adapters.windfield = {
    name = 'windfield',
    newWorld = function(gx, gy) return wf.newWorld(gx, gy, true) end,
    addBox = function(w, x, y, bw, bh, kind) return w:newRectangleCollider(x, y, bw, bh, {body_type = kind or 'dynamic'}) end,
    update = function(w, dt) w:update(dt) end,
    queryRect = function(w, x, y, bw, bh) return #w:queryRectangleArea(x, y, bw, bh) end,
    ray = function(w, x1, y1, x2, y2) return #w:queryLine(x1, y1, x2, y2) end,
    destroy = function(o) o:destroy() end,
    newPool = function(w)
        return w:newPool(function(x, y) return w:newRectangleCollider(x, y, 20, 20) end, function(c, x, y)
            c:setPosition(x + 10, y + 10)
        end)
    end,
}

adapters.windfield_poll = setmetatable({
    name = 'windfield + polling enter()',
    afterUpdate = function(w, items) for i = 1, #items do items[i]:enter('Default') end end,
}, {__index = adapters.windfield})

local order = {'raw', 'windfield', 'windfield_poll'}

-- Scenarios ------------------------------------------------------------------
local scenarios = {}

local N = 2000

local function grid(a, w, count, size, spacing)
    local items = {}
    local cols = 50
    for i = 0, count - 1 do
        items[#items + 1] = a.addBox(w, (i % cols) * spacing, math.floor(i / cols) * spacing, size, size)
    end
    return items
end

function scenarios.create(a)
    local before = mem()
    local w = a.newWorld(0, 0)
    local t0 = love.timer.getTime()
    local items = grid(a, w, N, 20, 30)
    local t1 = love.timer.getTime()
    local after = mem()
    return {{'time', (t1 - t0) * 1000, 'ms per 2000'}, {'memory', (after - before) / N, 'KB per collider'}}, items
end

function scenarios.idle(a)
    local w = a.newWorld(0, 0)
    local items = grid(a, w, N, 20, 30)
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 120 do
        a.update(w, 1 / 60)
        if a.afterUpdate then a.afterUpdate(w, items) end
    end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 120
    collectgarbage('restart')
    return {{'time', (t1 - t0) * 1000 / 120, 'ms per update'}, {'garbage', garbage, 'KB per update'}}, items
end

function scenarios.pile(a)
    math.randomseed(7)
    local w = a.newWorld(0, 500)
    a.addBox(w, 0, 590, 800, 20, 'static')
    a.addBox(w, -20, 0, 20, 600, 'static')
    a.addBox(w, 800, 0, 20, 600, 'static')
    local items = {}
    for _ = 1, 400 do
        items[#items + 1] = a.addBox(w, 40 + math.random() * 720, math.random() * 300, 14, 14)
    end
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 240 do
        a.update(w, 1 / 60)
        if a.afterUpdate then a.afterUpdate(w, items) end
    end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 240
    collectgarbage('restart')
    return {{'time', (t1 - t0) * 1000 / 240, 'ms per update'}, {'garbage', garbage, 'KB per update'}}, items
end

function scenarios.query(a)
    math.randomseed(11)
    local w = a.newWorld(0, 0)
    local items = grid(a, w, 1000, 20, 30)
    local hits = 0
    local t0 = love.timer.getTime()
    for _ = 1, 2000 do
        hits = hits + a.queryRect(w, math.random() * 1400, math.random() * 600, 100, 100)
    end
    local t1 = love.timer.getTime()
    return {{'time', (t1 - t0) * 1000, 'ms per 2000 rect queries'}}, items
end

function scenarios.ray(a)
    if not a.ray then return nil end
    math.randomseed(13)
    local w = a.newWorld(0, 0)
    local items = grid(a, w, 1000, 20, 30)
    local t0 = love.timer.getTime()
    for _ = 1, 2000 do
        local x, y = math.random() * 1400, math.random() * 600
        a.ray(w, x, y, x + 300, y + 100)
    end
    local t1 = love.timer.getTime()
    return {{'time', (t1 - t0) * 1000, 'ms per 2000 rays'}}, items
end

function scenarios.churn(a)
    local w = a.newWorld(0, 0)
    local live = {}
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 20 do
        for i = 1, #live do a.destroy(live[i]) end
        live = {}
        for i = 1, 300 do live[i] = a.addBox(w, (i % 50) * 30, math.floor(i / 50) * 30, 20, 20) end
        a.update(w, 1 / 60)
    end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 20
    collectgarbage('restart')
    return {{'time', (t1 - t0) * 1000 / 20, 'ms per frame (300 create + 300 destroy)'}, {'garbage', garbage, 'KB per frame'}}, live
end

function scenarios.poolchurn(a)
    if not a.newPool then return nil end
    local w = a.newWorld(0, 0)
    local pool = a.newPool(w)
    local live = {}
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 20 do
        for i = 1, #live do pool:release(live[i]) end
        live = {}
        for i = 1, 300 do live[i] = pool:get((i % 50) * 30, math.floor(i / 50) * 30) end
        a.update(w, 1 / 60)
    end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 20
    collectgarbage('restart')
    return {{'time', (t1 - t0) * 1000 / 20, 'ms per frame (300 get + 300 release)'}, {'garbage', garbage, 'KB per frame'}}, live
end

local scenario_order = {'create', 'idle', 'pile', 'query', 'ray', 'churn', 'poolchurn'}

-- Moving boxes ------------------------------------------------------------------
local movers = {}

movers.windfield = function()
    local world = wf.newWorld(0, 0, true)
    math.randomseed(21)
    for _ = 1, 300 do
        local c = world:newRectangleCollider(math.random() * 1900, math.random() * 1900, 16, 16)
        c:setLinearVelocity(math.random() * 120 - 60, math.random() * 120 - 60)
    end
    for _ = 1, 300 do
        world:newRectangleCollider(math.random() * 1900, math.random() * 1900, 40, 40, {body_type = 'static'})
    end
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 120 do world:update(1 / 60) end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 120
    collectgarbage('restart')
    return (t1 - t0) * 1000 / 120, garbage
end

movers.raw = function()
    local world = love.physics.newWorld(0, 0, true)
    math.randomseed(21)
    for _ = 1, 300 do
        local body = love.physics.newBody(world, math.random() * 1900, math.random() * 1900, 'dynamic')
        love.physics.newFixture(body, love.physics.newRectangleShape(16, 16))
        body:setLinearVelocity(math.random() * 120 - 60, math.random() * 120 - 60)
    end
    for _ = 1, 300 do
        local body = love.physics.newBody(world, math.random() * 1900, math.random() * 1900, 'static')
        love.physics.newFixture(body, love.physics.newRectangleShape(40, 40))
    end
    mem()
    collectgarbage('stop')
    local g0 = collectgarbage('count')
    local t0 = love.timer.getTime()
    for _ = 1, 120 do world:update(1 / 60) end
    local t1 = love.timer.getTime()
    local garbage = (collectgarbage('count') - g0) / 120
    collectgarbage('restart')
    return (t1 - t0) * 1000 / 120, garbage
end

-- Runner -----------------------------------------------------------------------
function love.load()
    for _, key in ipairs(order) do
        local a = adapters[key]
        for _, sname in ipairs(scenario_order) do
            local samples = {}
            local ok, err = true, nil
            for rep = 1, REPS do
                collectgarbage()
                local pok, metrics = pcall(scenarios[sname], a)
                if not pok then ok, err = false, metrics break end
                if not metrics then ok, err = false, 'not supported' break end
                for i, m in ipairs(metrics) do
                    samples[i] = samples[i] or {name = m[1], unit = m[3], values = {}}
                    samples[i].values[#samples[i].values + 1] = m[2]
                end
            end
            if ok then
                for _, s in ipairs(samples) do out(a.name, sname, s.name, median(s.values), s.unit) end
            else
                print(string.format('RESULT\t%s\t%s\tn/a\t0\t%s', a.name, sname, tostring(err):gsub('\n.*', '')))
            end
        end
    end

    for _, key in ipairs({'windfield', 'raw'}) do
        local samples_t, samples_g = {}, {}
        local ok, err = true, nil
        for rep = 1, REPS do
            local pok, t, g = pcall(movers[key])
            if not pok then ok, err = false, t break end
            samples_t[#samples_t + 1], samples_g[#samples_g + 1] = t, g
        end
        local label = key == 'raw' and 'raw love.physics' or key
        if ok then
            out(label, 'movers', 'time', median(samples_t), 'ms per frame (300 movers, 300 obstacles)')
            out(label, 'movers', 'garbage', median(samples_g), 'KB per frame')
        else
            print(string.format('RESULT\t%s\tmovers\tn/a\t0\t%s', label, tostring(err):gsub('\n.*', '')))
        end
    end
    love.event.quit(0)
end
