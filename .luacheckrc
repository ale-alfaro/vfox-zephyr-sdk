-- https://luacheck.readthedocs.io/en/stable/config.html
std = "lua51"

-- Globals provided by the mise runtime
globals = {
    "PLUGIN",
    "RUNTIME",
    "Utils",
    "ZephyrSdk",
}

-- Modules provided by mise (available via require but not as globals)
read_globals = {
    "require",
}

-- Ignore the types/ meta directory (type stubs, not real code)
exclude_files = {
    "types/",
}

-- Max line length (match stylua column_width)
max_line_length = 120

-- Ignore unused arguments starting with _
unused_args = false
self = false
