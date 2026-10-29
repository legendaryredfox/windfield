--[[
The MIT License (MIT)

Copyright (c) 2018 SSYGEN

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]--

local unpack = table.unpack or unpack
local meter_initialized = false
local path = ... .. '.' 
local wf = {} 
wf._VERSION = '0.3.0'
wf.Math = require(path .. 'mlib.mlib') 

-- Resolves LÖVE object methods on first use and caches them, so instances do not carry one closure per method.
local proxy_excluded = {__gc = true, __eq = true, __index = true, __tostring = true, destroy = true, type = true, typeOf = true}

local function newProxyIndex(class, parts)
    local index = {}
    return setmetatable(index, {__index = function(_, key)
        local method = class[key]
        if method ~= nil then return method end
        if proxy_excluded[key] then return end
        for _, part in ipairs(parts) do
            local fn = part.methods[key]
            if fn then
                local field = part.field
                local proxy = function(self, ...) return fn(self[field], ...) end
                index[key] = proxy
                return proxy
            end
        end
    end})
end

local World = {}
local world_metatable

local function collisionData(event)
    return {collider = event.collider_2, contact = event.contact,
            nx = event.nx, ny = event.ny, x1 = event.x1, y1 = event.y1, x2 = event.x2, y2 = event.y2}
end

function wf.newWorld(xg, yg, sleep, options)
    local world = wf.World.new(wf, xg, yg, sleep, options)

    world.box2d_world:setCallbacks(world.collisionOnEnter, world.collisionOnExit, world.collisionPre, world.collisionPost)
    world:collisionClear()
    world:addCollisionClass('Default')

    return world
end

function World.new(wf, xg, yg, sleep, options)
    local self = {}
    self.wf = wf

    self.draw_query_for_n_frames = 10
    self.query_debug_drawing_enabled = false
    self.explicit_collision_events = false
    self.dirty_colliders = {}
    self.collision_handlers = {}
    self.has_collision_handlers = false
    self.step_events = {}
    self.stepping = false
    self.destroy_queue = {}
    self.one_way = {}
    self.conveyors = {}
    self.has_contact_rules = false
    self.has_draw_order = false
    self.query_world = nil
    self.query_body = nil
    self.query_chain_body = nil
    self.collider_filter = nil
    self.filtered_contacts = setmetatable({}, {__mode = 'k'})
    self.fixed_dt = 1/60
    self.max_steps = 5
    self.accumulator = 0
    self.interpolated = {}
    self.query_results = {}
    self.query_callback = function(fixture)
        local collider = fixture:getUserData()
        if collider and not collider.destroy_pending and not fixture:isSensor() then
            local results = self.query_results
            results[#results + 1] = collider
        end
        return true
    end
    self.ray_callback = function(fixture)
        local collider = fixture:getUserData()
        if collider and not collider.destroy_pending and not fixture:isSensor() then
            local results = self.query_results
            results[#results + 1] = collider
        end
        return 1
    end
    self.collision_classes = {}
    self.masks = {}
    self.is_sensor_memo = {}
    self.query_debug_draw = {}

    local meter = options and options.meter
    if meter ~= nil and (type(meter) ~= 'number' or meter <= 0) then error('options.meter must be a positive number.') end
    if meter or not meter_initialized then love.physics.setMeter(meter or 32) end
    meter_initialized = true
    self.box2d_world = love.physics.newWorld(xg, yg, sleep) 

    world_metatable = world_metatable or {__index = newProxyIndex(World, {{field = 'box2d_world', methods = self.box2d_world.__index}})}
    return setmetatable(self, world_metatable)
end

function World:update(dt)
    self:collisionEventsClear()
    self.stepping = true
    self.box2d_world:update(dt)
    self.stepping = false
    local queue = self.destroy_queue
    for i = 1, #queue do queue[i]:_destroy() end
    for i = #queue, 1, -1 do queue[i] = nil end
    if self.has_collision_handlers then self:_dispatchCollisionEvents() end
end

function World:setFixedStep(dt, max_steps)
    max_steps = max_steps or 5
    if type(dt) ~= 'number' or dt <= 0 then error('The fixed step must be a positive number.') end
    if type(max_steps) ~= 'number' or max_steps < 1 then error('max_steps must be at least 1.') end
    self.fixed_dt = dt
    self.max_steps = max_steps
end

function World:step(dt)
    local fixed, steps = self.fixed_dt, 0
    self.accumulator = self.accumulator + dt
    while self.accumulator >= fixed and steps < self.max_steps do
        for collider in pairs(self.interpolated) do collider:_snapshot() end
        self:update(fixed)
        self.accumulator = self.accumulator - fixed
        steps = steps + 1
    end
    if self.accumulator >= fixed then self.accumulator = self.accumulator % fixed end
    return steps
end

function World:setColliderFilter(fn)
    if fn ~= nil and type(fn) ~= 'function' then error('The contact filter must be a function or nil.') end
    self.collider_filter = fn
end

function World:getAlpha()
    return self.accumulator / self.fixed_dt
end

function World:_addCollisionHandler(collision_type, class_a, class_b, fn, collider)
    local handler = {collision_type = collision_type, class_a = class_a, class_b = class_b, fn = fn, collider = collider}
    table.insert(self.collision_handlers, handler)
    self.has_collision_handlers = true
    return {remove = function()
        handler.removed = true
        for i = #self.collision_handlers, 1, -1 do
            if self.collision_handlers[i] == handler then table.remove(self.collision_handlers, i) end
        end
        self.has_collision_handlers = #self.collision_handlers > 0
    end}
end

function World:onEnter(class_a, class_b, fn)
    return self:_addCollisionHandler('enter', class_a, class_b, fn)
end

function World:onExit(class_a, class_b, fn)
    return self:_addCollisionHandler('exit', class_a, class_b, fn)
end

function World:_dispatchCollisionEvents()
    local events = self.step_events
    self.step_events = {}
    for _, event in ipairs(events) do
        local a, b = event.collider_1, event.collider_2
        if a.body and b.body then
            local handlers = {unpack(self.collision_handlers)}
            for _, handler in ipairs(handlers) do
                if not handler.removed and handler.collision_type == event.collision_type then
                    if handler.collider then
                        if handler.collider == a and b.collision_class == handler.class_b then
                            handler.fn(a, b, collisionData(event))
                        end
                    elseif a.collision_class == handler.class_a and b.collision_class == handler.class_b
                        and (handler.class_a ~= handler.class_b or a.id < b.id) then
                        handler.fn(a, b, collisionData(event))
                    end
                end
            end
        end
    end
end

local draw_options = {alpha = true, class_colors = true, line_width = true, contacts = true, aabb = true, velocities = true, sleeping = true}

local function drawFixture(body, fixture)
    local shape = fixture:getShape()
    local shape_type = shape:type()
    if shape_type == 'PolygonShape' then
        love.graphics.polygon('line', body:getWorldPoints(shape:getPoints()))
    elseif shape_type == 'EdgeShape' or shape_type == 'ChainShape' then
        local points = {body:getWorldPoints(shape:getPoints())}
        for i = 1, #points, 2 do
            if i < #points-2 then love.graphics.line(points[i], points[i+1], points[i+2], points[i+3]) end
        end
    elseif shape_type == 'CircleShape' then
        local body_x, body_y = body:getPosition()
        local shape_x, shape_y = shape:getPoint()
        love.graphics.circle('line', body_x + shape_x, body_y + shape_y, shape:getRadius(), 360)
    end
end

local function drawContacts(world, alpha)
    love.graphics.setColor(222/255, 64/255, 64/255, alpha)
    for _, contact in ipairs(world.box2d_world:getContacts()) do
        if contact:isTouching() then
            local nx, ny = contact:getNormal()
            local x1, y1, x2, y2 = contact:getPositions()
            if x1 then
                love.graphics.circle('line', x1, y1, 3)
                love.graphics.line(x1, y1, x1 + nx * 12, y1 + ny * 12)
            end
            if x2 then love.graphics.circle('line', x2, y2, 3) end
        end
    end
end

local function drawBody(body, options, alpha)
    local fixtures = body:getFixtures()
    local first = fixtures[1]
    local first_collider = first and first:getUserData()
    if first_collider and first_collider.draw then
        first_collider:draw(options.alpha or 255)
        love.graphics.setLineWidth(options.line_width or 1)
        return
    end
    local body_alpha = alpha
    if options.sleeping and not body:isAwake() then body_alpha = alpha * 0.4 end
    local class_colors = options.class_colors
    for _, fixture in ipairs(fixtures) do
        local collider = fixture:getUserData()
        if not (collider and fixture:isSensor()) then
            local color = class_colors and collider and class_colors[collider.collision_class]
            if color then love.graphics.setColor(color[1], color[2], color[3], body_alpha)
            else love.graphics.setColor(222/255, 222/255, 222/255, body_alpha) end
            drawFixture(body, fixture)
        end
    end
end

function World:draw(options)
    if type(options) ~= 'table' then options = {alpha = options} end
    for key in pairs(options) do
        if not draw_options[key] then error('Unknown draw option ' .. tostring(key) .. '.', 2) end
    end
    -- get the current color values to reapply
    local r, g, b, a = love.graphics.getColor()
    local line_width = love.graphics.getLineWidth()
    -- alpha value is optional, 0-255
    local alpha = (options.alpha or 255) / 255
    love.graphics.setLineWidth(options.line_width or 1)

    -- Colliders debug
    local bodies = self.box2d_world:getBodies()
    if self.has_draw_order then
        local entries = {}
        for index, body in ipairs(bodies) do
            local first = body:getFixtures()[1]
            local collider = first and first:getUserData()
            entries[index] = {body = body, order = collider and collider.draw_order or 0, index = index}
        end
        table.sort(entries, function(x, y)
            if x.order ~= y.order then return x.order < y.order end
            return x.index < y.index
        end)
        for _, entry in ipairs(entries) do drawBody(entry.body, options, alpha) end
    else
        for _, body in ipairs(bodies) do drawBody(body, options, alpha) end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    if options.aabb then
        love.graphics.setColor(128/255, 128/255, 128/255, alpha)
        for _, body in ipairs(bodies) do
            for _, fixture in ipairs(body:getFixtures()) do
                if not (fixture:getUserData() and fixture:isSensor()) then
                    for child = 1, fixture:getShape():getChildCount() do
                        local x1, y1, x2, y2 = fixture:getBoundingBox(child)
                        love.graphics.rectangle('line', x1, y1, x2 - x1, y2 - y1)
                    end
                end
            end
        end
    end

    if options.velocities then
        love.graphics.setColor(64/255, 222/255, 64/255, alpha)
        for _, body in ipairs(bodies) do
            local vx, vy = body:getLinearVelocity()
            if body:getType() ~= 'static' and (vx ~= 0 or vy ~= 0) then
                local x, y = body:getPosition()
                love.graphics.line(x, y, x + vx * 0.25, y + vy * 0.25)
            end
        end
    end

    if options.contacts then drawContacts(self, alpha) end

    -- Joint debug
    love.graphics.setColor(222/255, 128/255, 64/255, alpha)
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do
        local x1, y1, x2, y2 = joint:getAnchors()
        if x1 and y1 then love.graphics.circle('line', x1, y1, 4) end
        if x2 and y2 then love.graphics.circle('line', x2, y2, 4) end
    end
    love.graphics.setColor(1, 1, 1, alpha)

    -- Query debug
    love.graphics.setColor(64/255, 64/255, 222/255, alpha)
    for _, query_draw in ipairs(self.query_debug_draw) do
        query_draw.frames = query_draw.frames - 1
        if query_draw.type == 'circle' then
            love.graphics.circle('line', query_draw.x, query_draw.y, query_draw.r)
        elseif query_draw.type == 'rectangle' then
            love.graphics.rectangle('line', query_draw.x, query_draw.y, query_draw.w, query_draw.h)
        elseif query_draw.type == 'line' then
            love.graphics.line(query_draw.x1, query_draw.y1, query_draw.x2, query_draw.y2)
        elseif query_draw.type == 'polygon' then
            local triangles = love.math.triangulate(query_draw.vertices)
            for _, triangle in ipairs(triangles) do love.graphics.polygon('line', triangle) end
        end
    end
    for i = #self.query_debug_draw, 1, -1 do
        if self.query_debug_draw[i].frames <= 0 then
            table.remove(self.query_debug_draw, i)
        end
    end
    love.graphics.setLineWidth(line_width)
    love.graphics.setColor(r, g, b, a)
end

function World:setQueryDebugDrawing(value)
    self.query_debug_drawing_enabled = value
end

function World:setExplicitCollisionEvents(value)
    self.explicit_collision_events = value
end

local function classIgnores(collision_class)
    if collision_class.sensor then return {'All'} end
    return collision_class.ignores or {}
end

function World:addCollisionClass(collision_class_name, collision_class)
    if collision_class and collision_class.sensor and collision_class.ignores then
        error('Collision class ' .. collision_class_name .. ' cannot set both sensor and ignores.')
    end
    local one_way, conveyor
    if collision_class and collision_class.one_way ~= nil then
        local normal = collision_class.one_way
        local nx, ny = type(normal) == 'table' and normal[1], type(normal) == 'table' and normal[2]
        if type(nx) ~= 'number' or type(ny) ~= 'number' or (nx == 0 and ny == 0) then
            error('Collision class ' .. collision_class_name .. ': one_way must be a table {nx, ny} that is not zero.')
        end
        local length = math.sqrt(nx * nx + ny * ny)
        one_way = {nx = nx / length, ny = ny / length}
    end
    if collision_class and collision_class.conveyor ~= nil then
        conveyor = collision_class.conveyor
        if type(conveyor) ~= 'number' then error('Collision class ' .. collision_class_name .. ': conveyor must be a number.') end
    end
    if self.collision_classes[collision_class_name] then error('Collision class ' .. collision_class_name .. ' already exists.') end

    if self.explicit_collision_events then
        self.collision_classes[collision_class_name] = collision_class or {}
    else
        self.collision_classes[collision_class_name] = collision_class or {}
        self.collision_classes[collision_class_name].enter = {}
        self.collision_classes[collision_class_name].exit = {}
        self.collision_classes[collision_class_name].pre = {}
        self.collision_classes[collision_class_name].post = {}
        for c_class_name, _ in pairs(self.collision_classes) do
            table.insert(self.collision_classes[collision_class_name].enter, c_class_name)
            table.insert(self.collision_classes[collision_class_name].exit, c_class_name)
            table.insert(self.collision_classes[collision_class_name].pre, c_class_name)
            table.insert(self.collision_classes[collision_class_name].post, c_class_name)
        end
        for c_class_name, _ in pairs(self.collision_classes) do
            if c_class_name ~= collision_class_name then
                table.insert(self.collision_classes[c_class_name].enter, collision_class_name)
                table.insert(self.collision_classes[c_class_name].exit, collision_class_name)
                table.insert(self.collision_classes[c_class_name].pre, collision_class_name)
                table.insert(self.collision_classes[c_class_name].post, collision_class_name)
            end
        end
    end

    self.one_way[collision_class_name] = one_way
    self.conveyors[collision_class_name] = conveyor
    self.has_contact_rules = next(self.one_way) ~= nil or next(self.conveyors) ~= nil

    self:collisionClassesSet()
end

function World:collisionClassesSet()
    self:generateCategoriesMasks()
    self.is_sensor_memo = {}

    for _, body in ipairs(self.box2d_world:getBodies()) do
        local fixture = body:getFixtures()[1]
        local collider = fixture and fixture:getUserData()
        if collider then collider:setCollisionClass(collider.collision_class) end
    end

    self:collisionClear()
    local collision_table = self:getCollisionCallbacksTable()
    for collision_class_name, collision_list in pairs(collision_table) do
        for _, collision_info in ipairs(collision_list) do
            if collision_info.type == 'enter' then self:addCollisionEnter(collision_class_name, collision_info.other) end
            if collision_info.type == 'exit' then self:addCollisionExit(collision_class_name, collision_info.other) end
            if collision_info.type == 'pre' then self:addCollisionPre(collision_class_name, collision_info.other) end
            if collision_info.type == 'post' then self:addCollisionPost(collision_class_name, collision_info.other) end
        end
    end

    self:collisionEventsClear()
end

function World:collisionClear()
    self.collisions = {}
    self.collisions.on_enter = {}
    self.collisions.on_enter.sensor = {}
    self.collisions.on_enter.non_sensor = {}
    self.collisions.on_exit = {}
    self.collisions.on_exit.sensor = {}
    self.collisions.on_exit.non_sensor = {}
    self.collisions.pre = {}
    self.collisions.pre.sensor = {}
    self.collisions.pre.non_sensor = {}
    self.collisions.post = {}
    self.collisions.post.sensor = {}
    self.collisions.post.non_sensor = {}
end

function World:collisionEventsClear()
    local dirty = self.dirty_colliders
    for i = 1, #dirty do dirty[i]:collisionEventsClear() end
    for i = #dirty, 1, -1 do dirty[i] = nil end
end

function World:addCollisionEnter(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.on_enter.non_sensor, {type1 = type1, type2 = type2})
    else table.insert(self.collisions.on_enter.sensor, {type1 = type1, type2 = type2}) end
end

function World:addCollisionExit(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.on_exit.non_sensor, {type1 = type1, type2 = type2})
    else table.insert(self.collisions.on_exit.sensor, {type1 = type1, type2 = type2}) end
end

function World:addCollisionPre(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.pre.non_sensor, {type1 = type1, type2 = type2})
    else table.insert(self.collisions.pre.sensor, {type1 = type1, type2 = type2}) end
end

function World:addCollisionPost(type1, type2)
    if not self:isCollisionBetweenSensors(type1, type2) then
        table.insert(self.collisions.post.non_sensor, {type1 = type1, type2 = type2})
    else table.insert(self.collisions.post.sensor, {type1 = type1, type2 = type2}) end
end

function World:doesType1IgnoreType2(type1, type2)
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = classIgnores(collision_class)
    end
    local all = {}
    for collision_class_name, _ in pairs(collision_ignores) do
        table.insert(all, collision_class_name)
    end
    local ignored_types = {}
    for _, collision_class_type in ipairs(collision_ignores[type1]) do
        if collision_class_type == 'All' then
            for _, collision_class_name in ipairs(all) do
                table.insert(ignored_types, collision_class_name)
            end
        else table.insert(ignored_types, collision_class_type) end
    end
    for key, _ in pairs(collision_ignores[type1]) do
        if key == 'except' then
            for _, except_type in ipairs(collision_ignores[type1].except) do
                for i = #ignored_types, 1, -1 do
                    if ignored_types[i] == except_type then table.remove(ignored_types, i) end
                end
            end
        end
    end
    for _, ignored_type in ipairs(ignored_types) do
        if ignored_type == type2 then return true end
    end
end

function World:isCollisionBetweenSensors(type1, type2)
    if not self.is_sensor_memo[type1] then self.is_sensor_memo[type1] = {} end
    if not self.is_sensor_memo[type1][type2] then self.is_sensor_memo[type1][type2] = (self:doesType1IgnoreType2(type1, type2) or self:doesType1IgnoreType2(type2, type1)) end
    if self.is_sensor_memo[type1][type2] then return true
    else return false end
end

-- https://love2d.org/forums/viewtopic.php?f=4&t=75441
function World:generateCategoriesMasks()
    local collision_ignores = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_ignores[collision_class_name] = classIgnores(collision_class)
    end
    local incoming = {}
    local expanded = {}
    local all = {}
    for object_type, _ in pairs(collision_ignores) do
        incoming[object_type] = {}
        expanded[object_type] = {}
        table.insert(all, object_type)
    end
    for object_type, ignore_list in pairs(collision_ignores) do
        for key, ignored_type in pairs(ignore_list) do
            if ignored_type == 'All' then
                for _, all_object_type in ipairs(all) do
                    table.insert(incoming[all_object_type], object_type)
                    table.insert(expanded[object_type], all_object_type)
                end
            elseif type(ignored_type) == 'string' then
                if ignored_type ~= 'All' then
                    table.insert(incoming[ignored_type], object_type)
                    table.insert(expanded[object_type], ignored_type)
                end
            end
            if key == 'except' then
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(incoming[except_ignored_type]) do
                        if v == object_type then
                            table.remove(incoming[except_ignored_type], i)
                            break
                        end
                    end
                end
                for _, except_ignored_type in ipairs(ignored_type) do
                    for i, v in ipairs(expanded[object_type]) do
                        if v == except_ignored_type then
                            table.remove(expanded[object_type], i)
                            break
                        end
                    end
                end
            end
        end
    end
    local edge_groups = {}
    for k, v in pairs(incoming) do
        table.sort(v, function(a, b) return string.lower(a) < string.lower(b) end)
    end
    local i = 0
    for k, v in pairs(incoming) do
        local str = ""
        for _, c in ipairs(v) do
            str = str .. c
        end
        if not edge_groups[str] then i = i + 1; edge_groups[str] = {n = i} end
        table.insert(edge_groups[str], k)
    end
    local categories = {}
    for k, _ in pairs(collision_ignores) do
        categories[k] = {}
    end
    for k, v in pairs(edge_groups) do
        for i, c in ipairs(v) do
            categories[c] = v.n
        end
    end
    for k, v in pairs(expanded) do
        local category = {categories[k]}
        local current_masks = {}
        for _, c in ipairs(v) do
            table.insert(current_masks, categories[c])
        end
        self.masks[k] = {categories = category, masks = current_masks}
    end
end

function World:getCollisionCallbacksTable()
    local collision_table = {}
    for collision_class_name, collision_class in pairs(self.collision_classes) do
        collision_table[collision_class_name] = {}
        for _, v in ipairs(collision_class.enter or {}) do table.insert(collision_table[collision_class_name], {type = 'enter', other = v}) end
        for _, v in ipairs(collision_class.exit or {}) do table.insert(collision_table[collision_class_name], {type = 'exit', other = v}) end
        for _, v in ipairs(collision_class.pre or {}) do table.insert(collision_table[collision_class_name], {type = 'pre', other = v}) end
        for _, v in ipairs(collision_class.post or {}) do table.insert(collision_table[collision_class_name], {type = 'post', other = v}) end
    end
    return collision_table
end

local function collEnsure(collision_class_name1, a, collision_class_name2, b)
    if a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1 then return b, a
    else return a, b end
end

local function collIf(collision_class_name1, collision_class_name2, a, b)
    if (a.collision_class == collision_class_name1 and b.collision_class == collision_class_name2) or
       (a.collision_class == collision_class_name2 and b.collision_class == collision_class_name1) then
       return true
    else return false end
end

-- Contact objects are only valid during the physics step, so their geometry is copied here.
local function newCollisionEvent(collision_type, collider_1, collider_2, contact)
    local nx, ny = contact:getNormal()
    local x1, y1, x2, y2 = contact:getPositions()
    return {collision_type = collision_type, collider_1 = collider_1, collider_2 = collider_2, contact = contact,
            nx = nx, ny = ny, x1 = x1, y1 = y1, x2 = x2, y2 = y2}
end

local function trackStay(collider, other_collision_class_name, event)
    local stay = collider.collision_stay
    if not stay then return end
    if event.collision_type == 'enter' then
        stay[other_collision_class_name] = stay[other_collision_class_name] or {}
        table.insert(stay[other_collision_class_name], collisionData(event))
    elseif stay[other_collision_class_name] then
        for i = #stay[other_collision_class_name], 1, -1 do
            if stay[other_collision_class_name][i].collider.id == event.collider_2.id then
                table.remove(stay[other_collision_class_name], i)
            end
        end
    end
end

local function addCollisionEvent(collider, other_collision_class_name, event)
    local events = collider.collision_events[other_collision_class_name]
    if not events then
        events = {}
        collider.collision_events[other_collision_class_name] = events
    end
    events[#events + 1] = event
    trackStay(collider, other_collision_class_name, event)
    if collider.world.has_collision_handlers then
        local step_events = collider.world.step_events
        step_events[#step_events + 1] = event
    end
    if not collider.has_events then
        collider.has_events = true
        local dirty = collider.world.dirty_colliders
        dirty[#dirty + 1] = collider
    end
end

local function emitCollisionEvents(list, event_type, a, b, contact)
    for _, collision in ipairs(list) do
        if collIf(collision.type1, collision.type2, a, b) then
            a, b = collEnsure(collision.type1, a, collision.type2, b)
            addCollisionEvent(a, collision.type2, newCollisionEvent(event_type, a, b, contact))
            if collision.type1 == collision.type2 then
                addCollisionEvent(b, collision.type1, newCollisionEvent(event_type, b, a, contact))
            end
        end
    end
end

local one_way_speed_tolerance = 1

function World._oneWaySolid(platform_nx, platform_ny, contact_nx, contact_ny, relative_vx, relative_vy)
    return contact_nx * platform_nx + contact_ny * platform_ny > 0
        and relative_vx * platform_nx + relative_vy * platform_ny <= one_way_speed_tolerance
end

local function oneWayDisables(platform, other, contact_nx, contact_ny)
    local normal = platform.world.one_way[platform.collision_class]
    if not normal then return false end
    local pvx, pvy = platform.body:getLinearVelocity()
    local ovx, ovy = other.body:getLinearVelocity()
    return not World._oneWaySolid(normal.nx, normal.ny, contact_nx, contact_ny, ovx - pvx, ovy - pvy)
end

local function applyContactRules(world, a, b, contact)
    local nx, ny = contact:getNormal()
    if oneWayDisables(a, b, nx, ny) or oneWayDisables(b, a, -nx, -ny) then contact:setEnabled(false) end
    local speed = world.conveyors[a.collision_class] or world.conveyors[b.collision_class]
    if speed then contact:setTangentSpeed(-speed / love.physics.getMeter()) end
end

local function contactRejected(a, b, contact)
    local filter = a.world.collider_filter
    if not filter or filter(a, b) ~= false then return false end
    contact:setEnabled(false)
    return true
end

function World.collisionOnEnter(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            local lists = a.world.collisions.on_enter
            emitCollisionEvents(lists.sensor, 'enter', a, b, contact)
            if a.sensor_mode or b.sensor_mode then emitCollisionEvents(lists.non_sensor, 'enter', a, b, contact) end
        end

    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            if contactRejected(a, b, contact) then a.world.filtered_contacts[contact] = true
            else emitCollisionEvents(a.world.collisions.on_enter.non_sensor, 'enter', a, b, contact) end
        end
    end
end

function World.collisionOnExit(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            local lists = a.world.collisions.on_exit
            emitCollisionEvents(lists.sensor, 'exit', a, b, contact)
            if a.sensor_mode or b.sensor_mode then emitCollisionEvents(lists.non_sensor, 'exit', a, b, contact) end
        end

    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            local filtered = a.world.filtered_contacts
            if filtered[contact] then filtered[contact] = nil
            else emitCollisionEvents(a.world.collisions.on_exit.non_sensor, 'exit', a, b, contact) end
        end
    end
end

function World.collisionPre(fixture_a, fixture_b, contact)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.pre.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:preSolve(b, contact)
                    if collision.type1 == collision.type2 then 
                        b:preSolve(a, contact)
                    end
                end
            end
        end

    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b and not contactRejected(a, b, contact) then
            if a.world.has_contact_rules then applyContactRules(a.world, a, b, contact) end
            for _, collision in ipairs(a.world.collisions.pre.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:preSolve(b, contact)
                    if collision.type1 == collision.type2 then 
                        b:preSolve(a, contact)
                    end
                end
            end
        end
    end
end

function World.collisionPost(fixture_a, fixture_b, contact, ni1, ti1, ni2, ti2)
    local a, b = fixture_a:getUserData(), fixture_b:getUserData()

    if fixture_a:isSensor() and fixture_b:isSensor() then
        if a and b then
            for _, collision in ipairs(a.world.collisions.post.sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:postSolve(b, contact, ni1, ti1, ni2, ti2)
                    if collision.type1 == collision.type2 then 
                        b:postSolve(a, contact, ni1, ti1, ni2, ti2)
                    end
                end
            end
        end

    elseif not (fixture_a:isSensor() or fixture_b:isSensor()) then
        if a and b then
            for _, collision in ipairs(a.world.collisions.post.non_sensor) do
                if collIf(collision.type1, collision.type2, a, b) then
                    a, b = collEnsure(collision.type1, a, collision.type2, b)
                    a:postSolve(b, contact, ni1, ti1, ni2, ti2)
                    if collision.type1 == collision.type2 then 
                        b:postSolve(a, contact, ni1, ti1, ni2, ti2)
                    end
                end
            end
        end
    end
end

function World:newCircleCollider(x, y, r, settings)
    return self.wf.Collider.new(self, 'Circle', x, y, r, settings)
end

function World:newRectangleCollider(x, y, w, h, settings)
    return self.wf.Collider.new(self, 'Rectangle', x, y, w, h, settings)
end

function World:newBSGRectangleCollider(x, y, w, h, corner_cut_size, settings)
    return self.wf.Collider.new(self, 'BSGRectangle', x, y, w, h, corner_cut_size, settings)
end

function World:newPolygonCollider(vertices, settings)
    return self.wf.Collider.new(self, 'Polygon', vertices, settings)
end

function World:newLineCollider(x1, y1, x2, y2, settings)
    return self.wf.Collider.new(self, 'Line', x1, y1, x2, y2, settings)
end

function World:newChainCollider(vertices, loop, settings)
    return self.wf.Collider.new(self, 'Chain', vertices, loop, settings)
end

-- Internal AABB box2d query used before going for more specific and precise computations.
function World:_queryBoundingBox(x1, y1, x2, y2)
    self.box2d_world:queryBoundingBox(x1, y1, x2, y2, self.query_callback)
    return self.query_results
end

local all_collision_classes = {'All'}

local function clear(list)
    for i = #list, 1, -1 do list[i] = nil end
end

-- Returns a set of allowed class names, or nil when every class is allowed.
function World:_collisionClassFilter(collision_classes)
    if collision_classes[1] == 'All' then
        if not collision_classes.except then return nil end
        local allowed = {}
        for class, _ in pairs(self.collision_classes) do allowed[class] = true end
        for _, class in ipairs(collision_classes.except) do allowed[class] = nil end
        return allowed
    end
    local allowed = {}
    for _, class in ipairs(collision_classes) do allowed[class] = true end
    return allowed
end

function World:collisionClassInCollisionClassesList(collision_class, collision_classes)
    if collision_classes[1] == 'All' then
        local all_collision_classes = {}
        for class, _ in pairs(self.collision_classes) do
            table.insert(all_collision_classes, class)
        end
        if collision_classes.except then
            for _, except in ipairs(collision_classes.except) do
                for i, class in ipairs(all_collision_classes) do
                    if class == except then 
                        table.remove(all_collision_classes, i)
                        break
                    end
                end
            end
        end
        for _, class in ipairs(all_collision_classes) do
            if class == collision_class then return true end
        end
    else
        for _, class in ipairs(collision_classes) do
            if class == collision_class then return true end
        end
    end
end

-- CircleShape has no getPoints, so circles are tested by center and radius.
local function fixtureCircle(body, fixture)
    local shape = fixture:getShape()
    if shape:type() ~= 'CircleShape' then return end
    local x, y = body:getWorldPoint(shape:getPoint())
    return x, y, shape:getRadius()
end

function World:queryCircleArea(x, y, radius, collision_class_names)
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'circle', x = x, y = y, r = radius, frames = self.draw_query_for_n_frames}) end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local polygon = self.wf.Math.polygon
    local colliders = self:_queryBoundingBox(x-radius, y-radius, x+radius, y+radius)
    local outs = {}
    for i = 1, #colliders do
        local collider = colliders[i]
        if not allowed or allowed[collider.collision_class] then
            for _, fixture in pairs(collider.fixtures) do
                local cx, cy, cr = fixtureCircle(collider.body, fixture)
                local hit
                if cx then
                    hit = (x - cx)^2 + (y - cy)^2 <= (radius + cr)^2
                else
                    hit = polygon.getCircleIntersection(x, y, radius, {collider.body:getWorldPoints(fixture:getShape():getPoints())})
                end
                if hit then
                    outs[#outs + 1] = collider
                    break
                end
            end
        end
    end
    clear(colliders)
    return outs
end

-- rect is {x1, y1, x2, y2} for axis aligned queries: a shape whose bounding box lies strictly inside it is a hit, and one whose bounding box is strictly apart from it is a miss, without the exact test.
function World:_polygonQueryHit(vertices, body, fixture, rect)
    local shape = fixture:getShape()
    local shape_type = shape:type()
    if rect and shape_type ~= 'ChainShape' then
        local x1, y1, x2, y2 = fixture:getBoundingBox(1)
        if x2 < rect[1] or x1 > rect[3] or y2 < rect[2] or y1 > rect[4] then return false end
        if x1 > rect[1] and y1 > rect[2] and x2 < rect[3] and y2 < rect[4] then return true end
    end
    local polygon = self.wf.Math.polygon
    if shape_type == 'CircleShape' then
        local cx, cy = body:getWorldPoint(shape:getPoint())
        local cr = shape:getRadius()
        return polygon.isCircleInside(cx, cy, cr, vertices) or polygon.getCircleIntersection(cx, cy, cr, vertices)
    end
    return polygon.isPolygonInside(vertices, {body:getWorldPoints(shape:getPoints())})
end

function World:queryRectangleArea(x, y, w, h, collision_class_names)
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'rectangle', x = x, y = y, w = w, h = h, frames = self.draw_query_for_n_frames}) end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local vertices = {x, y, x+w, y, x+w, y+h, x, y+h}
    local rect = (w > 0 and h > 0) and {x, y, x+w, y+h} or nil
    local colliders = self:_queryBoundingBox(x, y, x+w, y+h)
    local outs = {}
    for i = 1, #colliders do
        local collider = colliders[i]
        if not allowed or allowed[collider.collision_class] then
            for _, fixture in pairs(collider.fixtures) do
                if self:_polygonQueryHit(vertices, collider.body, fixture, rect) then
                    outs[#outs + 1] = collider
                    break
                end
            end
        end
    end
    clear(colliders)
    return outs
end

function World:queryPolygonArea(vertices, collision_class_names)
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'polygon', vertices = vertices, frames = self.draw_query_for_n_frames}) end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local cx, cy = self.wf.Math.polygon.getCentroid(vertices)
    local d_max = 0
    for i = 1, #vertices, 2 do
        local d = self.wf.Math.line.getLength(cx, cy, vertices[i], vertices[i+1])
        if d > d_max then d_max = d end
    end
    local colliders = self:_queryBoundingBox(cx-d_max, cy-d_max, cx+d_max, cy+d_max)
    local outs = {}
    for i = 1, #colliders do
        local collider = colliders[i]
        if not allowed or allowed[collider.collision_class] then
            for _, fixture in pairs(collider.fixtures) do
                if self:_polygonQueryHit(vertices, collider.body, fixture) then
                    outs[#outs + 1] = collider
                    break
                end
            end
        end
    end
    clear(colliders)
    return outs
end

function World:queryLine(x1, y1, x2, y2, collision_class_names)
    if self.query_debug_drawing_enabled then 
        table.insert(self.query_debug_draw, {type = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, frames = self.draw_query_for_n_frames}) 
    end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    self.box2d_world:rayCast(x1, y1, x2, y2, self.ray_callback)

    local colliders = self.query_results
    local outs = {}
    for i = 1, #colliders do
        local collider = colliders[i]
        if not allowed or allowed[collider.collision_class] then
            outs[#outs + 1] = collider
        end
    end
    clear(colliders)
    return outs
end

function World:queryPoint(x, y, collision_class_names)
    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local found, outs = {}, {}
    self.box2d_world:queryBoundingBox(x, y, x, y, function(fixture)
        local collider = fixture:getUserData()
        if collider and not found[collider] and not collider.destroy_pending and not fixture:isSensor()
            and (not allowed or allowed[collider.collision_class]) and fixture:testPoint(x, y) then
            found[collider] = true
            outs[#outs + 1] = collider
        end
        return true
    end)
    return outs
end

function World:getColliderAt(x, y, collision_class_names)
    return self:queryPoint(x, y, collision_class_names)[1]
end

local function newQueryShape(shape_def)
    if type(shape_def) ~= 'table' then error('The query shape must be a table such as {type = "circle", radius = 10}.', 4) end
    local kind = shape_def.type
    if kind == 'circle' then
        if type(shape_def.radius) ~= 'number' then error('A circle query shape needs a numeric radius.', 4) end
        return love.physics.newCircleShape(shape_def.radius)
    elseif kind == 'rectangle' then
        if type(shape_def.w) ~= 'number' or type(shape_def.h) ~= 'number' then error('A rectangle query shape needs numeric w and h.', 4) end
        return love.physics.newRectangleShape(shape_def.w, shape_def.h)
    elseif kind == 'polygon' then
        if type(shape_def.vertices) ~= 'table' then error('A polygon query shape needs a vertices table.', 4) end
        return love.physics.newPolygonShape(unpack(shape_def.vertices))
    elseif kind == 'edge' then
        return love.physics.newEdgeShape(shape_def.x1, shape_def.y1, shape_def.x2, shape_def.y2)
    end
    error('Unknown query shape type ' .. tostring(kind) .. '.', 4)
end

-- getDistance only looks at the first child of a chain, so a chain is tested one edge at a time.
local function chainOverlaps(world, query_fixture, fixture, qx1, qy1, qx2, qy2)
    local shape, body = fixture:getShape(), fixture:getBody()
    local chain_body = world.query_chain_body
    chain_body:setPosition(body:getPosition())
    chain_body:setAngle(body:getAngle())
    for child = 1, shape:getChildCount() do
        local x1, y1, x2, y2 = fixture:getBoundingBox(child)
        if x2 >= qx1 and x1 <= qx2 and y2 >= qy1 and y1 <= qy2 then
            local edge_fixture = love.physics.newFixture(chain_body, shape:getChildEdge(child))
            local distance = love.physics.getDistance(query_fixture, edge_fixture)
            edge_fixture:destroy()
            if distance <= 0 then return true end
        end
    end
    return false
end

local function newQueryFixture(world, shape_def, x, y)
    local shape = newQueryShape(shape_def)
    if not world.query_world then
        world.query_world = love.physics.newWorld(0, 0, false)
        world.query_body = love.physics.newBody(world.query_world, 0, 0, 'static')
        world.query_chain_body = love.physics.newBody(world.query_world, 0, 0, 'static')
    end
    local body = world.query_body
    body:setPosition(x, y)
    body:setAngle(shape_def.angle or 0)
    return love.physics.newFixture(body, shape)
end

function World:queryShape(shape_def, x, y, collision_class_names)
    local query_fixture = newQueryFixture(self, shape_def, x, y)
    local qx1, qy1, qx2, qy2 = query_fixture:getBoundingBox(1)
    if self.query_debug_drawing_enabled then
        table.insert(self.query_debug_draw, {type = 'rectangle', x = qx1, y = qy1, w = qx2 - qx1, h = qy2 - qy1, frames = self.draw_query_for_n_frames})
    end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local found, outs = {}, {}
    self.box2d_world:queryBoundingBox(qx1, qy1, qx2, qy2, function(fixture)
        local collider = fixture:getUserData()
        if collider and not found[collider] and not collider.destroy_pending and not fixture:isSensor()
            and (not allowed or allowed[collider.collision_class]) then
            local hit
            if fixture:getShape():type() == 'ChainShape' then
                hit = chainOverlaps(self, query_fixture, fixture, qx1, qy1, qx2, qy2)
            else
                hit = love.physics.getDistance(query_fixture, fixture) <= 0
            end
            if hit then
                found[collider] = true
                outs[#outs + 1] = collider
            end
        end
        return true
    end)
    query_fixture:destroy()
    return outs
end

local shape_cast_iterations = 32
local shape_cast_tolerance = 1e-3

-- Conservative advancement: the nearest points define a plane that separates two convex shapes, so the
-- moving shape cannot touch the other one before it travels the gap divided by the cosine to that plane.
local function advanceToHit(body, query_fixture, x, y, dx, dy, length, ux, uy, test_fixture, limit)
    local t = 0
    local nx, ny
    for _ = 1, shape_cast_iterations do
        body:setPosition(x + dx * t, y + dy * t)
        local distance, x1, y1, x2, y2 = love.physics.getDistance(query_fixture, test_fixture)
        if distance <= shape_cast_tolerance then
            -- Near contact the two points collapse and float noise decides their direction, so the normal comes from the last clear step.
            if not nx then
                nx, ny = x1 - x2, y1 - y2
                local normal_length = math.sqrt(nx * nx + ny * ny)
                if normal_length > 0.05 then nx, ny = nx / normal_length, ny / normal_length
                else nx, ny = -ux, -uy end
            end
            return t, nx, ny, x2, y2
        end
        local sx, sy = x2 - x1, y2 - y1
        local separation = math.sqrt(sx * sx + sy * sy)
        nx, ny = -sx / separation, -sy / separation
        local rate = (ux * sx + uy * sy) / separation
        if rate <= 1e-6 then return nil end
        t = t + distance / (rate * length)
        if t > 1 or t >= limit then return nil end
    end
    return nil
end

function World:shapeCast(shape_def, x, y, dx, dy, collision_class_names)
    if type(dx) ~= 'number' or type(dy) ~= 'number' then error('shapeCast needs a numeric movement dx, dy.') end
    local query_fixture = newQueryFixture(self, shape_def, x, y)
    local body = self.query_body
    local length = math.sqrt(dx * dx + dy * dy)
    local ux, uy = 0, 0
    if length > 0 then ux, uy = dx / length, dy / length end

    local sx1, sy1, sx2, sy2 = query_fixture:getBoundingBox(1)
    body:setPosition(x + dx, y + dy)
    local ex1, ey1, ex2, ey2 = query_fixture:getBoundingBox(1)
    local qx1, qy1 = math.min(sx1, ex1), math.min(sy1, ey1)
    local qx2, qy2 = math.max(sx2, ex2), math.max(sy2, ey2)
    if self.query_debug_drawing_enabled then
        table.insert(self.query_debug_draw, {type = 'line', x1 = x, y1 = y, x2 = x + dx, y2 = y + dy, frames = self.draw_query_for_n_frames})
    end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local candidates = {}
    self.box2d_world:queryBoundingBox(qx1, qy1, qx2, qy2, function(fixture)
        local collider = fixture:getUserData()
        if collider and not collider.destroy_pending and not fixture:isSensor()
            and (not allowed or allowed[collider.collision_class]) then
            candidates[#candidates + 1] = fixture
        end
        return true
    end)

    local best_t, best
    local function consider(test_fixture, collider)
        local t, nx, ny, px, py = advanceToHit(body, query_fixture, x, y, dx, dy, length, ux, uy, test_fixture, best_t or math.huge)
        if t then
            best_t = t
            best = {collider = collider, fraction = t, x = px, y = py, nx = nx, ny = ny}
            if t == 0 then best.overlap = true end
        end
    end
    for _, fixture in ipairs(candidates) do
        local collider = fixture:getUserData()
        if fixture:getShape():type() == 'ChainShape' then
            local shape, chain_body = fixture:getShape(), self.query_chain_body
            local fixture_body = fixture:getBody()
            chain_body:setPosition(fixture_body:getPosition())
            chain_body:setAngle(fixture_body:getAngle())
            for child = 1, shape:getChildCount() do
                local cx1, cy1, cx2, cy2 = fixture:getBoundingBox(child)
                if cx2 >= qx1 and cx1 <= qx2 and cy2 >= qy1 and cy1 <= qy2 then
                    local edge_fixture = love.physics.newFixture(chain_body, shape:getChildEdge(child))
                    consider(edge_fixture, collider)
                    edge_fixture:destroy()
                end
            end
        else
            consider(fixture, collider)
        end
    end
    query_fixture:destroy()
    return best
end

function World:raycast(x1, y1, x2, y2, collision_class_names, mode)
    mode = mode or 'all'
    if mode ~= 'all' and mode ~= 'closest' then error("Unknown raycast mode " .. tostring(mode) .. ".") end
    if self.query_debug_drawing_enabled then
        table.insert(self.query_debug_draw, {type = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, frames = self.draw_query_for_n_frames})
    end

    local allowed = self:_collisionClassFilter(collision_class_names or all_collision_classes)
    local closest = mode == 'closest'
    local hits = {}
    self.box2d_world:rayCast(x1, y1, x2, y2, function(fixture, x, y, nx, ny, fraction)
        local collider = fixture:getUserData()
        if not collider or collider.destroy_pending or fixture:isSensor()
            or (allowed and not allowed[collider.collision_class]) then
            return -1
        end
        local hit = {collider = collider, x = x, y = y, nx = nx, ny = ny, fraction = fraction}
        if closest then
            hits[1] = hit
            return fraction
        end
        hits[#hits + 1] = hit
        return 1
    end)

    if closest then return hits[1] end
    table.sort(hits, function(a, b) return a.fraction < b.fraction end)
    return hits
end

function World:addJoint(joint_type, ...)
    local args = {...}
    if args[1].body then args[1] = args[1].body end
    if type(args[2]) == "table" and args[2].body then args[2] = args[2].body end
    local joint = love.physics['new' .. joint_type](unpack(args))
    return joint
end

function World:removeJoint(joint)
    joint:destroy()
end

function World:destroy()
    local bodies = self.box2d_world:getBodies()
    for _, body in ipairs(bodies) do
        local collider = body:getFixtures()[1]:getUserData()
        collider:destroy()
    end
    local joints = self.box2d_world:getJoints()
    for _, joint in ipairs(joints) do joint:destroy() end
    if self.query_world then self.query_world:destroy() end
    self.box2d_world:destroy()
    self.box2d_world = nil
end



local Collider = {}
local collider_metatables = {}

local generator = love.math.newRandomGenerator(os.time())
local function UUID()
    local fn = function(x)
        local r = generator:random(16) - 1
        r = (x == "x") and (r + 1) or (r % 4) + 9
        return ("0123456789abcdef"):sub(r, r)
    end
    return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", fn))
end

local body_settings = {
    bullet = 'setBullet', fixed_rotation = 'setFixedRotation', gravity_scale = 'setGravityScale',
    linear_damping = 'setLinearDamping', angular_damping = 'setAngularDamping',
    sleeping_allowed = 'setSleepingAllowed', active = 'setActive', angle = 'setAngle',
}
local fixture_settings = {restitution = 'setRestitution', friction = 'setFriction', density = 'setDensity'}

local function checkSettings(settings)
    if not settings then return end
    for key in pairs(settings) do
        if key ~= 'collision_class' and key ~= 'body_type' and key ~= 'object' and key ~= 'sensor'
            and not body_settings[key] and not fixture_settings[key] then
            error('Unknown collider setting ' .. tostring(key) .. '.', 3)
        end
    end
end

local function applySettings(body, fixture, settings)
    if not settings then return end
    for key, method in pairs(body_settings) do
        if settings[key] ~= nil then body[method](body, settings[key]) end
    end
    for key, method in pairs(fixture_settings) do
        if settings[key] ~= nil then fixture[method](fixture, settings[key]) end
    end
    if settings.density ~= nil then body:resetMassData() end
end

local all_categories = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}

local function applyMask(collider, fixture)
    local mask = collider.world.masks[collider.collision_class]
    if mask then
        fixture:setCategory(unpack(mask.categories))
        fixture:setMask(unpack(collider.sensor_mode and all_categories or mask.masks))
    elseif collider.sensor_mode then
        fixture:setMask(unpack(all_categories))
    end
end

function Collider.new(world, collider_type, ...)
    local self = {}
    self.id = UUID()
    self.world = world
    self.type = collider_type
    self.object = nil

    self.shapes = {}
    self.fixtures = {}
    self.sensors = {}

    self.collision_events = {}
    self.has_events = false
    self.collision_stay = {}
    self.enter_collision_data = {}
    self.exit_collision_data = {}
    self.stay_collision_data = {}

    local args = {...}
    local shape, fixture, x, y, settings
    if self.type == 'Circle' then
        x, y, settings = args[1], args[2], args[4]
        shape = love.physics.newCircleShape(args[3])

    elseif self.type == 'Rectangle' then
        x, y, settings = args[1] + args[3]/2, args[2] + args[4]/2, args[5]
        shape = love.physics.newRectangleShape(args[3], args[4])

    elseif self.type == 'BSGRectangle' then
        x, y, settings = args[1] + args[3]/2, args[2] + args[4]/2, args[6]
        local w, h, s = args[3], args[4], args[5]
        shape = love.physics.newPolygonShape({
            -w/2, -h/2 + s, -w/2 + s, -h/2,
             w/2 - s, -h/2, w/2, -h/2 + s,
             w/2, h/2 - s, w/2 - s, h/2,
            -w/2 + s, h/2, -w/2, h/2 - s
        })

    elseif self.type == 'Polygon' then
        x, y, settings = 0, 0, args[2]
        shape = love.physics.newPolygonShape(unpack(args[1]))

    elseif self.type == 'Line' then
        x, y, settings = 0, 0, args[5]
        shape = love.physics.newEdgeShape(args[1], args[2], args[3], args[4])

    elseif self.type == 'Chain' then
        x, y, settings = 0, 0, args[3]
        shape = love.physics.newChainShape(args[2], unpack(args[1]))
    end

    checkSettings(settings)
    self.collision_class = (settings and settings.collision_class) or 'Default'
    self.body = love.physics.newBody(self.world.box2d_world, x, y, (settings and settings.body_type) or 'dynamic')

    -- Define collision classes and attach them to fixture and sensor
    fixture = love.physics.newFixture(self.body, shape)
    self.sensor_mode = (settings and settings.sensor) or nil
    applyMask(self, fixture)
    fixture:setUserData(self)
    local sensor = love.physics.newFixture(self.body, shape)
    sensor:setSensor(true)
    sensor:setUserData(self)

    applySettings(self.body, fixture, settings)
    self.object = settings and settings.object

    self.shapes['main'] = shape
    self.fixtures['main'] = fixture
    self.sensors['main'] = sensor
    self.shape = shape
    self.fixture = fixture
    
    self.preSolve = function() end
    self.postSolve = function() end

    local shape_type = shape:type()
    if not collider_metatables[shape_type] then
        collider_metatables[shape_type] = {__index = newProxyIndex(Collider, {
            {field = 'shape', methods = shape.__index},
            {field = 'fixture', methods = fixture.__index},
            {field = 'body', methods = self.body.__index},
        })}
    end

    return setmetatable(self, collider_metatables[shape_type])
end

function Collider:collisionEventsClear()
    self.collision_events = {}
    self.has_events = false
end

function Collider:setCollisionClass(collision_class_name)
    if not self.world.collision_classes[collision_class_name] then error("Collision class " .. collision_class_name .. " doesn't exist.") end
    self.collision_class = collision_class_name
    for _, fixture in pairs(self.fixtures) do applyMask(self, fixture) end
end

function Collider:setSensor(sensor)
    self.sensor_mode = sensor and true or nil
    for _, fixture in pairs(self.fixtures) do applyMask(self, fixture) end
end

function Collider:isSensor()
    return self.sensor_mode == true or self.world.collision_classes[self.collision_class].sensor == true
end

function Collider:enter(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1  then
        for _, e in ipairs(events) do
            if e.collision_type == 'enter' then
                self.enter_collision_data[other_collision_class_name] = collisionData(e)
                return true
            end
        end
    end
end

function Collider:getEnterCollisionData(other_collision_class_name)
    return self.enter_collision_data[other_collision_class_name]
end

function Collider:exit(other_collision_class_name)
    local events = self.collision_events[other_collision_class_name]
    if events and #events >= 1  then
        for _, e in ipairs(events) do
            if e.collision_type == 'exit' then
                self.exit_collision_data[other_collision_class_name] = collisionData(e)
                return true 
            end
        end
    end
end

function Collider:getExitCollisionData(other_collision_class_name)
    return self.exit_collision_data[other_collision_class_name]
end

-- Colliders destroyed while touching never send an exit event, so they are dropped here.
local function liveStay(collider, other_collision_class_name)
    local list = collider.collision_stay and collider.collision_stay[other_collision_class_name]
    if not list then return end
    for i = #list, 1, -1 do
        if not list[i].collider.body then table.remove(list, i) end
    end
    return list
end

function Collider:stay(other_collision_class_name)
    local list = liveStay(self, other_collision_class_name)
    if list and #list >= 1 then return true end
end

function Collider:getStayCollisionData(other_collision_class_name)
    return liveStay(self, other_collision_class_name)
end

local function collectEvents(collider, other_collision_class_name, collision_type)
    local out = {}
    local events = collider.collision_events[other_collision_class_name]
    if events then
        for _, e in ipairs(events) do
            if e.collision_type == collision_type then out[#out + 1] = collisionData(e) end
        end
    end
    return out
end

function Collider:onEnter(other_collision_class_name, fn)
    return self.world:_addCollisionHandler('enter', self.collision_class, other_collision_class_name, fn, self)
end

function Collider:onExit(other_collision_class_name, fn)
    return self.world:_addCollisionHandler('exit', self.collision_class, other_collision_class_name, fn, self)
end

function Collider:setDrawOrder(order)
    self.draw_order = order
    self.world.has_draw_order = true
end

function Collider:getDrawOrder()
    return self.draw_order or 0
end

function Collider:getEnters(other_collision_class_name)
    return collectEvents(self, other_collision_class_name, 'enter')
end

function Collider:getExits(other_collision_class_name)
    return collectEvents(self, other_collision_class_name, 'exit')
end

function Collider:setPreSolve(callback)
    self.preSolve = callback
end

function Collider:setPostSolve(callback)
    self.postSolve = callback
end

function Collider:setObject(object)
    self.object = object 
end

function Collider:getObject()
    return self.object
end

function Collider:addShape(shape_name, shape_type, ...)
    if self.shapes[shape_name] or self.fixtures[shape_name] then error("Shape/fixture " .. shape_name .. " already exists.") end
    local args = {...}
    local shape = love.physics['new' .. shape_type](unpack(args))
    local fixture = love.physics.newFixture(self.body, shape)
    applyMask(self, fixture)
    fixture:setUserData(self)
    local sensor = love.physics.newFixture(self.body, shape)
    sensor:setSensor(true)
    sensor:setUserData(self)

    self.shapes[shape_name] = shape
    self.fixtures[shape_name] = fixture
    self.sensors[shape_name] = sensor
end

function Collider:removeShape(shape_name)
    if not self.shapes[shape_name] then return end
    self.shapes[shape_name] = nil
    self.fixtures[shape_name]:setUserData(nil)
    self.fixtures[shape_name]:destroy()
    self.fixtures[shape_name] = nil
    self.sensors[shape_name]:setUserData(nil)
    self.sensors[shape_name]:destroy()
    self.sensors[shape_name] = nil
end

function Collider:_snapshot()
    self.prev_x, self.prev_y = self.body:getPosition()
    self.prev_angle = self.body:getAngle()
end

function Collider:setInterpolated(interpolated)
    if interpolated then
        self:_snapshot()
        self.world.interpolated[self] = true
    else
        self.world.interpolated[self] = nil
    end
end

function Collider:isInterpolated()
    return self.world.interpolated[self] == true
end

function Collider:getRenderPosition()
    local x, y = self.body:getPosition()
    if not self.world.interpolated[self] then return x, y end
    local alpha = self.world:getAlpha()
    return self.prev_x + (x - self.prev_x) * alpha, self.prev_y + (y - self.prev_y) * alpha
end

function Collider:getRenderAngle()
    local angle = self.body:getAngle()
    if not self.world.interpolated[self] then return angle end
    return self.prev_angle + (angle - self.prev_angle) * self.world:getAlpha()
end

-- Box2D forbids changing the world during a step, so destroying from a collision callback waits for the step to end.
function Collider:destroy()
    if not self.body or self.destroy_pending then return end
    local world = self.world
    if world.stepping then
        self.destroy_pending = true
        table.insert(world.destroy_queue, self)
        return
    end
    self:_destroy()
end

function Collider:_destroy()
    local world = self.world
    world.interpolated[self] = nil
    local handlers = world.collision_handlers
    for i = #handlers, 1, -1 do
        if handlers[i].collider == self then
            handlers[i].removed = true
            table.remove(handlers, i)
        end
    end
    world.has_collision_handlers = #handlers > 0
    self.collision_stay = nil
    self.enter_collision_data = nil
    self.exit_collision_data = nil
    self:collisionEventsClear()

    self:setObject(nil)
    for name, _ in pairs(self.fixtures) do
        self.shapes[name] = nil
        self.fixtures[name]:setUserData(nil)
        self.fixtures[name] = nil
        self.sensors[name]:setUserData(nil)
        self.sensors[name] = nil
    end
    self.body:destroy()
    self.body = nil
end

wf.World = World
wf.Collider = Collider

return wf

