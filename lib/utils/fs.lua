local M = require("file") ---@module 'file'
local iswin = not not (RUNTIME.osType:lower():find("windows"))
local os_sep = iswin and "\\" or "/"

--- Iterate over all the parents of the given path (not expanded/resolved, the caller must do that).
---
--- Example:
---
--- ```lua
--- local root_dir
--- for dir in Utils.fs.parents(Utils.api.nUtils_buf_get_name(0)) do
---   if Utils.fn.isdirectory(dir .. '/.git') == 1 then
---     root_dir = dir
---     break
---   end
--- end
---
--- if root_dir then
---   print('Found git repository at', root_dir)
--- end
--- ```
---
---@since 10
---@param start (string) Initial path.
---@return fun(_, dir: string): string? # Iterator
---@return nil
---@return string|nil
function M.parents(start)
    return function(_, dir)
        local parent = M.dirname(dir)
        if parent == dir then
            return nil
        end

        return parent
    end,
        nil,
        start
end

---@param path string
---@return string? Output
function M.fs_realpath(path)
    local handle = io.popen(string.format("realpath %s 2>/dev/null", path))
    if not handle then
        return nil
    end
    local tool_path = handle:read("*l")
    handle:close()

    if not tool_path or tool_path == "" then
        return nil
    end

    return tool_path
end

---@param path string
---@return boolean
function M.directory_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
end

function M.isdirectory(path)
    Utils.validate("path", path, "string")
    if string.sub(path, -1) == "/" then
        return true
    end
    return false
end
---@alias PathType
---| "file"
---| "directory"

---@class ScanDirOpts
---@field type? PathType - Whether or not to scan subdirectories recursively (default value = true)
---@field recursive? boolean - Whether or not to scan subdirectories recursively (default value = true)
---@field pattern? string - List of extensions to collect, if blank all will be collected

--- Create a flat list of all files in a directory
---@param directory string - The directory to scan (default value = './')
---@param opts ScanDirOpts - The directory to scan (default value = './')
function M.scandir(directory, opts)
    Utils.validate("directory", directory, "string")
    Utils.validate("opts", opts, "table")
    if string.sub(directory, -1) ~= "/" then
        directory = directory .. "/"
    end
    local search_dir = directory
    local command = ""

    if iswin then
        command = 'dir "' .. search_dir .. '" /b'
    else
        command = "ls -p " .. search_dir
        if opts.type == "file" then
            command = command .. " | grep -v /"
        elseif opts.type == "directory" then
            command = command .. " | grep /"
        end
    end
    local res = {}
    for path in io.popen(command):lines() do
        local check = opts.type == "directory" and "([%w%d_-]+)/$" or "([%w%d_-]+)"
        if type(opts.pattern) == "string" then
            local pattern = opts.pattern
            assert(pattern)
            check = (opts.type == "directory") and pattern .. "/$" or pattern
        end
        local matched = path:match(check)
        if matched then
            Utils.inf("Matched path", { matched = matched })
            table.insert(res, search_dir .. matched)
        end
    end
    return res
end
--- Gets the basename of the given path (not expanded/resolved).
---
---@since 10
---@param file string Path
---@return string Basename of {file}
function M.basename(file)
    Utils.validate("file", file, "string")
    if iswin then
        file = file:gsub(os_sep, "/") --[[@as string]]
        if file:match("^%w:/?$") then
            return ""
        end
    end
    return file:match("/$") and "" or (file:match("[^/]*$"))
end
--- Gets the parent directory of the given path (not expanded/resolved, the caller must do that).
---
---@since 10
---@param file string Path
---@return string Parent directory of {file}
function M.dirname(file)
    Utils.validate("file", file, "string")
    if iswin then
        file = file:gsub(os_sep, "/") --[[@as string]]
        if file:match("^%w:/?$") then
            return file
        end
    end
    if not file:match("/") then
        return "."
    elseif file == "/" or file:match("^/[^/]+$") then
        return "/"
    end
    ---@type string
    local dir = file:match("/$") and file:sub(1, #file - 1) or file:match("^(/?.+)/")
    if iswin and dir:match("^%w:$") then
        return dir .. "/"
    end
    return dir
end

---@class PathExistsOpts
---@field type PathType
---@field create? boolean

---@param path string
---@param opts? PathExistsOpts
---@return boolean
function M.path_exists(path, opts)
    Utils.validate("path", path, "string")
    Utils.validate("opts", opts, "table", true)
    opts = opts or { type = "directory" }
    local exists = false
    if opts.type == "file" then
        exists = M.exists(path)
    else
        exists = M.directory_exists(path)
    end
    if not exists and opts.create then
        local cmd = { "mkdir", "-p", path }
        if opts.type == "file" then
            cmd = { "touch", path }
        end
        Utils.sh.safe_exec(cmd, { fail = true })
        return true
    end
    return exists
end

---@class PathOpts : PathExistsOpts
---@field fail? boolean

---@param components string|string[]
---@param opts? PathOpts
---@return string? path
function M.Path(components, opts)
    Utils.validate("components", components, { "string", "table" })
    Utils.validate("opts", opts, "table", true)
    local path = ""
    if type(components) == "table" then
        path = M.join_path(unpack(components))
    else
        path = components
    end
    opts = opts or {}
    path = Utils.strings.trim_space(path)
    if opts.fail and not M.path_exists(path, opts) then
        Utils.fatal("Path does not exists")
    end
    return path
end

--- Split a Windows path into a prefix and a body, such that the body can be processed like a POSIX
--- path. The path must use forward slashes as path separator.
---
--- Does not check if the path is a valid Windows path. Invalid paths will give invalid results.
---
--- Examples:
--- - `//./C:/foo/bar` -> `//./C:`, `/foo/bar`
--- - `//?/UNC/server/share/foo/bar` -> `//?/UNC/server/share`, `/foo/bar`
--- - `//./system07/C$/foo/bar` -> `//./system07`, `/C$/foo/bar`
--- - `C:/foo/bar` -> `C:`, `/foo/bar`
--- - `C:foo/bar` -> `C:`, `foo/bar`
---
--- @param path string Path to split.
--- @return string, string, boolean : prefix, body, whether path is invalid.
local function split_windows_path(path)
    local prefix = ""

    --- Match pattern. If there is a match, move the matched pattern from the path to the prefix.
    --- Returns the matched pattern.
    ---
    --- @param pattern string Pattern to match.
    --- @return string|nil Matched pattern
    local function match_to_prefix(pattern)
        local match = path:match(pattern)

        if match then
            prefix = prefix .. match --[[ @as string ]]
            path = path:sub(#match + 1)
        end

        return match
    end

    local function process_unc_path()
        return match_to_prefix("[^/]+/+[^/]+/+")
    end

    if match_to_prefix("^//[?.]/") then
        -- Device paths
        local device = match_to_prefix("[^/]+/+")

        -- Return early if device pattern doesn't match, or if device is UNC and it's not a valid path
        if not device or (device:match("^UNC/+$") and not process_unc_path()) then
            return prefix, path, false
        end
    elseif match_to_prefix("^//") then
        -- Process UNC path, return early if it's invalid
        if not process_unc_path() then
            return prefix, path, false
        end
    elseif path:match("^%w:") then
        -- Drive paths
        prefix, path = path:sub(1, 2), path:sub(3)
    end

    -- If there are slashes at the end of the prefix, move them to the start of the body. This is to
    -- ensure that the body is treated as an absolute path. For paths like C:foo/bar, there are no
    -- slashes at the end of the prefix, so it will be treated as a relative path, as it should be.
    local trailing_slash = prefix:match("/+$")

    if trailing_slash then
        prefix = prefix:sub(1, -1 - #trailing_slash)
        path = trailing_slash .. path --[[ @as string ]]
    end

    return prefix, path, true
end

--- Resolve `.` and `..` components in a POSIX-style path. This also removes extraneous slashes.
--- `..` is not resolved if the path is relative and resolving it requires the path to be absolute.
--- If a relative path resolves to the current directory, an empty string is returned.
---
--- @see M.normalize()
--- @param path string Path to resolve.
--- @return string Resolved path.
local function path_resolve_dot(path)
    local is_path_absolute = Utils.strings.has_prefix(path, "/")
    local new_path_components = {}

    for component in Utils.strings.split(path, "/") do
        if component == "." or component == "" then -- luacheck: ignore 542
        -- Skip `.` components and empty components
        elseif component == ".." then
            if #new_path_components > 0 and new_path_components[#new_path_components] ~= ".." then
                -- For `..`, remove the last component if we're still inside the current directory, except
                -- when the last component is `..` itself
                table.remove(new_path_components)
            elseif is_path_absolute then -- luacheck: ignore 542
            -- Reached the root directory in absolute path, do nothing
            else
                -- Reached current directory in relative path, add `..` to the path
                table.insert(new_path_components, component)
            end
        else
            table.insert(new_path_components, component)
        end
    end

    return (is_path_absolute and "/" or "") .. table.concat(new_path_components, "/")
end

--- Expand tilde (~) character at the beginning of the path to the user's home directory.
---
--- @param path string Path to expand.
--- @param sep string|nil Path separator to use. Uses os_sep by default.
--- @return string Expanded path.
local function expand_home(path, sep)
    sep = sep or os_sep

    if Utils.strings.has_prefix(path, "~") then
        local home = os.getenv("HOME") or "~" --- @type string

        if home:sub(-1) == sep then
            home = home:sub(1, -2)
        end

        path = home .. path:sub(2) --- @type string
    end

    return path
end

--- @class vim.fs.normalize.Opts
--- @inlinedoc
---
--- Expand environment variables.
--- (default: `true`)
--- @field expand_env? boolean
---
--- @field package _fast? boolean
---
--- Path is a Windows path.
--- (default: `true` in Windows, `false` otherwise)
--- @field win? boolean

--- Normalize a path to a standard format. A tilde (~) character at the beginning of the path is
--- expanded to the user's home directory and environment variables are also expanded. "." and ".."
--- components are also resolved, except when the path is relative and trying to resolve it would
--- result in an absolute path.
--- - "." as the only part in a relative path:
---   - "." => "."
---   - "././" => "."
--- - ".." when it leads outside the current directory
---   - "foo/../../bar" => "../bar"
---   - "../../foo" => "../../foo"
--- - ".." in the root directory returns the root directory.
---   - "/../../" => "/"
---
--- On Windows, backslash (\) characters are converted to forward slashes (/).
---
--- Examples:
--- ```lua
--- [[C:\Users\jdoe]]                         => "C:/Users/jdoe"
--- "~/src/neovim"                            => "/home/jdoe/src/neovim"
--- "$XDG_CONFIG_HOME/nvim/init.vim"          => "/Users/jdoe/.config/nvim/init.vim"
--- "~/src/nvim/api/../tui/./tui.c"           => "/home/jdoe/src/nvim/tui/tui.c"
--- "./foo/bar"                               => "foo/bar"
--- "foo/../../../bar"                        => "../../bar"
--- "/home/jdoe/../../../bar"                 => "/bar"
--- "C:foo/../../baz"                         => "C:../baz"
--- "C:/foo/../../baz"                        => "C:/baz"
--- [[\\?\UNC\server\share\foo\..\..\..\bar]] => "//?/UNC/server/share/bar"
--- ```
---
---@since 10
---@param path (string) Path to normalize
---@param opts? vim.fs.normalize.Opts
---@return (string) : Normalized path
function M.normalize(path, opts)
    opts = opts or {}

    if not opts._fast then
        Utils.validate("path", path, "string")
        Utils.validate("expand_env", opts.expand_env, "boolean", true)
        Utils.validate("win", opts.win, "boolean", true)
    end

    local win = opts.win == nil and iswin or not not opts.win
    local os_sep_local = win and "\\" or "/"

    -- Empty path is already normalized
    if path == "" then
        return ""
    end

    -- Expand ~ to user's home directory
    path = expand_home(path, os_sep_local)

    -- Expand environment variables if `opts.expand_env` isn't `false`
    if opts.expand_env == nil or opts.expand_env then
        path = path:gsub("%$([%w_]+)", os.getenv) --- @type string
    end

    if win then
        -- Convert path separator to `/`
        path = path:gsub(os_sep_local, "/")
    end

    -- Check for double slashes at the start of the path because they have special meaning
    local double_slash = false
    if not opts._fast then
        double_slash = Utils.strings.has_prefix(path, "//") and not Utils.strings.has_prefix(path, "///")
    end

    local prefix = ""

    if win then
        local is_valid --- @type boolean
        -- Split Windows paths into prefix and body to make processing easier
        prefix, path, is_valid = split_windows_path(path)

        -- If path is not valid, return it as-is
        if not is_valid then
            return prefix .. path
        end

        -- Ensure capital drive and remove extraneous slashes from the prefix
        prefix = prefix:gsub("^%a:", string.upper):gsub("/+", "/")
    end

    if not opts._fast then
        -- Resolve `.` and `..` components and remove extraneous slashes from path, then recombine prefix
        -- and path.
        path = path_resolve_dot(path)
    end

    -- Preserve leading double slashes as they indicate UNC paths and DOS device paths in
    -- Windows and have implementation-defined behavior in POSIX.
    path = (double_slash and "/" or "") .. prefix .. path

    -- Change empty path to `.`
    if path == "" then
        path = "."
    end

    return path
end

--- Converts `path` to an absolute path. Expands tilde (~) at the beginning of the path
--- to the user's home directory. Does not check if the path exists, normalize the path, resolve
--- symlinks or hardlinks (including `.` and `..`), or expand environment variables. If the path is
--- already absolute, it is returned unchanged. Also converts `\` path separators to `/`.
---
--- @since 13
--- @param path string Path
--- @return string Absolute path
function M.abspath(path)
    -- TODO(justinmk): mark f_fnamemodify as API_FAST and use it, ":p:h" should be safe...

    Utils.validate("path", path, "string")

    -- Expand ~ to user's home directory
    path = expand_home(path)

    -- Convert path separator to `/`
    path = path:gsub(os_sep, "/")

    local prefix = ""

    if iswin then
        prefix, path = split_windows_path(path)
    end

    if prefix == "//" or Utils.strings.has_prefix(path, "/") then
        -- Path is already absolute, do nothing
        return prefix .. path
    end

    -- Windows allows paths like C:foo/bar, these paths are relative to the current working directory
    -- of the drive specified in the path
    local cwd = assert((iswin and prefix:match("^%w:$")) and M.fs_realpath(prefix) or os.getenv("PWD"))
    -- Convert cwd path separator to `/`
    cwd = cwd:gsub(os_sep, "/")

    if path == "." then
        return cwd
    end
    -- Prefix is not needed for expanding relative paths, `cwd` already contains it.
    return M.joinpath(cwd, path)
end
return M
