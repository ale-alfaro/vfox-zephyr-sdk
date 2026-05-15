local M = {
    ---@type table<Version,table>
    cache = {},
}

local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds

local function store_paths(store_name)
    local json_path = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    local ts_path = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.ts", store_name))
    return json_path, ts_path
end

---@param ts_path string
---@return boolean
local function is_fresh(ts_path)
    if not Utils.fs.exists(ts_path) then
        return false
    end
    local content = Utils.file.read(ts_path)
    local ts = tonumber(content)
    if not ts then
        return false
    end
    local age = os.time() - ts
    return age >= 0 and age < cache_ttl
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then
        error("Failed to open " .. path .. " for writing")
    end
    f:write(content)
    f:close()
end

---@param data table
---@param store_name string
---@return string?
function M.store_table(data, store_name)
    Utils.validate("data", data, "table")
    Utils.validate("store_name", store_name, "string")
    local store_json, store_ts = store_paths(store_name)

    local json = require("json")
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        error("Failed to encode bundles")
    end
    write_file(store_json, encoded)
    write_file(store_ts, tostring(os.time()))
    return store_json
end

---@param store_name string
---@param fetch_fn AssetBundleFetchFn
---@return table<Version,ToolchainBundle[]>?
local function read_store(store_name, fetch_fn)
    Utils.validate("store_name", store_name, "string")
    Utils.validate("fetch_releases_fn", fetch_fn, "function")
    local json = require("json")
    local store_json, store_ts = store_paths(store_name)
    local store = {}
    if Utils.fs.exists(store_json) and is_fresh(store_ts) then
        Utils.inf("Store exists already and is fresh, returning values stored there")
        local ok, decoded = pcall(json.decode, Utils.file.read(store_json))
        if not ok then
            error("Failed to decode bundles")
        end
        store = decoded
    else
        Utils.inf("Fetching new bundle store")
        local bundles = fetch_fn()
        if not bundles then
            Utils.wrn("Could not fetch bundles online")
            return nil
        end
        for _, bundle in Utils.semver.spairs(bundles) do
            store[bundle.version] = bundle
        end
        Utils.store.store_table(store, store_name)
    end
    return store
end
---@param store_name string
---@param fetch_fn AssetBundleFetchFn
---@return Version[]
function M.fetch_versions(store_name, fetch_fn)
    local assets = read_store(store_name, fetch_fn)
    local versions = Utils.tbl_keys(assets or {})
    Utils.dbg("Versions", { versions = versions })
    return versions
end

---@param store_name string
---@param fetch_fn AssetBundleFetchFn
---@param version string
---@return ToolchainBundle?
function M.fetch_toolchain_asset(store_name, fetch_fn, version)
    local assets = read_store(store_name, fetch_fn) or {}
    return assets[version]
end
return M
