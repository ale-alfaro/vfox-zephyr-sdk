local M = {}

---@param store_name string
---@return boolean
function M.store_exists(store_name)
    local store_json = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    return Utils.fs.exists(store_json)
end

local cache_ttl = 12 * 60 * 60 -- 12 hours in seconds
---@param data table
---@return boolean,number
local function timestamp_check_for_freshness(data)
    local now = os.time()

    if data.timestamp and (now - data.timestamp) < cache_ttl then
        return true, now
    end

    return false, now
end

---@param data table
---@param store_name string
---@return string?
function M.store_table(data, store_name)
    Utils.validate("data", data, "table")
    Utils.validate("store_name", store_name, "string")
    if M.store_exists(store_name) then
        local is_fresh, ts = timestamp_check_for_freshness(data)
        if is_fresh then
            Utils.dbg("Returning stored data as it is still fresh")
            return nil
        else
            data.timestamp = ts
        end
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
---@return table?
function M.read_table(store_name)
    Utils.validate("store_name", store_name, "string")
    if not M.store_exists(store_name) then
        Utils.dbg("Store does not exist with key : " .. store_name)
        return nil
    end
    -- Run the Poetry installer via bash script
    -- Write and execute the script
    local json = require("json")
    local store_json = Utils.fs.join_path(RUNTIME.pluginDirPath, string.format("%s_store.json", store_name))
    local store_content = Utils.file.read(store_json)
    local ok, decoded = pcall(json.decode, store_content)
    if not ok then
        error("Failed to decode bundles")
    end
    return decoded
end
---@param store_name string
---@param fetch_fn AssetBundleFetchFn
---@return string[]?
function M.fetch_versions(store_name, fetch_fn)
    Utils.validate("store_name", store_name, "string")
    Utils.validate("fetch_releases_fn", fetch_fn, "function")
    if Utils.store.store_exists(store_name) then
        Utils.dbg("Store exists already, returning values stored there")
        local assets = Utils.store.read_table(store_name)
        if not assets then
            Utils.fatal("Could not get asset store")
            return {}
        end
        return Utils.tbl_keys(assets)
    end
    local bundles = fetch_fn()
    if not bundles then
        return {}
    end
    local versions = {} ---@as string[]
    local cache = {} ---@as table<Version,table>
    for _, bundle in Utils.semver.spairs(bundles) do
        cache[bundle.version] = bundle
        versions[#versions + 1] = bundle.version
    end

    Utils.store.store_table(cache, store_name)
    Utils.dbg("Versions", { versions = versions })
    return versions
end
---@param store_name string
---@param version string
---@return ToolchainBundle?
function M.fetch_asset_bundles(store_name, version)
    local bundles = M.read_table(store_name)

    if not bundles then
        Utils.err("Could not get bundle cache", { version = version })
        return nil
    end

    local bundle = bundles[version]
    if not bundle then
        Utils.err("Could not find bundle in cache ", { version = version })
        return nil
    end
    return bundle
end
return M
