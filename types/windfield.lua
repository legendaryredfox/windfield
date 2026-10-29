---@meta windfield

---@class windfield
---@field _VERSION string
---@field Math table MLib, the math and shape intersection library bundled with windfield.
---@field World windfield.World
---@field Collider windfield.Collider
local wf = {}

---@class windfield.WorldOptions
---@field meter? number LÖVE physics meter in pixels per meter. Default 32. Global to LÖVE.

---@param xg number
---@param yg number
---@param sleep? boolean Default true.
---@param options? windfield.WorldOptions
---@return windfield.World
function wf.newWorld(xg, yg, sleep, options) end

---@alias windfield.BodyType 'dynamic'|'static'|'kinematic'

---@class windfield.ColliderSettings
---@field collision_class? string Default 'Default'.
---@field body_type? windfield.BodyType Default 'dynamic'.
---@field bullet? boolean
---@field fixed_rotation? boolean
---@field gravity_scale? number
---@field linear_damping? number
---@field angular_damping? number
---@field sleeping_allowed? boolean
---@field active? boolean
---@field angle? number Initial angle in radians.
---@field restitution? number
---@field friction? number
---@field density? number
---@field sensor? boolean Start as a sensor, same as `Collider:setSensor(true)`.
---@field object? any

---@class windfield.Ignores: string[]
---@field except? string[] Used with 'All': the classes that are not ignored.

---@class windfield.CollisionClass
---@field ignores? windfield.Ignores Classes this class physically ignores. Cannot be combined with `sensor`.
---@field sensor? boolean Pass through every class and still report events. Same as `ignores = {'All'}`.
---@field one_way? number[] `{nx, ny}`: colliders are solid only for bodies on the side this vector points to.
---@field conveyor? number Carry speed in pixels per second.
---@field enter? string[] Classes that generate enter events.
---@field exit? string[] Classes that generate exit events.
---@field pre? string[] Classes that generate pre solve events.
---@field post? string[] Classes that generate post solve events.

---@class windfield.CollisionData
---@field collider windfield.Collider The other collider.
---@field contact love.Contact Only valid during the physics step.
---@field nx number Contact normal x, copied from the contact.
---@field ny number Contact normal y, copied from the contact.
---@field x1? number First contact point x.
---@field y1? number First contact point y.
---@field x2? number Second contact point x.
---@field y2? number Second contact point y.

---@class windfield.Handle
---@field remove fun() Stops the callback from running.

---@class windfield.World: love.World
---@field box2d_world love.World
local World = {}

---@param dt number
function World:update(dt) end

---@param dt number
---@return integer steps Fixed updates that ran.
function World:step(dt) end

---@param dt number Fixed time step, greater than zero. Default 1/60.
---@param max_steps? integer Most updates per `step` call, at least 1. Default 5.
function World:setFixedStep(dt, max_steps) end

---@return number alpha Leftover fraction of a fixed step, from 0 up to but not including 1.
function World:getAlpha() end

---@class windfield.DrawOptions
---@field alpha? number 0 to 255. Default 255.
---@field line_width? number Default 1.
---@field class_colors? table<string, number[]> `{r, g, b}` from 0 to 1 by collision class.
---@field contacts? boolean Contact points and normals.
---@field aabb? boolean Bounding boxes.
---@field velocities? boolean Lines to where each body is a quarter of a second later.
---@field sleeping? boolean Dim the bodies that are asleep.

---@param alpha_or_options? number|windfield.DrawOptions A number is the alpha, 0 to 255.
function World:draw(alpha_or_options) end

---@param value boolean
function World:setQueryDebugDrawing(value) end

---@param value boolean
function World:setExplicitCollisionEvents(value) end

---@param collision_class_name string
---@param collision_class? windfield.CollisionClass
function World:addCollisionClass(collision_class_name, collision_class) end

---@param class_a string
---@param class_b string
---@param fn fun(a: windfield.Collider, b: windfield.Collider, data: windfield.CollisionData)
---@return windfield.Handle
function World:onEnter(class_a, class_b, fn) end

---@param class_a string
---@param class_b string
---@param fn fun(a: windfield.Collider, b: windfield.Collider, data: windfield.CollisionData)
---@return windfield.Handle
function World:onExit(class_a, class_b, fn) end

---@param fn? fun(a: windfield.Collider, b: windfield.Collider): boolean? Return false to reject the contact.
function World:setColliderFilter(fn) end

---@param x number
---@param y number
---@param r number
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newCircleCollider(x, y, r, settings) end

---@param x number Top left corner.
---@param y number Top left corner.
---@param w number
---@param h number
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newRectangleCollider(x, y, w, h, settings) end

---@param x number Top left corner.
---@param y number Top left corner.
---@param w number
---@param h number
---@param corner_cut_size number
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newBSGRectangleCollider(x, y, w, h, corner_cut_size, settings) end

---@param vertices number[] Flat list: x1, y1, x2, y2, ...
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newPolygonCollider(vertices, settings) end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newLineCollider(x1, y1, x2, y2, settings) end

---@param vertices number[] Flat list: x1, y1, x2, y2, ...
---@param loop boolean
---@param settings? windfield.ColliderSettings
---@return windfield.Collider
function World:newChainCollider(vertices, loop, settings) end

---@alias windfield.ClassNames string[]|{[1]: 'All', except?: string[]}

---@param x number
---@param y number
---@param radius number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryCircleArea(x, y, radius, collision_class_names) end

---@param x number Top left corner.
---@param y number Top left corner.
---@param w number
---@param h number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryRectangleArea(x, y, w, h, collision_class_names) end

---@param vertices number[] Flat list: x1, y1, x2, y2, ...
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryPolygonArea(vertices, collision_class_names) end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryLine(x1, y1, x2, y2, collision_class_names) end

---@param x number
---@param y number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryPoint(x, y, collision_class_names) end

---@param x number
---@param y number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider?
function World:getColliderAt(x, y, collision_class_names) end

---@class windfield.QueryShape
---@field type 'circle'|'rectangle'|'polygon'|'edge'
---@field radius? number For 'circle'.
---@field w? number For 'rectangle', centered on the placement point.
---@field h? number For 'rectangle'.
---@field vertices? number[] For 'polygon': flat list, convex, at most 8 points.
---@field x1? number For 'edge'.
---@field y1? number For 'edge'.
---@field x2? number For 'edge'.
---@field y2? number For 'edge'.
---@field angle? number Radians, around the placement point.

---@param shape_def windfield.QueryShape
---@param x number
---@param y number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.Collider[]
function World:queryShape(shape_def, x, y, collision_class_names) end

---@class windfield.ShapeCastHit: windfield.RayHit
---@field overlap? boolean True when the shape already overlapped the collider at the start.

---@param shape_def windfield.QueryShape
---@param x number Start position.
---@param y number Start position.
---@param dx number Movement.
---@param dy number Movement.
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@return windfield.ShapeCastHit? hit The nearest hit, nil when the whole movement is free. `nx`, `ny` point from the collider to the shape.
function World:shapeCast(shape_def, x, y, dx, dy, collision_class_names) end

---@class windfield.RayHit
---@field collider windfield.Collider
---@field x number Hit point x.
---@field y number Hit point y.
---@field nx number Surface normal x at the hit point.
---@field ny number Surface normal y at the hit point.
---@field fraction number 0 at the start of the ray, 1 at its end.

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param collision_class_names? windfield.ClassNames Default {'All'}.
---@param mode? 'all'|'closest' Default 'all'.
---@return windfield.RayHit[]|windfield.RayHit|nil hits Sorted by distance in 'all' mode, the nearest hit or nil in 'closest' mode.
function World:raycast(x1, y1, x2, y2, collision_class_names, mode) end

---@param joint_type string LÖVE joint name without `new`, such as 'MouseJoint' or 'RevoluteJoint'.
---@param ... any Arguments of the LÖVE constructor. Colliders are replaced by their body.
---@return love.Joint
function World:addJoint(joint_type, ...) end

---@param joint love.Joint
function World:removeJoint(joint) end

function World:destroy() end

---@class windfield.Collider: love.Body, love.Fixture, love.Shape
---@field id string
---@field world windfield.World
---@field collision_class string
---@field body love.Body
---@field fixture love.Fixture The solid fixture of the main shape.
---@field shape love.Shape The main shape.
---@field shapes table<string, love.Shape>
---@field fixtures table<string, love.Fixture> Solid fixtures by shape name.
---@field sensors table<string, love.Fixture> Sensor fixtures by shape name.
---@field draw? fun(self: windfield.Collider, alpha: number) Called by `World:draw` in place of the debug shape. Alpha is 0 to 255.
local Collider = {}

---@param collision_class_name string
function Collider:setCollisionClass(collision_class_name) end

---@param sensor boolean
function Collider:setSensor(sensor) end

---@return boolean
function Collider:isSensor() end

---@param other_collision_class_name string
---@return boolean?
function Collider:enter(other_collision_class_name) end

---@param other_collision_class_name string
---@return windfield.CollisionData?
function Collider:getEnterCollisionData(other_collision_class_name) end

---@param other_collision_class_name string
---@return boolean?
function Collider:exit(other_collision_class_name) end

---@param other_collision_class_name string
---@return windfield.CollisionData?
function Collider:getExitCollisionData(other_collision_class_name) end

---@param other_collision_class_name string
---@return windfield.CollisionData[]
function Collider:getEnters(other_collision_class_name) end

---@param other_collision_class_name string
---@return windfield.CollisionData[]
function Collider:getExits(other_collision_class_name) end

---@param other_collision_class_name string
---@return boolean?
function Collider:stay(other_collision_class_name) end

---@param other_collision_class_name string
---@return windfield.CollisionData[]?
function Collider:getStayCollisionData(other_collision_class_name) end

---@param other_collision_class_name string
---@param callback fun(self: windfield.Collider, other: windfield.Collider, data: windfield.CollisionData)
---@return windfield.Handle
function Collider:onEnter(other_collision_class_name, callback) end

---@param other_collision_class_name string
---@param callback fun(self: windfield.Collider, other: windfield.Collider, data: windfield.CollisionData)
---@return windfield.Handle
function Collider:onExit(other_collision_class_name, callback) end

---@param order number Lower orders are drawn first.
function Collider:setDrawOrder(order) end

---@return number order
function Collider:getDrawOrder() end

---@param callback fun(self: windfield.Collider, other: windfield.Collider, contact: love.Contact)
function Collider:setPreSolve(callback) end

---@param callback fun(self: windfield.Collider, other: windfield.Collider, contact: love.Contact, ni1: number, ti1: number, ni2: number, ti2: number)
function Collider:setPostSolve(callback) end

---@param shape_name string
---@param shape_type string LÖVE shape constructor name without `new`, such as 'RectangleShape'.
---@param ... any Arguments of the LÖVE shape constructor.
function Collider:addShape(shape_name, shape_type, ...) end

---@param shape_name string
function Collider:removeShape(shape_name) end

---@param object any
function Collider:setObject(object) end

---@return any
function Collider:getObject() end

---@param interpolated boolean
function Collider:setInterpolated(interpolated) end

---@return boolean
function Collider:isInterpolated() end

---@return number x
---@return number y
function Collider:getRenderPosition() end

---@return number angle
function Collider:getRenderAngle() end

function Collider:destroy() end

return wf
