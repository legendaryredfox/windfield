-- Reads RESULT lines on stdin and prints a markdown table, one row per
-- scenario and metric, one column per library.
local libraries, rows, index = {}, {}, {}

for line in io.lines() do
    local library, scenario, metric, value, unit = line:match('^RESULT\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$')
    if library then
        if not libraries[library] then
            libraries[library] = true
            libraries[#libraries + 1] = library
        end
        local key = scenario .. ' ' .. metric
        if not index[key] then
            index[key] = {label = scenario .. ' ' .. metric, unit = unit, values = {}}
            rows[#rows + 1] = index[key]
        end
        index[key].values[library] = tonumber(value)
    end
end

local header, rule = {'scenario', 'unit'}, {'---', '---'}
for _, library in ipairs(libraries) do
    header[#header + 1] = library
    rule[#rule + 1] = '---'
end
print('| ' .. table.concat(header, ' | ') .. ' |')
print('| ' .. table.concat(rule, ' | ') .. ' |')
for _, row in ipairs(rows) do
    local cells = {row.label, row.unit}
    for _, library in ipairs(libraries) do
        local value = row.values[library]
        cells[#cells + 1] = value and string.format('%.3f', value) or 'n/a'
    end
    print('| ' .. table.concat(cells, ' | ') .. ' |')
end
