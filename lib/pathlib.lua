local M = {}

local os_name = RUNTIME.osType:lower()
local arch = RUNTIME.archType:lower()
local iswin = not not (os_name:find("windows"))
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
---@generic T : string|nil
---@param file T Path
---@return T Parent directory of {file}
function M.dirname(file)
    if file == nil then
        return nil
    end
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

---@class PathOpts
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
