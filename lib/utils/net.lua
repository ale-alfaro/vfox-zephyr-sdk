---@module 'http'
local M = {}
M.http = require("http")
--
---@alias GhApiRequestType
---| 'GET'
---| 'DOWNLOAD'
---
local GITHUB_API_URL = "https://api.github.com"
local GITHUB_REPOS_URL = Utils.fs.join_path(GITHUB_API_URL, "repos")

---@class GhApiOpts
---@field reqType GhApiRequestType
---@field token? string
---

---@class GhListReleasesPayload
---@field name string
---@field tag_name string
---@field draft boolean
---@field prerelease boolean

---@class PlatformInfo
---@field osname string
---@field arch string
---@field ext {archive:string,executable:string}
--- Returns the executable suffix for the current OS.
---@return string
local function get_platform_exe_suffix()
    return RUNTIME.osType:lower() == "windows" and ".exe" or ""
end

local function get_platform_archive_suffix()
    return RUNTIME.osType:lower() == "windows" and ".zip" or ".tar.gz"
end

_G.PLATFORM_MAP = _G.PLATFORM_MAP or {}
---@param overrides? PlatformInfo
---@return PlatformInfo
M.platform_idents = function(overrides)
    local os_map = {
        ["darwin"] = "macos",
    }
    local arch_map = {
        ["amd64"] = "x86_64",
        ["arm64"] = "aarch64",
    }
    if not _G.PLATFORM_MAP["osname"] then
        _G.PLATFORM_MAP = {
            osname = os_map[RUNTIME.osType:lower()] or RUNTIME.osType:lower(),
            arch = arch_map[RUNTIME.archType:lower()] or RUNTIME.archType:lower(),
            extensions = { archive = get_platform_archive_suffix(), executable = get_platform_exe_suffix() },
        }
    end
    if overrides then
        _G.PLATFORM_MAP = Utils.tbl_extend("force", _G.PLATFORM_MAP, overrides)
    end
    return _G.PLATFORM_MAP
end

local template_string_placeholders = {
    ["os"] = "osname",
    ["arch"] = "arch",
    ["ext"] = "ext",
}
local function lua_pattern_escape(value)
    local str = tostring(value or "")
    -- for _, magic in ipairs(lua_magic_chars) do
    --     str = str:gsub('([%.%(%)%[%]%%%^%$%*%+%-%?])', "%%1")
    -- end
    return str.gsub(str:gsub("([%.%(%)%[%]%%%^%$%*%+%-%?])", "%%%1"), "%%", "")
end
---@alias FileExtensionType
---| 'archive'
---| 'executable'

---@param template string
---@param exttype? FileExtensionType
---@return string
M.platform_create_string = function(template, exttype)
    template = lua_pattern_escape(template)
    for placeholder, repl_id in pairs(template_string_placeholders) do
        local repl = _G.PLATFORM_MAP[repl_id] or ""
        if exttype and repl_id == "ext" then
            repl = _G.PLATFORM_MAP.ext[exttype]
        end
        template = string.gsub(template, "{" .. placeholder .. "}", repl)
    end
    return template
end

--- @param repo string
--- @param components string
--- @param opts GhApiOpts
---@return HttpRequestOpts
local function gh_api(repo, components, opts)
    Utils.validate("repo", repo, "string")
    Utils.validate("components", components, "string")
    Utils.validate("opts", opts, "table")
    Utils.validate("reqType", opts.reqType, function(req)
        return req == "GET" or req == "DOWNLOAD"
    end)
    local gh_token = os.getenv("GITHUB_TOKEN") or ""
    local application_header = opts.reqType == "GET" and "application/vnd.github+json" or "application/octet-stream"
    local headers = {
        ["Accept"] = application_header,
        ["X-GitHub-Api-Version"] = "2026-03-10",
        ["User-Agent"] = "mise-plugin",
    }
    if gh_token ~= "" then
        headers["Authorization"] = string.format("Bearer: %s", gh_token)
    end
    local url = Utils.fs.join_path(GITHUB_REPOS_URL, repo, components)
    return {
        url = url,
        headers = headers,
    }
end

---@param repo string
---@param asset_id string
---@param install_path string
---@param download_path string
---@return string
function M.github_asset_download(repo, asset_id, install_path, download_path)
    Utils.validate("asset_id", asset_id, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")

    local archiver = require("archiver")
    local err = M.http.download_file(
        gh_api(repo, Utils.fs.join_path({ "releases", "assets", asset_id }), { reqType = "DOWNLOAD" }),
        download_path
    )
    if err ~= nil then
        Utils.fatal("Download failed: " .. err)
    end
    Utils.inf("Extracting archive to install path", { download_path = download_path, install_path = install_path })
    err = archiver.decompress(download_path, install_path)
    if err ~= nil then
        Utils.fatal("Extraction failed (" .. download_path .. "): " .. err)
    end
    return install_path
end

--- Fetch available SDK release versions from GitHub.
--- Filters out pre-releases, drafts, and versions below MIN_VERSION.
---@param repo string
---@param min_version string
---@return table releases
M.github_fetch_releases = function(repo, min_version)
    local semver = require("semver")
    local req_opts = { reqType = "GET" }
    local request = gh_api(repo, "releases", req_opts)
    local result = Utils.net.get_json_payload(
        request,
        ---@param release GhListReleasesPayload
        ---@return boolean
        function(release)
            local version = release.tag_name:gsub("^v", "")
            local is_not_official = version:match("-([%w%d]+)$")
            if is_not_official or release.prerelease or release.draft then
                return false
            end
            if semver.compare(version, min_version) < 0 then
                return false
            end
            return true
        end
    )

    if type(result) ~= "table" or #result == 0 then
        Utils.fatal("JSON payload did not have any content", result)
    end
    return result
end
---@param install_dir string
---@param archive_path string
---@param components number
---@return string?
function M.decompres_strip_components(archive_path, install_dir, components)
    Utils.inf(
        "Extracting SDK and stripping components",
        { archive = archive_path, dest = install_dir, components = components }
    )
    Utils.sh.safe_exec(
        string.format("tar xvf %q --directory %q --strip-components=%d", archive_path, install_dir, components),
        { fail = true }
    )

    os.remove(archive_path)
end

---@param url string
---@param install_dir string
---@param download_dir string
---@param asset_opts? {name:string,ext:string, strip_components:integer?}
---@return string?
function M.archived_asset_download(url, install_dir, download_dir, asset_opts)
    Utils.validate("url", url, "string")
    Utils.validate("install_dir", install_dir, "string")
    Utils.validate("download_dir", download_dir, "string")
    Utils.validate("asset_name", asset_opts, "table", true)
    local archiver = require("archiver")
    asset_opts = asset_opts or {}
    local archive_name = url:match(".*/(%S+)$")
    local archive_ext = asset_opts.ext or get_platform_archive_suffix()
    local asset_name = asset_opts.name or archive_name:gsub(archive_ext, "")
    -- try_download_file: returns (true, nil) on success, (nil, err_string) on failure
    local packaged_asset = Utils.fs.join_path(download_dir, archive_name)
    local asset = Utils.fs.join_path(install_dir, asset_name)
    local _ok, err = M.http.try_download_file({
        url = url,
    }, packaged_asset)
    if err ~= nil then
        Utils.err("Extraction failed of archive", { packaged_asset = packaged_asset, err = err })
        return nil
    end
    err = archiver.decompress(packaged_asset, asset)
    if err ~= nil then
        Utils.err("Extraction failed of asset", { asset = asset, err = err })
        return nil
    end
    Utils.inf("Downloaded and extracted asset", { asset = asset })
    return asset
end

---@param url string
---@param install_dir string
---@param exe_name? string
---@return string?
function M.executable_asset_download(url, install_dir, exe_name)
    Utils.validate("url", url, "string")
    Utils.validate("install_dir", install_dir, "string")
    Utils.validate("asset_name", exe_name, "string", true)
    exe_name = exe_name or url:match(".*/(%S+)$")
    -- try_download_file: returns (true, nil) on success, (nil, err_string) on failure
    local exe_ext = exe_name:match(".*(.%%S+)$") or get_platform_exe_suffix()
    if exe_ext ~= "" and not Utils.strings.has_suffix(exe_name, exe_ext) then
        exe_name = exe_name .. exe_ext
    end
    local asset = Utils.fs.join_path(install_dir, exe_name)
    local _ok, err = M.http.try_download_file({
        url = url,
    }, asset)
    if err ~= nil then
        Utils.err("Download failed: " .. err)
        return nil
    end
    Utils.inf("Downloaded and extracted asset", { asset = asset })
    return asset
end
--- Downloads a file and raises on failure.
---@param request string|HttpRequestOpts
---@param filter_fn? fun(table):boolean?
---@param key_to_filter? string
---@return table?
function M.get_json_payload(request, filter_fn, key_to_filter)
    Utils.validate("request", request, { "string", "table" })
    Utils.validate("filter_fn", filter_fn, "function", true)
    Utils.validate("key_to_filter", key_to_filter, "string", true)
    local json = require("json")
    local http = require("http")
    Utils.inf("Request:", { request = request })
    local resp, err
    if type(request) == "table" then
        resp, err = http.try_get(request)
    elseif type(request) == "string" then
        resp, err = http.try_get({ url = request, headers = {
            ["User-Agent"] = "mise-plugin",
        } })
    else
        error("Invalid request")
    end

    if err ~= nil then
        Utils.fatal("Failed to do to HTTP GET, UNKNOWN_ERR")
        return nil
    end

    if resp.status_code ~= 200 then
        Utils.err("Failed to do to HTTP GET: with error code: " .. resp.status_code)
        return nil
    end
    local success, result = pcall(json.decode, resp.body)
    if not success then
        Utils.fatal("Failed to parse JSON: " .. result)
        return nil
    end
    if not filter_fn then
        return result
    end
    if key_to_filter then
        return Utils.tbl_filter(filter_fn, result[key_to_filter])
    end
    Utils.inf("Payload:", { res = result })
    return Utils.tbl_filter(filter_fn, result)
end

return M
