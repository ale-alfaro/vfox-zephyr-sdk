M = {}
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

GITHUB_USER = "zephyrproject-rtos"
GITHUB_REPO = "sdk-ng"
MIN_VERSION = "0.17.0"
--

---@return string
local function get_platform_component()
    local os_name = RUNTIME.osType:lower()
    local arch = RUNTIME.archType

    local platform_map = {
        ["darwin"] = {
            ["arm64"] = "macos-aarch64",
        },
        ["linux"] = {
            ["amd64"] = "linux-x86_64",
            ["arm64"] = "linux-aarch64",
        },
        ["windows"] = {
            ["amd64"] = "windows-x86_64",
        },
    }

    local os_map = platform_map[os_name]
    if os_map then
        return os_map[arch] or "linux-x86_64" -- fallback
    end

    -- Default fallback
    return "linux-x86_64"
end
---@return string
local function get_platform_archive_extension()
    local ext = RUNTIME.osType:lower() == "windows" and "7z" or "tar.xz"
    return ext
end
--- @param components string[]
---@return string
local function gh_api(components)
    return table.concat({ "https://api.github.com", "repos", GITHUB_USER, GITHUB_REPO, unpack(components) }, "/")
end
--- Downloads a file and raises on failure.
---@param url string
---@param filter_fn? fun(table):boolean?
---@return table
local function get_json_payload(url, filter_fn)
    local http = require("http")
    local json = require("json")

    local resp, err = http.get({ url = url })

    if err ~= nil then
        Utils.err("Failed to do to HTTP GET: " .. err)
    end
    if resp.status_code ~= 200 then
        Utils.err("GitHub API returned status " .. resp.status_code .. ": " .. resp.body)
    end

    local success, result = pcall(json.decode, resp.body)
    if not success then
        Utils.err("Failed to parse JSON: " .. result)
    end
    if not filter_fn then
        return result
    end
    local filtered = Utils.tbl_filter(filter_fn, result)
    return filtered
end

---@param asset_id string
---@param asset_name string
---@param install_path? string
local function asset_download(asset_id, asset_name, install_path, download_path)
    local http = require("http")
    local path = require("pathlib")
    local archiver = require("archiver")
    local archive_path = path.Path({ download_path, asset_name })
    local err = http.download_file({
        url = gh_api({ "releases", "assets", asset_id }),
        headers = {
            ["Accept"] = "application/octet-stream",
            ["X-GitHub-Api-Version"] = "2026-03-10",
        },
    }, archive_path)

    if err ~= nil then
        Utils.err("Download failed: " .. err)
    end
    if not install_path then
        return
    end
    -- ── Extract archive ─────────────────────────────────────────────────
    Utils.inf("Extracting archive to install path", { archive_path = archive_path, install_path = install_path })
    err = archiver.decompress(archive_path, install_path)
    if err ~= nil then
        Utils.err("Extraction failed (" .. archive_path .. "): " .. err)
    end
end
--- @param tool string
--- @param version string
--- @param install_path string
--- @param download_path string
M.get_asset_for_tool = function(tool, version, install_path, download_path)
    local err = Utils.err
    local inf = Utils.inf
    inf("Getting asset for tool with version", { tool = tool, version = version })
    local tag = version:gsub("^([%d%.]+)$", "v%1") or version
    local ext = "." .. get_platform_archive_extension()
    local asset_pattern = table.concat({ get_platform_component(), tool .. ext }, "_")

    local release_url = gh_api({ "releases", "tags", tag })
    inf("Release url", release_url, "asset pattern", asset_pattern)
    local result = get_json_payload(release_url)
    if not type(result) == "table" or not result.assets or #result.assets == 0 then
        err("JSON payload did not have any content", { result = result })
    end

    local payload = Utils.list_filter(function(asset)
        if not type(asset) == "table" or not asset["name"] then
            return false
        end
        local asset_name = asset["name"]
        return require("strings").has_suffix(asset_name, asset_pattern)
    end, result.assets)

    local assets = Utils.list_map(function(node)
        return {
            name = node.name,
            id = node.id,
            checksum = node.digest,
            download_url = node.url,
        }
    end, payload)
    Utils.inf("Assets: ", { assets = assets })
    local asset = assets[1]
    if not type(asset) == "table" then
        Utils.fatal("Found more than one possible asset")
    end

    asset_download(asset.id, asset.name, install_path, download_path)
end
---@return string[] versions
M.fetch_releases = function()
    local semver = require("semver")
    local result = get_json_payload(
        gh_api({ "releases" }),
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

    if not type(result) == "table" or #result == 0 then
        print("JSON payload did not have any content", result)
        error("Empty json payload")
    end
    return Utils.tbl_map(function(release)
        local version = release.tag_name:gsub("^v", "")
        return version
    end, result)
end

return M
