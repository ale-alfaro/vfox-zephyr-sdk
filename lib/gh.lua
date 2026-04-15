local M = {}

GITHUB_USER = "zephyrproject-rtos"
GITHUB_REPO = "sdk-ng"
TOOLCHAIN_RELEASES_BASE_URL =
    Utils.fs.join_path("https://api.github.com", "repos", GITHUB_USER, GITHUB_REPO, "releases")

TOOLCHAIN_DOWNLOADS_BASE_URL = Utils.fs.join_path(TOOLCHAIN_RELEASES_BASE_URL, "downloads")
TOOLCHAIN_ASSETS_BASE_URL = Utils.fs.join_path(TOOLCHAIN_RELEASES_BASE_URL, "assets")
local MIN_VERSION = "3.0.0"
local MAX_VERSION = "3.2.1"
---
---@class GhListReleasesPayload
---@field name string
---@field tag_name string
---@field draft boolean
---@field prerelease boolean

---@class GhAssetPayload
---@field name string
---@field id string
---@field checksum string
---@field download_url string
--[[
-- Example JSON:
     "tag_name": "v1.0.1",
     "name": "Zephyr SDK 1.0.1",
     "draft": false,
     "prerelease": false,
     "assets": [
       {
         "url": "https://api.github.com/repos/zephyrproject-rtos/sdk-ng/releases/assets/381890506",
         "id": 381890506,
         "name": "hosttools_linux-aarch64.tar.xz",
         "digest": "sha256:c08e11efa5076b8e5a80e15f1923fdec4d87894259cee48ce85693dcb90dfb01",
          ...
       },
       ...
--]]

--- @param tool string
--- @param version string
--- @param install_path string
--- @param downloads_dir string
M.get_asset_for_tool = function(tool, version, install_path, downloads_dir)
    Utils.validate("tool", tool, "string")
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("downloads_dir", downloads_dir, "string")

    Utils.inf("Getting asset for tool with version", { tool = tool, version = version })
    local tag = version:gsub("^([%d%.]+)$", "v%1") or version
    local extmap = {
        ["windows"] = ".7z",
        ["macos"] = ".tar.xz",
        ["linux"] = ".tar.xz",
    }

    Utils.net.platform_idents({ ext = extmap })
    local asset_pattern = Utils.net.platform_create_string("zephyr-sdk-{version}_{osname}-{arch}_minimal{ext}")
    local url = Utils.fs.join_path(TOOLCHAIN_ASSETS_BASE_URL, tag, asset_pattern)
    Utils.inf("URL: ", { url = url })
    if not url then
        Utils.wrn("Unsupported platform for nrfutil", { platform = key })
        return nil
    end
    -- try_get: returns (resp, nil) on success, (nil, err_string) on failure
    local bundles = Utils.net.archived_asset_download(url, install_path, downloads_dir)

    if #bundles == 0 then
        Utils.wrn("JSON payload did not have any content", { bundles = bundles })
        return nil
    end
    return Utils.tbl_map(function(release)
        local meta = release.metadata or {}
        local download_url = (meta.filename ~= nil) and Utils.fs.join_path(TOOLCHAIN_BUNDLES_BASE_URL, meta.filename)
            or ""
        local bundle = {
            version = release.key or "",
            checksum = meta.version or "",
            download_url = download_url,
        }
        return bundle
    end, bundles)
end
---@return string[] versions
M.fetch_releases = function()
    local semver = require("semver")
    local result = Utils.net.get_json_payload(
        TOOLCHAIN_RELEASES_BASE_URL,
        ---@param release GhListReleasesPayload
        ---@return boolean
        function(release)
            local version = release.tag_name:gsub("^v", "")
            local is_not_official = version:match("-([%w%d]+)$")
            if is_not_official or release.prerelease or release.draft then
                return false
            end
            if semver.compare(version, MIN_VERSION) < 0 then
                return false
            end
            return true
        end
    )

    if type(result) ~= "table" or #result == 0 then
        Utils.fatal("JSON payload did not have any content", result)
    end
    return Utils.tbl_map(function(release)
        local version = release.tag_name:gsub("^v", "")
        return version
    end, result)
end

return M
