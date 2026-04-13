local M = {}
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
local strings = require("strings")
GITHUB_API_URL = strings.join({ "https://api.github.com", "repos", GITHUB_USER, GITHUB_REPO }, "/")
--
---@alias GhApiRequestType
---| 'GET'
---| 'DOWNLOAD'

---@class GhApiOpts
---@field reqType GhApiRequestType

--- @param components string[]
--- @param opts GhApiOpts
---@return HttpRequestOpts
local function gh_api(components, opts)
    Utils.validate("components", components, Utils.islist)
    Utils.validate("opts", opts, "table")
    Utils.validate("reqType", opts.reqType, function(req)
        return req == "GET" or req == "DOWNLOAD"
    end)
    -- local sh = require("utils.sh")
    local application_header = opts.reqType == "GET" and "application/json" or "application/octet-stream"
    local headers = {
        ["Accept"] = application_header,
        ["X-GitHub-Api-Version"] = "2022-11-28",
    }

    -- if GITHUB_TOKEN then
    --     CACHED_GH_TOKEN = GITHUB_TOKEN or assert(sh.safe_exec({ "gh", "auth", "token" }, { fail = true }))
    --
    --     if not CACHED_GH_TOKEN:find("^gh[op]_") then
    --         Utils.wrn("Invalid token")
    --         CACHED_GH_TOKEN = nil
    --     end
    -- end
    -- if CACHED_GH_TOKEN then
    --     headers["Authorization"] = "Bearer " .. CACHED_GH_TOKEN
    -- end
    return {
        url = strings.join({ GITHUB_API_URL, unpack(components) }, "/"),
        headers = headers,
    }
end

---@param asset_id string
---@param archive_path string
local function gh_api_download_asset(asset_id, archive_path)
    Utils.validate("asset_id", asset_id, "string")
    Utils.validate("archive_path", archive_path, "string")

    local http = require("http")
    local err = http.download_file(gh_api({ "releases", "assets", asset_id }, { reqType = "DOWNLOAD" }), archive_path)
    if err ~= nil then
        Utils.fatal("Download failed: " .. err)
    end
end

---@param asset_id string
---@param install_path string
---@param download_path string
local function asset_download(asset_id, install_path, download_path)
    Utils.validate("asset_id", asset_id, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")
    local archiver = require("archiver")
    gh_api_download_asset(asset_id, download_path)
    -- ── Extract archive ─────────────────────────────────────────────────
    Utils.inf("Extracting archive to install path", { download_path = download_path, install_path = install_path })
    local err = archiver.decompress(download_path, install_path)
    if err ~= nil then
        Utils.fatal("Extraction failed (" .. download_path .. "): " .. err)
    end
end

--- Downloads a file and raises on failure.
---@param url string[]
---@param filter_fn? fun(table):boolean?
---@param key_to_filter? string
---@return table
local function get_json_payload(url, filter_fn, key_to_filter)
    Utils.validate("url", url, Utils.islist)
    Utils.validate("filter_fn", filter_fn, "function", true)
    Utils.validate("key_to_filter", key_to_filter, "string", true)
    local http = require("http")
    local json = require("json")

    local resp, err = http.get(gh_api(url, { reqType = "GET" }))

    if err ~= nil then
        Utils.fatal("Failed to do to HTTP GET: " .. err)
    end
    if resp.status_code ~= 200 then
        Utils.fatal("GitHub API returned status " .. resp.status_code .. ": " .. resp.body)
    end

    local success, result = pcall(json.decode, resp.body)
    if not success then
        Utils.fatal("Failed to parse JSON: " .. result)
    end
    if not filter_fn then
        return result
    end
    local filterable_result = key_to_filter and result[key_to_filter] or result
    return Utils.tbl_filter(filter_fn, filterable_result)
end
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
    local ext = "." .. get_platform_archive_extension()
    local asset_pattern = table.concat({ get_platform_component(), tool .. ext }, "_")

    Utils.inf("Release asset pattern", { tag = tag, asset_pattern = asset_pattern })
    local result = get_json_payload({ "releases", "tags", tag }, function(asset)
        if type(asset) ~= "table" or not asset["name"] then
            return false
        end
        local asset_name = asset["name"]
        return strings.has_suffix(asset_name, asset_pattern)
    end, "assets")
    if type(result) ~= "table" or #result == 0 then
        Utils.fatal("JSON payload did not have any content", { result = result })
    end

    local assets = Utils.list_map(function(node)
        return {
            name = node.name,
            id = node.id,
            checksum = node.digest,
            download_url = node.url,
        }
    end, result)
    Utils.inf("Assets: ", { assets = assets })
    local asset = assets[1]
    if type(asset) ~= "table" then
        Utils.fatal("Found more than one possible asset")
    end

    local archive_path = Utils.file.join_path(downloads_dir, asset.name)
    asset_download(tostring(asset.id), install_path, archive_path)
end
---@return string[] versions
M.fetch_releases = function()
    local semver = require("semver")
    local result = get_json_payload(
        { "releases" },
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
