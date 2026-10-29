-- Lua 5.1 to 5.5 common subset; LÖVE provides the `love` global.
std = 'min'
max_line_length = false

-- `table.unpack or unpack` is how the source reaches unpack on every Lua version.
read_globals = { 'love', 'unpack', table = { fields = { 'unpack' } } }

-- Vendored third-party code is checked by the compiler only, and the type
-- definitions are declarations for the language server, not runnable code.
exclude_files = { 'windfield/mlib/**', 'types/**' }

-- Trailing whitespace, shadowing, unused `self` and unused loop variables come
-- from the upstream code and are not worth the diff noise.
ignore = { '611', '612', '613', '614', '421', '422', '423', '431', '432', '212/self', '213' }

-- The tests replace parts of `love` and `print` to mock the environment and keep
-- throwaway locals for readability.
files['tests/**'] = {
    globals = { 'love', 'print' },
    ignore = { '211', '212', '231', '241', '311', '331' },
}
