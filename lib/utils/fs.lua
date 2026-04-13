local M = require("file") ---@module 'file'
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
    Utils.validate("directory", directory, "string")
    Utils.validate("opts", opts, "table")
    if string.sub(directory, -1) ~= "/" then
        directory = directory .. "/"
    end
    local search_dir = directory
    local command = ""

    if M.iswin then
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
---@param file string Path
---@return string Basename of {file}
function M.basename(file)
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
---@param file string Path
---@return string Parent directory of {file}
function M.dirname(file)
    Utils.validate("file", file, "string")
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

---@param components string[]
---@param opts? PathOpts
---@return string? path
function M.Path(components, opts)
    Utils.validate("components", components, Utils.islist)
    Utils.validate("opts", opts, "table", true)

    opts = opts or {}
    local path = Utils.strings.trim_space(M.join_path(unpack(components)))
    if not M.path_exists(path, opts) then
        if opts.fail then
            error("Path does not exists")
        end
        return nil
    end
    return path
end

return M
