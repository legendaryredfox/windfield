-- Frozen copy of the area query implementation as it was before the query
-- optimization. tests/run.lua compares the current queries against it.
local ref = {}

function ref._queryBoundingBox(self, x1, y1, x2, y2)
    local colliders = {}
    local callback = function(fixture)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return true
    end
    self.box2d_world:queryBoundingBox(x1, y1, x2, y2, callback)
    return colliders
end

function ref.collisionClassInCollisionClassesList(self, collision_class, collision_classes)
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

function ref.queryCircleArea(self, x, y, radius, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'circle', x = x, y = y, r = radius, frames = self.draw_query_for_n_frames}) end
    
    local colliders = ref._queryBoundingBox(self, x-radius, y-radius, x+radius, y+radius) 
    local outs = {}
    for _, collider in ipairs(colliders) do
        if ref.collisionClassInCollisionClassesList(self, collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                local cx, cy, cr = fixtureCircle(collider.body, fixture)
                local hit
                if cx then
                    hit = (x - cx)^2 + (y - cy)^2 <= (radius + cr)^2
                else
                    hit = self.wf.Math.polygon.getCircleIntersection(x, y, radius, {collider.body:getWorldPoints(fixture:getShape():getPoints())})
                end
                if hit then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function ref._polygonQueryHit(self, vertices, body, fixture)
    local cx, cy, cr = fixtureCircle(body, fixture)
    if cx then
        return self.wf.Math.polygon.isCircleInside(cx, cy, cr, vertices) or self.wf.Math.polygon.getCircleIntersection(cx, cy, cr, vertices)
    end
    return self.wf.Math.polygon.isPolygonInside(vertices, {body:getWorldPoints(fixture:getShape():getPoints())})
end

function ref.queryRectangleArea(self, x, y, w, h, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'rectangle', x = x, y = y, w = w, h = h, frames = self.draw_query_for_n_frames}) end

    local colliders = ref._queryBoundingBox(self, x, y, x+w, y+h) 
    local outs = {}
    for _, collider in ipairs(colliders) do
        if ref.collisionClassInCollisionClassesList(self, collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if ref._polygonQueryHit(self, {x, y, x+w, y, x+w, y+h, x, y+h}, collider.body, fixture) then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function ref.queryPolygonArea(self, vertices, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then table.insert(self.query_debug_draw, {type = 'polygon', vertices = vertices, frames = self.draw_query_for_n_frames}) end

    local cx, cy = self.wf.Math.polygon.getCentroid(vertices)
    local d_max = 0
    for i = 1, #vertices, 2 do
        local d = self.wf.Math.line.getLength(cx, cy, vertices[i], vertices[i+1])
        if d > d_max then d_max = d end
    end
    local colliders = ref._queryBoundingBox(self, cx-d_max, cy-d_max, cx+d_max, cy+d_max)
    local outs = {}
    for _, collider in ipairs(colliders) do
        if ref.collisionClassInCollisionClassesList(self, collider.collision_class, collision_class_names) then
            for _, fixture in ipairs(collider.body:getFixtures()) do
                if ref._polygonQueryHit(self, vertices, collider.body, fixture) then
                    table.insert(outs, collider)
                    break
                end
            end
        end
    end
    return outs
end

function ref.queryLine(self, x1, y1, x2, y2, collision_class_names)
    if not collision_class_names then collision_class_names = {'All'} end
    if self.query_debug_drawing_enabled then 
        table.insert(self.query_debug_draw, {type = 'line', x1 = x1, y1 = y1, x2 = x2, y2 = y2, frames = self.draw_query_for_n_frames}) 
    end

    local colliders = {}
    local callback = function(fixture, ...)
        if not fixture:isSensor() then table.insert(colliders, fixture:getUserData()) end
        return 1
    end
    self.box2d_world:rayCast(x1, y1, x2, y2, callback)

    local outs = {}
    for _, collider in ipairs(colliders) do
        if ref.collisionClassInCollisionClassesList(self, collider.collision_class, collision_class_names) then
            table.insert(outs, collider)
        end
    end
    return outs
end

return ref
