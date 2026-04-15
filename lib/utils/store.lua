local M = {}
---@param data table
---@param store_name string
---@return string?
function M.store_table(data, store_name)
    Utils.validate("data", data, "table")
    Utils.validate("store_name", store_name, "string")
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

return M
