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
        getContacts = function(self) return self.contacts or {} end,
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
        'setAngularDamping', 'setSleepingAllowed', 'setActive', 'setAngle', 'resetMassData', 'setAngularVelocity'})
    local fixture_methods = recorders({'setRestitution', 'setFriction', 'setDensity'})

    local newBodyObject = class('Body', merge({
        getPosition = function(self) return self.x, self.y end,
        getAngle = function(self) return self.angle or 0 end,
        getMass = function(self) return self.mass or 1 end,
        applyForce = function(self, fx, fy)
            self.forces = self.forces or {}
            self.forces[#self.forces + 1] = {fx, fy}
        end,
        getContacts = function(self) return self.contacts or {} end,
        getJoints = function(self) return self.joints end,
        getType = function(self) return self.body_type or 'dynamic' end,
        isAwake = function(self) return not self.asleep end,
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
        getDensity = function(self) return self.density or 1 end,
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
        getChildCount = function() return 1 end,
    }
    local newPolygon = class('PolygonShape', polygonMethods)
    local newEdge = class('EdgeShape', {getPoints = polygonMethods.getPoints, probe = polygonMethods.probe, getChildCount = polygonMethods.getChildCount})
    local newChain = class('ChainShape', {
        getPoints = polygonMethods.getPoints,
        probe = polygonMethods.probe,
        getChildCount = function(self) return #self.points / 2 - 1 + (self.loop and 1 or 0) end,
        getChildEdge = function(self, index)
            local p, count = self.points, #self.points / 2
            local next_index = index % count + 1
            return newEdge({points = {p[2 * index - 1], p[2 * index], p[2 * next_index - 1], p[2 * next_index]}})
        end,
    })
    local newCircle = class('CircleShape', {
        probe = polygonMethods.probe,
        getChildCount = polygonMethods.getChildCount,
        getRadius = function(self) return self.radius end,
        getPoint = function() return 0, 0 end,
    })

    local joint_methods = merge({
        getAnchors = function(self) return self.x1, self.y1, self.x2, self.y2 end,
        isDestroyed = function(self) return self.destroyed == true end,
        destroy = function(self)
            remove(self.world.joints, self)
            for _, body in ipairs(self.bodies) do remove(body.joints, self) end
            self.destroyed = true
        end,
    }, recorders({'setLimits', 'setLimitsEnabled', 'setMotorEnabled', 'setMotorSpeed', 'setMaxMotorTorque',
        'setMaxMotorForce', 'setFrequency', 'setDampingRatio', 'setSpringFrequency', 'setSpringDampingRatio'}))

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

    function love.physics.getDistance(fixture_a, fixture_b)
        local ax1, ay1, ax2, ay2 = fixture_a:getBoundingBox()
        local bx1, by1, bx2, by2 = fixture_b:getBoundingBox()
        local dx = math.max(0, bx1 - ax2, ax1 - bx2)
        local dy = math.max(0, by1 - ay2, ay1 - by2)
        local function nearest(a1, a2, b1, b2)
            if b1 > a2 then return a2, b1 end
            if a1 > b2 then return a1, b2 end
            local middle = (math.max(a1, b1) + math.min(a2, b2)) / 2
            return middle, middle
        end
        local px1, px2 = nearest(ax1, ax2, bx1, bx2)
        local py1, py2 = nearest(ay1, ay2, by1, by2)
        return math.sqrt(dx * dx + dy * dy), px1, py1, px2, py2
    end

    function love.physics.newBody(world, x, y, body_type)
        local body = newBodyObject({world = world, x = x, y = y, body_type = body_type, fixtures = {}, joints = {}})
        world.bodies[#world.bodies + 1] = body
        return body
    end

    function love.physics.newFixture(body, shape)
        local fixture = newFixtureObject({body = body, shape = shape})
        body.fixtures[#body.fixtures + 1] = fixture
        return fixture
    end

    function love.physics.newCircleShape(radius) return newCircle({radius = radius}) end
    function love.physics.newPolygonShape(...)
        local points = {...}
        if #points == 1 and type(points[1]) == 'table' then points = points[1] end
        local count = #points / 2
        if count < 3 or count > 8 then error('Number of vertices must be between 3 and 8', 2) end
        local sign
        for i = 1, count do
            local a, b, c = i, i % count + 1, (i + 1) % count + 1
            local z = (points[2 * b - 1] - points[2 * a - 1]) * (points[2 * c] - points[2 * a])
                - (points[2 * b] - points[2 * a]) * (points[2 * c - 1] - points[2 * a - 1])
            if math.abs(z) > 1e-9 then
                if sign and (z > 0) ~= sign then error('Polygon is not convex', 2) end
                sign = z > 0
            end
        end
        return newPolygon({points = points})
    end
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

    for _, name in ipairs({'DistanceJoint', 'RevoluteJoint', 'PrismaticJoint', 'WeldJoint', 'RopeJoint', 'WheelJoint',
        'FrictionJoint', 'MotorJoint', 'MouseJoint', 'PulleyJoint', 'GearJoint'}) do
        local new = class(name, merge({}, joint_methods))
        love.physics['new' .. name] = function(a, b, ...)
            local args = {...}
            local joint = new({world = a.world, args = {a, b, ...}, bodies = {}})
            if name == 'MouseJoint' then joint.x1, joint.y1 = b, args[1] end
            for _, body in ipairs({a, name ~= 'MouseJoint' and b or false}) do
                if body and body.joints then
                    body.joints[#body.joints + 1] = joint
                    joint.bodies[#joint.bodies + 1] = body
                end
            end
            joint.world.joints[#joint.world.joints + 1] = joint
            return joint
        end
    end

    function love.math.newRandomGenerator() return newGenerator({}) end

    function love.math.triangulate(vertices)
        local count = #vertices / 2
        if count < 3 then error('Need at least 3 vertices to triangulate', 2) end
        local points = {}
        for i = 1, count do points[i] = {vertices[2 * i - 1], vertices[2 * i]} end
        local function cross(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]) end
        local area = 0
        for i = 1, count do area = area + cross(points[1], points[i], points[i % count + 1]) end
        if area < 0 then
            for i = 1, math.floor(count / 2) do points[i], points[count - i + 1] = points[count - i + 1], points[i] end
        end
        local triangles = {}
        while #points > 3 do
            local clipped
            for i = 1, #points do
                local a, b, c = points[(i - 2) % #points + 1], points[i], points[i % #points + 1]
                if cross(a, b, c) > 1e-9 then
                    local empty = true
                    for _, p in ipairs(points) do
                        if p ~= a and p ~= b and p ~= c and cross(a, b, p) >= 0 and cross(b, c, p) >= 0 and cross(c, a, p) >= 0 then empty = false end
                    end
                    if empty then
                        triangles[#triangles + 1] = {a[1], a[2], b[1], b[2], c[1], c[2]}
                        table.remove(points, i)
                        clipped = true
                        break
                    end
                end
            end
            if not clipped then table.remove(points, 1) end
        end
        triangles[#triangles + 1] = {points[1][1], points[1][2], points[2][1], points[2][2], points[3][1], points[3][2]}
        return triangles
    end

    love.graphics.calls = {}
    local line_width = 1
    local function record(name)
        return function(...)
            love.graphics.calls[#love.graphics.calls + 1] = {name = name, ...}
        end
    end
    function love.graphics.getColor() return 1, 1, 1, 1 end
    function love.graphics.setColor(...)
        local color = {...}
        if type(color[1]) == 'table' then color = color[1] end
        love._colors[#love._colors + 1] = color
        love.graphics.calls[#love.graphics.calls + 1] = {name = 'setColor', unpack(color)}
    end
    function love.graphics.getLineWidth() return line_width end
    function love.graphics.setLineWidth(width)
        line_width = width
        love.graphics.calls[#love.graphics.calls + 1] = {name = 'setLineWidth', width}
    end
    love.graphics.polygon = record('polygon')
    love.graphics.line = record('line')
    love.graphics.circle = record('circle')
    love.graphics.rectangle = record('rectangle')

    local newContact = class('Contact', {
        getNormal = function(self)
            if self.destroyed then error('Attempt to use destroyed contact.', 2) end
            return self.nx, self.ny
        end,
        getPositions = function(self)
            if self.destroyed then error('Attempt to use destroyed contact.', 2) end
            return unpack(self.positions)
        end,
        isTouching = function(self) return self.touching ~= false end,
        getFixtures = function(self) return unpack(self.fixtures) end,
        setEnabled = function(self, enabled) self.enabled = enabled end,
        isEnabled = function(self) return self.enabled ~= false end,
        setTangentSpeed = function(self, speed) self.tangent_speed = speed end,
        getTangentSpeed = function(self) return self.tangent_speed or 0 end,
    })

    love._newContact = newContact

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
