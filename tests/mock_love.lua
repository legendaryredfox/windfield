-- Minimal stand-in for the parts of LÖVE 11.5 that windfield calls. It does not
-- simulate physics: tests fire contact callbacks by hand with `love._fire`.
local unpack = table.unpack or unpack

local function class(name, methods)
    methods.__index = methods
    methods.type = function() return name end
    methods.typeOf = function(_, t) return t == name end
    return function(object) return setmetatable(object, methods) end
end

local function recorders(names)
    local methods = {}
    for _, name in ipairs(names) do
        methods[name] = function(self, ...)
            self.calls = self.calls or {}
            self.calls[name] = {...}
        end
    end
    return methods
end

local function merge(target, source)
    for k, v in pairs(source) do target[k] = v end
    return target
end

local function worldPoints(body, ...)
    local points, out = {...}, {}
    for i = 1, #points, 2 do
        out[#out + 1] = points[i] + body.x
        out[#out + 1] = points[i + 1] + body.y
    end
    return unpack(out)
end

local function remove(list, item)
    for i = #list, 1, -1 do
        if list[i] == item then table.remove(list, i) end
    end
end

local function install()
    local love = {physics = {}, math = {}, graphics = {}, _colors = {}}

    local newWorldObject = class('World', {
        setCallbacks = function(self, ...) self.callbacks = {...} end,
        update = function(self)
            self.locked = true
            local ok, err = pcall(function() if self.step_hook then self.step_hook() end end)
            self.locked = false
            if not ok then error(err, 0) end
        end,
        getBodies = function(self) return self.bodies end,
        getJoints = function(self) return self.joints end,
        setGravity = function(self, x, y) self.gx, self.gy = x, y end,
        getGravity = function(self) return self.gx, self.gy end,
        queryBoundingBox = function(self, _, _, _, _, callback)
            for _, body in ipairs(self.bodies) do
                for _, fixture in ipairs(body.fixtures) do callback(fixture) end
            end
        end,
        rayCast = function(self, _, _, _, _, callback)
            local max_fraction = 1
            for _, body in ipairs(self.bodies) do
                for _, fixture in ipairs(body.fixtures) do
                    local hit = fixture.ray or {}
                    local fraction = hit.fraction or 0
                    if fraction <= max_fraction then
                        local result = callback(fixture, hit.x or 0, hit.y or 0, hit.xn or 0, hit.yn or 0, fraction)
                        if result == 0 then return end
                        if result >= 0 and result < max_fraction then max_fraction = result end
                    end
                end
            end
        end,
        destroy = function(self) self.destroyed = true end,
    })

    local body_methods = recorders({'setBullet', 'setFixedRotation', 'setGravityScale', 'setLinearDamping',
        'setAngularDamping', 'setSleepingAllowed', 'setActive', 'setAngle', 'resetMassData'})
    local fixture_methods = recorders({'setRestitution', 'setFriction', 'setDensity'})

    local newBodyObject = class('Body', merge({
        getPosition = function(self) return self.x, self.y end,
        getAngle = function(self) return self.angle or 0 end,
        setPosition = function(self, x, y) self.x, self.y = x, y end,
        getFixtures = function(self) return self.fixtures end,
        getWorldPoints = worldPoints,
        probe = function() return 'body' end,
        probeFixtureBody = function() return 'body' end,
        getWorldPoint = function(self, x, y) return x + self.x, y + self.y end,
        setLinearVelocity = function(self, x, y) self.vx, self.vy = x, y end,
        getLinearVelocity = function(self) return self.vx or 0, self.vy or 0 end,
        destroy = function(self)
            if self.world.locked then error('Box2D world is locked', 2) end
            remove(self.world.bodies, self)
            self.destroyed = true
        end,
    }, body_methods))

    local newFixtureObject = class('Fixture', merge({
        probe = function() return 'fixture' end,
        probeFixtureBody = function() return 'fixture' end,
        setCategory = function(self, ...) self.category = {...} end,
        setMask = function(self, ...) self.mask = {...} end,
        setUserData = function(self, data) self.data = data end,
        getUserData = function(self) return self.data end,
        setSensor = function(self, value) self.sensor = value end,
        isSensor = function(self) return self.sensor == true end,
        getShape = function(self) return self.shape end,
        getBody = function(self) return self.body end,
        testPoint = function(self, x, y)
            local shape, body = self.shape, self.body
            if shape.radius then
                return (x - body.x) ^ 2 + (y - body.y) ^ 2 <= shape.radius ^ 2
            end
            local x1, y1, x2, y2 = self:getBoundingBox()
            return x >= x1 and x <= x2 and y >= y1 and y <= y2
        end,
        getBoundingBox = function(self)
            local shape, body = self.shape, self.body
            if shape.radius then
                return body.x - shape.radius, body.y - shape.radius, body.x + shape.radius, body.y + shape.radius
            end
            local points = shape.points
            local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
            for i = 1, #points, 2 do
                x1, x2 = math.min(x1, points[i] + body.x), math.max(x2, points[i] + body.x)
                y1, y2 = math.min(y1, points[i + 1] + body.y), math.max(y2, points[i + 1] + body.y)
            end
            return x1, y1, x2, y2
        end,
        destroy = function(self) remove(self.body.fixtures, self) end,
    }, fixture_methods))

    local polygonMethods = {
        getPoints = function(self) return unpack(self.points) end,
        probe = function() return 'shape' end,
    }
    local newPolygon = class('PolygonShape', polygonMethods)
    local newEdge = class('EdgeShape', {getPoints = polygonMethods.getPoints, probe = polygonMethods.probe})
    local newChain = class('ChainShape', {getPoints = polygonMethods.getPoints, probe = polygonMethods.probe})
    local newCircle = class('CircleShape', {
        probe = polygonMethods.probe,
        getRadius = function(self) return self.radius end,
        getPoint = function() return 0, 0 end,
    })

    local newJointObject = class('Joint', {
        getAnchors = function(self) return self.x1, self.y1, self.x2, self.y2 end,
        destroy = function(self)
            remove(self.world.joints, self)
            self.destroyed = true
        end,
    })

    local newGenerator = class('RandomGenerator', {
        random = function(_, n) return math.random(n) end,
    })

    local meter = 30
    love.physics.meter_calls = 0
    function love.physics.setMeter(m)
        meter = m
        love.physics.meter_calls = love.physics.meter_calls + 1
    end
    function love.physics.getMeter() return meter end

    function love.physics.newWorld(xg, yg)
        return newWorldObject({gx = xg, gy = yg, bodies = {}, joints = {}})
    end

    function love.physics.newBody(world, x, y, body_type)
        local body = newBodyObject({world = world, x = x, y = y, body_type = body_type, fixtures = {}})
        world.bodies[#world.bodies + 1] = body
        return body
    end

    function love.physics.newFixture(body, shape)
        local fixture = newFixtureObject({body = body, shape = shape})
        body.fixtures[#body.fixtures + 1] = fixture
        return fixture
    end

    function love.physics.newCircleShape(radius) return newCircle({radius = radius}) end
    function love.physics.newPolygonShape(...) return newPolygon({points = {...}}) end
    function love.physics.newEdgeShape(...) return newEdge({points = {...}}) end

    function love.physics.newChainShape(loop, ...)
        if type(loop) ~= 'boolean' then
            error('bad argument #1 to newChainShape (boolean expected, got ' .. type(loop) .. ')', 2)
        end
        return newChain({loop = loop, points = {...}})
    end

    function love.physics.newRectangleShape(w, h)
        return newPolygon({points = {-w / 2, -h / 2, w / 2, -h / 2, w / 2, h / 2, -w / 2, h / 2}})
    end

    function love.physics.newMouseJoint(body, x, y)
        local joint = newJointObject({world = body.world, x1 = x, y1 = y})
        body.world.joints[#body.world.joints + 1] = joint
        return joint
    end

    function love.math.newRandomGenerator() return newGenerator({}) end

    function love.math.triangulate(vertices)
        return {{unpack(vertices, 1, 6)}}
    end

    function love.graphics.getColor() return 1, 1, 1, 1 end
    function love.graphics.setColor(...)
        local color = {...}
        if type(color[1]) == 'table' then color = color[1] end
        love._colors[#love._colors + 1] = color
    end
    function love.graphics.polygon() end
    function love.graphics.line() end
    function love.graphics.circle() end
    function love.graphics.rectangle() end

    local newContact = class('Contact', {
        getNormal = function(self)
            if self.destroyed then error('Attempt to use destroyed contact.', 2) end
            return self.nx, self.ny
        end,
        getPositions = function(self)
            if self.destroyed then error('Attempt to use destroyed contact.', 2) end
            return unpack(self.positions)
        end,
    })

    -- Calls the callback registered with World:setCallbacks and returns the
    -- contact it passed. kind: 'enter', 'exit', 'pre' or 'post'.
    function love._fire(world, kind, fixture_a, fixture_b, contact)
        local index = ({enter = 1, exit = 2, pre = 3, post = 4})[kind]
        contact = newContact(contact or {nx = 0, ny = 1, positions = {1, 2}})
        world.box2d_world.callbacks[index](fixture_a, fixture_b, contact)
        return contact
    end

    return love
end

return install
