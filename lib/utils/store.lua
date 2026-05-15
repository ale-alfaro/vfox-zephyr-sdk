local M = {
    ---@type table<Version,table>
    cache = {},
}

local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds
---@param file string
---@return boolean
local function timestamp_check_for_freshness(file)
    local now = os.time()
    local file_ts = Utils.sh.exec({ "stat", "--format='%W'", file })
    local rem = (now - file_ts)
    return rem < cache_ttl
end

---@param data table
---@param store_name string
---@return string?
function M.store_table(data, store_name)
    Utils.validate("data", data, "table")
    Utils.validate("store_name", store_name, "string")
    local store_json = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    if Utils.fs.exists(store_json) and timestamp_check_for_freshness(store_json) then
        Utils.dbg("Returning stored data as it is still fresh")
        return nil
    end

    local json = require("json")
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        error("Failed to encode bundles")
    end
    -- Write and execute the script
    local store_json = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    local f = io.open(store_json, "w")
    if not f then
        error("Failed to create installation script")
    end
    f:write(encoded)
    f:close()
    return store_json
end

---@param store_name string
---@param fetch_fn AssetBundleFetchFn
---@return table<Version,ToolchainBundle[]>?
function read_store(store_name, fetch_fn)
    Utils.validate("store_name", store_name, "string")
    Utils.validate("fetch_releases_fn", fetch_fn, "function")
    local json = require("json")
    local store_json = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    local store = {}
    local ok
    if Utils.fs.exists(store_json) and timestamp_check_for_freshness(store_json) then
        Utils.inf("Store exists already and is fresh, returning values stored there")
        local store_content = Utils.file.read(store_json)
        ok, store = pcall(json.decode, store_content)
        if not ok then
            error("Failed to decode bundles")
        end
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
