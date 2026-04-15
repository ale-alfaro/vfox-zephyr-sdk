local M = {}
M.http = require("http") ---@module 'http'
--
---@alias GhApiRequestType
---| 'GET'
---| 'DOWNLOAD'

---@class GhApiOpts
---@field reqType GhApiRequestType

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
    return {
        url = Utils.strings.join({ GITHUB_API_URL, unpack(components) }, "/"),
        headers = headers,
    }
end

---@param asset_id string
---@param install_path string
---@param download_path string
function M.github_asset_download(asset_id, install_path, download_path)
    Utils.validate("asset_id", asset_id, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")

    local archiver = require("archiver")
    local err =
        M.http.download_file(gh_api({ "releases", "assets", asset_id }, { reqType = "DOWNLOAD" }), download_path)
    if err ~= nil then
        Utils.fatal("Download failed: " .. err)
    end
    Utils.inf("Extracting archive to install path", { download_path = download_path, install_path = install_path })
    err = archiver.decompress(download_path, install_path)
    if err ~= nil then
        Utils.fatal("Extraction failed (" .. download_path .. "): " .. err)
    end
end

---@param url string
---@param install_dir string
---@param download_dir string
---@param asset_name? string
---@return string?
function M.archived_asset_download(url, install_dir, download_dir, asset_name)
    Utils.validate("url", url, "string")
    Utils.validate("install_dir", install_dir, "string")
    Utils.validate("download_dir", download_dir, "string")
    Utils.validate("asset_name", asset_name, "string", true)
    local archiver = require("archiver")
    asset_name = asset_name or url:match(".*/(%S+)$")
    -- try_download_file: returns (true, nil) on success, (nil, err_string) on failure
    local archive_ext = get_platform_archive_suffix()
    local packaged_asset_name = asset_name
    if not Utils.strings.has_suffix(packaged_asset_name, archive_ext) then
        local extensionless = asset_name:match("(%S+).%.*")
        packaged_asset_name = extensionless .. archive_ext
    end
    local packaged_asset = Utils.fs.join_path(download_dir, packaged_asset_name)
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
---@param url string[]
---@param filter_fn? fun(table):boolean?
---@param key_to_filter? string
---@return table?
function M.get_json_payload(url, filter_fn, key_to_filter)
    Utils.validate("url", url, "string")
    Utils.validate("filter_fn", filter_fn, "function", true)
    Utils.validate("key_to_filter", key_to_filter, "string", true)
    local json = require("json")

    local resp, err = M.http.try_get({
        url = url,
        header = { ["User-Agent"] = "mise-plugin" },
    })

    if err ~= nil then
        Utils.wrn("Failed to do to HTTP GET: " .. err)
        return nil
    end

    local success, result = pcall(json.decode, resp.body)
    if not success then
        Utils.wrn("Failed to parse JSON: " .. result)
        return nil
    end
    if not filter_fn then
        return result
    end
    if key_to_filter then
        return Utils.tbl_filter(filter_fn, result[key_to_filter])
    end
    Utils.dbg("Payload:", { res = result })
    return Utils.tbl_filter(filter_fn, result)
end

return M
