---@nodoc
---@diagnostic disable-next-line: missing-fields
_G.Utils = _G.Utils or {} --[[@as Utils]]

--- Returns the current OS name lowercased.
---@return string
function Utils.os()
    return RUNTIME.osType:lower()
end

local arch_map = { amd64 = "x86_64", arm64 = "aarch64", x86_64 = "x86_64", aarch64 = "aarch64" }
function Utils.arch()
    return arch_map[RUNTIME.archType]
end
---@return string
local function get_platform_exe_suffix()
    return RUNTIME.osType:lower() == "windows" and ".exe" or ""
end

local function get_platform_archive_suffix()
    return RUNTIME.osType:lower() == "windows" and ".zip" or ".tar.gz"
end

local function lua_pattern_escape(value)
    local str = tostring(value or "")
    return str.gsub(str:gsub("([%.%(%)%[%]%%%^%$%*%+%-%?])", "%%%1"), "%%", "")
end

Utils.platform_create_string = function(template, opts)
    template = lua_pattern_escape(template)
    opts = opts or {}
    local mappings = Utils.tbl_extend("force", {
        ["{os}"] = Utils.os(),
        ["{arch}"] = Utils.arch(),
        ["{ext}"] = (opts.exttype == "archive") and get_platform_archive_suffix() or get_platform_exe_suffix(),
    }, opts.override or {})
    template = string.gsub(template, "({%w+})", mappings)
    return template
end
-- Common version string operations
Utils.normalize_version = function(version)
    -- Remove 'v' prefix if present
    version = version:gsub("^v", "")

    -- Remove pre-release suffixes
    local parts = Utils.strings.split(version, "-")
    return parts[1]
end
--- Print Lua objects in command line
---
---@param print_fn? fun(any):any  number of objects to be printed each on separate line.
---@param ... any Any number of objects to be printed each on separate line.
Utils.put = function(print_fn, ...)
    local objects = {}
    local inspect = Utils.inspect
    -- Not using `{...}` because it removes `nil` input
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        table.insert(objects, inspect(v))
    end
    if print_fn then
        print_fn(table.concat(objects, "\n"))
    else
        print(table.concat(objects, "\n"))
    end
    return ...
end
---@param ... any Any number of objects to be printed each on separate line.
Utils.err = function(...)
    Utils.put(require("log").error, "ERROR: ", ...)
end
---@param ... any Any number of objects to be printed each on separate line.
Utils.wrn = function(...)
    Utils.put(require("log").warn, ...)
end
---@param ... any Any number of objects to be printed each on separate line.
Utils.dbg = function(...)
    Utils.put(require("log").debug, ...)
end
---@param ... any Any number of objects to be printed each on separate line.
Utils.inf = function(...)
    Utils.put(require("log").info, ...)
end
---@param msg string Any number of objects to be printed each on separate line.
---@param ... any Any number of objects to be printed each on separate line.
Utils.fatal = function(msg, ...)
    Utils.err(...)
    error("FATAL:" .. msg)
end

--- @generic T
--- @param x T|T[]
--- @return T[]
function Utils.ensure_list(x)
    if type(x) == "table" then
        return x
    end
    return { x }
end
--- Return a list of all keys used in a table.
--- However, the order of the return table of keys is not guaranteed.
---
---@see From https://github.com/premake/premake-core/blob/master/src/base/table.lua
---
---@generic T
---@param t table<T, any> (table) Table
---@return T[] : List of keys
function Utils.tbl_keys(t)
    Utils.validate("t", t, "table")
    --- @cast t table<any,any>

    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    return keys
end

--- Return a list of all values used in a table.
--- However, the order of the return table of values is not guaranteed.
---
---@generic T
---@param t table<any, T> (table) Table
---@return T[] : List of values
function Utils.tbl_values(t)
    Utils.validate("t", t, "table")

    local values = {}
    for _, v in
        pairs(t --[[@as table<any,any>]])
    do
        table.insert(values, v)
    end
    return values
end
--- Applies function `fn` to all values of table `t`, in `pairs()` iteration order (which is not
--- guaranteed to be stable, even when the data doesn't change).

---@generic K,V
---@param fn fun(value: V):any Function
---@param t table<K,V> Table
---@return table<K,any> Table of transformed values
Utils.tbl_map = function(fn, t)
    local rettab = {}
    for k, v in pairs(t) do
        rettab[k] = fn(v)
    end
    return rettab
end
---@generic T
---@param fn fun(value: T): any Function
---@param t  T[] list
---@return table<any>: list of transformed values
function Utils.list_map(fn, t)
    --- @cast t table<any,any>
    local rettab = {} --- @type table<any,any>
    for _, v in ipairs(t) do
        rettab[#rettab + 1] = fn(v)
    end
    return rettab
end

--- Filter a table using a predicate function
---
---@generic T
---@param fn fun(value: T): boolean (function) Function
---@param t table<any, T> (table) Table
---@return T[] : Table of filtered values
function Utils.tbl_filter(fn, t)
    --- @cast t table<any,any>

    local rettab = {} --- @type table<any,any>
    for _, entry in pairs(t) do
        if fn(entry) then
            rettab[#rettab + 1] = entry
        end
    end
    return rettab
end

--- Filter a table using a predicate function
---
---@generic T
---@param fn fun(value: T): boolean (function) Function
---@param t T[] (list): list
---@return T[] : Table of filtered values
function Utils.list_filter(fn, t)
    --- @cast t table<any,any>

    local rettab = {} --- @type table<any,any>
    for _, entry in ipairs(t) do
        if fn(entry) then
            rettab[#rettab + 1] = entry
        end
    end
    return rettab
end
--- @class Utils.tbl_contains.Opts
--- @inlinedoc
---
--- `value` is a function reference to be checked (default false)
--- @field predicate? boolean

--- Checks if a table contains a given value, specified either directly or via
--- a predicate that is checked for each value.
---
--- Example:
---
---
--- Utils.tbl_contains({ 'a', { 'b', 'c' } }, function(v)
---   return Utils.deep_equal(v, { 'b', 'c' })
--- end, { predicate = true })
---
---
---
---@see Utils.tbl_contains
---
---@param t table Table to check
---@param value any Value to compare or predicate function reference
---@param opts? Utils.tbl_contains.Opts Keyword arguments |kwargs|:
---@return boolean `true` if `t` contains `value`
function Utils.tbl_contains(t, value, opts)
    --- @cast t table<any,any>

    local pred --- @type fun(v: any): boolean?
    if opts and opts.predicate then
        Utils.validate("value", value, "callable")
        pred = value
    else
        pred = function(v)
            return v == value
        end
    end

    for _, v in pairs(t) do
        if pred(v) then
            return true
        end
    end
    return false
end

--- @alias Utils.validate.Validator
--- | type
--- | 'callable'
--- | (type|'callable')[]
--- | fun(v:any):boolean, string?

local type_aliases = {
    b = "boolean",
    c = "callable",
    f = "function",
    n = "number",
    s = "string",
    t = "table",
}

--- @nodoc
--- @class Utils.validate.Spec
--- @field [1] any Argument value
--- @field [2] Utils.validate.Validator Argument validator
--- @field [3]? boolean|string Optional flag or error message

local function is_type(val, t)
    return type(val) == t or (t == "callable" and Utils.is_callable(val))
end

--- @param param_name string
--- @param val any
--- @param validator Utils.validate.Validator
--- @param message? string "Expected" message
--- @param allow_alias? boolean Allow short type names: 'n', 's', 't', 'b', 'f', 'c'
--- @return string?
local function is_valid(param_name, val, validator, message, allow_alias)
    if type(validator) == "string" then
        local expected = allow_alias and type_aliases[validator] or validator

        if not expected then
            return string.format("invalid type name: %s", validator)
        end

        if not is_type(val, expected) then
            return ("%s: expected %s, got %s"):format(param_name, message or expected, type(val))
        end
    elseif Utils.is_callable(validator) then
        -- Check user-provided validation function
        local valid, opt_msg = validator(val)
        if not valid then
            local err_msg = ("%s: expected %s, got %s"):format(param_name, message or "?", tostring(val))
            err_msg = opt_msg and ("%s. Info: %s"):format(err_msg, opt_msg) or err_msg

            return err_msg
        end
    elseif type(validator) == "table" then
        for _, t in ipairs(validator) do
            local expected = allow_alias and type_aliases[t] or t
            if not expected then
                return string.format("invalid type name: %s", t)
            end

            if is_type(val, expected) then
                return -- success
            end
        end

        -- Normalize validator types for error message
        if allow_alias then
            for i, t in ipairs(validator) do
                validator[i] = type_aliases[t] or t
            end
        end

        return string.format("%s: expected %s, got %s", param_name, table.concat(validator, "|"), type(val))
    else
        return string.format("invalid validator: %s", tostring(validator))
    end
end

--- Enumerates key-value pairs of a table, ordered by key.
---
---@see Based on https://github.com/premake/premake-core/blob/master/src/base/table.lua
---
---@generic T: table, K, V
---@param t T Dict-like table
---@return fun(table: table<K, V>, index?: K):K, V # |for-in| iterator over sorted keys and their values
---@return T
function Utils.spairs(t)
    Utils.validate("t", t, "table")
    --- @cast t table<any,any>

    -- collect the keys
    local keys = {} --- @type string[]
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys)

    -- Return the iterator function.
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end,
        t
end
--- Validate function arguments.
---
--- This function has two valid forms:
---
--- 1. `Utils.validate(name, value, validator[, optional][, message])`
---
---     Validates that argument {name} with value {value} satisfies
---     {validator}. If {optional} is given and is `true`, then {value} may be
---     `nil`. If {message} is given, then it is used as the expected type in the
---     error message.
---
---     Example:
---
---     ```lua
---       function Utils.startswith(s, prefix)
---         Utils.validate('s', s, 'string')
---         Utils.validate('prefix', prefix, 'string')
---         -- ...
---       end
---     ```
---
--- Examples with explicit argument values (can be run directly):
---
--- ```lua
--- Utils.validate('arg1', {'foo'}, 'table')
---    --> NOP (success)
--- Utils.validate('arg2', 'foo', 'string')
---    --> NOP (success)
---
--- Utils.validate('arg1', 1, 'table')
---    --> error('arg1: expected table, got number')
---
--- Utils.validate('arg1', 3, function(a) return (a % 2) == 0 end, 'even number')
---    --> error('arg1: expected even number, got 3')
--- ```
---
--- If multiple types are valid they can be given as a list.
---
--- ```lua
--- Utils.validate('arg1', {'foo'}, {'table', 'string'})
--- Utils.validate('arg2', 'foo', {'table', 'string'})
--- -- NOP (success)
---
--- Utils.validate('arg1', 1, {'string', 'table'})
--- -- error('arg1: expected string|table, got number')
--- ```
---
--- @note `validator` set to a value returned by |lua-type()| provides the
--- best performance.
---
--- @param name string Argument name
--- @param value any Argument value
--- @param validator Utils.validate.Validator :
---   - (`string|string[]`): Any value that can be returned from |lua-type()| in addition to
---     `'callable'`: `'boolean'`, `'callable'`, `'function'`, `'nil'`, `'number'`, `'string'`, `'table'`,
---     `'thread'`, `'userdata'`.
---   - (`fun(val:any): boolean, string?`) A function that returns a boolean and an optional
---     string message.
--- @param optional? boolean Parameter is optional (may be omitted or nil)
--- @param message? string message when validation fails
--- @overload fun(name: string, val: any, validator: Utils.validate.Validator, message: string)
--- @overload fun(spec: table<string,[any, Utils.validate.Validator, boolean|string]>)
function Utils.validate(name, value, validator, optional, message)
    local err_msg --- @type string?
    if validator then -- Form 1
        -- Check validator as a string first to optimize the common case.
        local ok = (type(value) == validator) or (value == nil and optional == true)
        if not ok then
            local msg = type(optional) == "string" and optional or message --[[@as string?]]
            -- Check more complicated validators
            err_msg = is_valid(name, value, validator, msg, false)
        end
    else
        error("invalid arguments")
    end

    if err_msg then
        error(err_msg, 2)
    end
end

--- Returns true if object `f` can be called as a function.
---
---@param f? any Any object
---@return boolean `true` if `f` is callable, else `false`
function Utils.is_callable(f)
    if type(f) == "function" then
        return true
    end
    local m = getmetatable(f)
    if m == nil then
        return false
    end
    return type(rawget(m, "__call")) == "function"
end

--- Checks if a table is empty.
---
---@see https://github.com/premake/premake-core/blob/master/src/base/table.lua
---
---@param t table Table to check
---@return boolean `true` if `t` is empty
function Utils.tbl_isempty(t)
    Utils.validate("t", t, "table")
    return next(t) == nil
end

--- We only merge empty tables or tables that are not list-like (indexed by consecutive integers
--- starting from 1)
local function can_merge(v)
    return type(v) == "table" and (Utils.tbl_isempty(v) or not Utils.islist(v))
end

--- Recursive worker for tbl_extend
--- @param behavior 'error'|'keep'|'force'|fun(key:any, prev_value:any?, value:any): any
--- @param deep_extend boolean
--- @param ... table<any,any>
local function tbl_extend_rec(behavior, deep_extend, ...)
    local ret = {} --- @type table<any,any>

    for i = 1, select("#", ...) do
        local tbl = select(i, ...) --[[@as table<any,any>]]
        if tbl then
            for k, v in pairs(tbl) do
                if deep_extend and can_merge(v) and can_merge(ret[k]) then
                    ret[k] = tbl_extend_rec(behavior, true, ret[k], v)
                elseif type(behavior) == "function" then
                    ret[k] = behavior(k, ret[k], v)
                elseif behavior ~= "force" and ret[k] ~= nil then
                    if behavior == "error" then
                        error("key found in more than one map: " .. k)
                    end -- Else behavior is "keep".
                else
                    ret[k] = v
                end
            end
        end
    end

    return ret
end

--- @param behavior MergeTableBehavior
--- @param deep_extend boolean
--- @param ... table<any,any>
local function tbl_extend(behavior, deep_extend, ...)
    if behavior ~= "error" and behavior ~= "keep" and behavior ~= "force" and type(behavior) ~= "function" then
        error('invalid "behavior": ' .. tostring(behavior))
    end

    local nargs = select("#", ...)

    if nargs < 2 then
        error(("wrong number of arguments (given %d, expected at least 3)"):format(1 + nargs))
    end

    for i = 1, nargs do
        Utils.validate("after the second argument", select(i, ...), "table")
    end

    return tbl_extend_rec(behavior, deep_extend, ...)
end

--- Merges two or more tables.
---
---
---@param behavior MergeTableBehavior Decides what to do if a key is found in more than one map:
---@param ... table Two or more tables
---@return table : Merged table
function Utils.tbl_extend(behavior, ...)
    return tbl_extend(behavior, false, ...)
end

--- Merges recursively two or more tables.
---
--- Only values that are empty tables or tables that are not |lua-list|s (indexed by consecutive
--- integers starting from 1) are merged recursively. This is useful for merging nested tables
--- like default and user configurations where lists should be treated as literals (i.e., are
--- overwritten instead of merged).
---
---
---@generic T1: table
---@generic T2: table
---@param behavior MergeTableBehavior
---@param ... T2 Two or more tables
---@return T1|T2 (table) Merged table
function Utils.tbl_deep_extend(behavior, ...)
    return tbl_extend(behavior, true, ...)
end
--- Checks if a table is a list (array-like, indexed by consecutive integers starting from 1).
---@param t table
---@return boolean
function Utils.islist(t)
    if type(t) ~= "table" then
        return false
    end
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then
            return false
        end
    end
    return true
end

--- Extends a list-like table with the values of another list-like table.
---
--- NOTE: This mutates dst!
---
---@generic T: table
---@param dst T List which will be modified and appended to
---@param src table List from which values will be inserted
---@param start integer? Start index on src. Defaults to 1
---@param finish integer? Final index on src. Defaults to `#src`
---@return T dst
function Utils.list_extend(dst, src, start, finish)
    Utils.validate("dst", dst, "table")
    Utils.validate("src", src, "table")
    Utils.validate("start", start, "number", true)
    Utils.validate("finish", finish, "number", true)
    for i = start or 1, finish or #src do
        table.insert(dst, src[i])
    end
    return dst
end
--- Split a version string into numeric parts
return Utils
