-- Area query behavior. The box collider covers x 100..150, y 100..150; the
-- circle collider has center (125, 125) and radius 25. Line cases need real
-- ray casting, so only the LÖVE smoke script runs them.
local box = {kind = 'rectangle', 100, 100, 50, 50}
local disc = {kind = 'circle', 125, 125, 25}

return {
    {'circle query crossing the edge of a box', box, {kind = 'circle', 150, 125, 20}, true},
    {'circle query inside a box', box, {kind = 'circle', 125, 125, 10}, false},
    {'circle query around a box', box, {kind = 'circle', 125, 125, 60}, true},
    {'circle query far from a box', box, {kind = 'circle', 300, 300, 10}, false},
    {'circle query overlapping a circle collider', disc, {kind = 'circle', 150, 125, 20}, true},
    {'circle query inside a circle collider', disc, {kind = 'circle', 125, 125, 5}, true},
    {'circle query far from a circle collider', disc, {kind = 'circle', 300, 300, 10}, false},

    {'rectangle query overlapping a box', box, {kind = 'rectangle', 130, 130, 50, 50}, true},
    {'rectangle query around a box', box, {kind = 'rectangle', 90, 90, 80, 80}, true},
    {'rectangle query inside a box', box, {kind = 'rectangle', 110, 110, 10, 10}, false},
    {'rectangle query far from a box', box, {kind = 'rectangle', 300, 300, 10, 10}, false},
    {'rectangle query over the center of a circle collider', disc, {kind = 'rectangle', 120, 120, 10, 10}, true},
    {'rectangle query crossing the edge of a circle collider', disc, {kind = 'rectangle', 140, 110, 30, 30}, true},
    {'rectangle query inside a circle collider away from its center', disc, {kind = 'rectangle', 110, 110, 5, 5}, true},
    {'rectangle query far from a circle collider', disc, {kind = 'rectangle', 300, 300, 10, 10}, false},

    {'polygon query around a box', box, {kind = 'polygon', 80, 80, 170, 80, 170, 170, 80, 170}, true},
    {'polygon query overlapping a box', box, {kind = 'polygon', 120, 120, 200, 120, 200, 200, 120, 200}, true},
    {'polygon query inside a box', box, {kind = 'polygon', 110, 110, 140, 110, 140, 140, 110, 140}, false},
    {'polygon query far from a box', box, {kind = 'polygon', 300, 300, 320, 300, 320, 320, 300, 320}, false},
    {'polygon query over the center of a circle collider', disc, {kind = 'polygon', 110, 110, 140, 110, 140, 140, 110, 140}, true},

    {'line query through a box', box, {kind = 'line', 0, 125, 300, 125}, true, line = true},
    {'line query missing a box', box, {kind = 'line', 0, 0, 50, 50}, false, line = true},
    {'line query through a circle collider', disc, {kind = 'line', 0, 125, 300, 125}, true, line = true},
}
