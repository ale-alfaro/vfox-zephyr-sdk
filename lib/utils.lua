local Utils = {}

--- Applies function `fn` to all values of table `t`, in `pairs()` iteration order (which is not
--- guaranteed to be stable, even when the data doesn't change).
---@generic T
---@param fn fun(value: T): any Function
---@param t table<any, T> Table
---@return table : Table of transformed values
function Utils.tbl_map(fn, t)
    --- @cast t table<any,any>

    local rettab = {} --- @type table<any,any>
    for k, v in pairs(t) do
        rettab[k] = fn(v)
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
return Utils
