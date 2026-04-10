local M = {}

M.iswin = not not (RUNTIME.osType:lower():find("windows"))
M.os_sep = M.iswin and "\\" or "/"

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

function M.directory_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    else
        return false
    end
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
    if string.sub(directory, -1) ~= "/" then
        directory = directory .. "/"
    end
    local search_dir = directory
    local command = ""

    if M.is_win then
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
    Utils.inf("Scandir cmd", { cmd = command })
    for path in io.popen(command):lines() do
        local check = opts.type == "directory" and "([%w%d_-]+)/$" or "([%w%d_-]+)"
        if type(opts.pattern) == "string" then
            local pattern = opts.pattern
            assert(pattern)
            check = (opts.type == "directory") and pattern .. "/$" or pattern
        end
        Utils.inf("Scandir check", { check = check })
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
---@generic T : string|nil
---@param file T Path
---@return T Basename of {file}
function M.basename(file)
    if file == nil then
        return nil
    end
    Utils.validate("file", file, "string")
    if M.iswin then
        file = file:gsub(M.os_sep, "/") --[[@as string]]
        if file:match("^%w:/?$") then
            return ""
        end
    end
    return file:match("/$") and "" or (file:match("[^/]*$"))
end
--- Gets the parent directory of the given path (not expanded/resolved, the caller must do that).
---
---@since 10
---@generic T : string|nil
---@param file T Path
---@return T Parent directory of {file}
function M.dirname(file)
    if file == nil then
        return nil
    end
    if M.iswin then
        file = file:gsub(M.os_sep, "/") --[[@as string]]
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
    if M.iswin and dir:match("^%w:$") then
        return dir .. "/"
    end
    return dir
end

---@class PathOpts
---@field create? boolean
---@field check_exists? boolean
---@field fail? boolean

local file = require("file")
---@param components string[]
---@param opts? PathOpts
---@return string path
function M.Path(components, opts)
    if type(components) ~= "table" then
        Utils.err("Components is not a table", { components = components })
    end
    opts = opts or {}
    local path = file.join_path(unpack(components))
    if opts.create then
        local ok = require("shell_exec").safe_exec("mkdir -p " .. path)
        if not ok then
            Utils.wrn("Path not created!: ", { path = path })
        else
            Utils.inf("Path created successfully: ", { path = path })
        end
        return path
    end
    if opts.check_exists then
        if path == nil or path == "" or not file.exists(path) then
            if opts.fail then
                Utils.fatal("Path does not exist : ", { path = path })
            else
                Utils.inf("Path does not exist : ", { path = path })
            end
            return ""
        end
    end
    return path
end

return M
