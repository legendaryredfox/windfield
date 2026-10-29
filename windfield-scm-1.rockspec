rockspec_format = '3.0'
package = 'windfield'
version = 'scm-1'

source = {
    url = 'git+https://github.com/legendaryredfox/windfield.git',
    branch = 'master',
}

description = {
    summary = 'Physics module for LÖVE 11 that wraps love.physics with collision classes, events and queries',
    detailed = [[
        Wraps the Box2D bindings of LÖVE with collision classes, enter, exit and
        stay events, area, point and ray queries, sensors, one-way platforms,
        conveyors and joints.
    ]],
    homepage = 'https://github.com/legendaryredfox/windfield',
    license = 'MIT',
}

dependencies = {
    'lua >= 5.1',
}

build = {
    type = 'builtin',
    modules = {
        windfield = 'windfield/init.lua',
        ['windfield.mlib.mlib'] = 'windfield/mlib/mlib.lua',
    },
}
