---@module 'http'
local M = {}
M.http = require("http")
--
local GITHUB_API_URL = "https://api.github.com"
local GITHUB_REPOS_URL = Utils.fs.join_path(GITHUB_API_URL, "repos")

-- ─── Download with progress ─────────────────────────────────────────

--- Check once whether curl is available in PATH.
--- Caches the result so we only shell out once per plugin invocation.
---@return boolean
local _has_curl
local function has_curl()
    if _has_curl == nil then
        _has_curl = os.execute("curl --version >/dev/null 2>&1") == 0
        if not _has_curl then
            Utils.dbg("curl not found in PATH, downloads will use built-in http (no progress bar)")
        end
    end
    return _has_curl
end

--- Download a file using curl with a visible progress bar.
--- curl writes progress to stderr, which passes through to the terminal.
--- Falls back to mise's http.try_download_file if curl is not available.
---@param url string Download URL
---@param dest string Destination file path
---@param headers? table<string, string> Optional HTTP headers
---@return boolean ok
---@return string? err
function M.download_with_progress(url, dest, headers)
    Utils.validate("url", url, "string")
    Utils.validate("dest", dest, "string")

    if has_curl() then
        -- Build curl command with progress bar
        local parts = { "curl", "-fSL", "--progress-bar", "-o", string.format("%q", dest) }
        if headers then
            for k, v in pairs(headers) do
                parts[#parts + 1] = "-H"
                parts[#parts + 1] = string.format("%q", k .. ": " .. v)
            end
        end
        parts[#parts + 1] = string.format("%q", url)
        local curl_cmd = table.concat(parts, " ")

        Utils.dbg("Downloading with progress", { cmd = curl_cmd })
        local exit_code = os.execute(curl_cmd)
        if exit_code == 0 then
            return true, nil
        end
        Utils.wrn("curl download failed, falling back to built-in http", { exit_code = exit_code })
    end

    -- Fallback: built-in http (no progress bar)
    local success, err = M.http.try_download_file({ url = url, headers = headers or {} }, dest)
    if not success then
        return false, err
    end
    return true, nil
end

---

--- @param repo string
--- @param components string
--- @param opts GhApiOpts
---@return HttpRequestOpts
function M.gh_api(repo, components, opts)
    Utils.validate("repo", repo, "string")
    Utils.validate("components", components, "string")
    Utils.validate("opts", opts, "table")
    Utils.validate("reqType", opts.reqType, function(req)
        return req == "GET" or req == "DOWNLOAD"
    end)
    local gh_token = os.getenv("GITHUB_TOKEN") or os.getenv("MISE_GITHUB_TOKEN") or ""
    local application_header = opts.reqType == "GET" and "application/vnd.github+json" or "application/octet-stream"
    local headers = {
        ["Accept"] = application_header,
        ["X-GitHub-Api-Version"] = "2026-03-10",
        ["User-Agent"] = "mise-plugin",
    }
    if gh_token ~= "" then
        headers["Authorization"] = string.format("Bearer %s", gh_token)
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
    local api_opts = M.gh_api(repo, Utils.fs.join_path("releases", "assets", asset_id), { reqType = "DOWNLOAD" })
    local ok, err = M.download_with_progress(api_opts.url, download_path, api_opts.headers)
    if not ok then
        Utils.fatal("Download failed: ", { err = err })
    end
    Utils.dbg("Extracting archive to install path", { download_path = download_path, install_path = install_path })
    err = archiver.decompress(download_path, install_path)
    if err ~= nil then
        Utils.fatal("Extraction failed", { download = download_path, err = err })
    end
    return install_path
end

---@param install_dir string
---@param archive_path string
---@param components number
function M.decompress_strip_components(archive_path, install_dir, components)
    Utils.validate("archive_path", archive_path, "string")
    Utils.validate("install_dir", install_dir, "string")
    Utils.validate("components", components, "number")
    Utils.dbg(
        "Extracting SDK and stripping components",
        { archive = archive_path, dest = install_dir, components = components }
    )
    Utils.sh.exec(
        { "tar", "xvf", archive_path, "--directory", install_dir, "--strip-components=" .. components },
        { fail = true }
    )

    os.remove(archive_path)
end

---@param url string
---@param install_dir string
---@param download_dir string
---@param asset_opts? {name:string, strip_components:integer?}
---@return string?
function M.archived_asset_download(url, install_dir, download_dir, asset_opts)
    Utils.validate("url", url, "string")
    Utils.validate("install_dir", install_dir, "string")
    Utils.validate("download_dir", download_dir, "string")
    Utils.validate("asset_name", asset_opts, "table", true)
    local archiver = require("archiver")
    local archive_name = url:match(".*/(%S+)$")

    asset_opts = asset_opts or {}
    local packaged_asset = Utils.fs.join_path(download_dir, archive_name)
    local ok, err = M.download_with_progress(url, packaged_asset)
    if not ok then
        Utils.err("Download failed of archive", { packaged_asset = packaged_asset, err = err })
        return nil
    end
    if asset_opts.strip_components then
        M.decompress_strip_components(packaged_asset, install_dir, asset_opts.strip_components)
        return install_dir
    else
        local asset = Utils.fs.join_path(install_dir, asset_opts.name or archive_name:gsub("(%.%w+)", ""))
        err = archiver.decompress(packaged_asset, asset)
        if err ~= nil then
            Utils.err("Extraction failed of asset", { asset = asset, err = err })
            return nil
        end
        Utils.inf("Downloaded and extracted asset", { asset = asset })
        return asset
    end
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
    local exe_ext = exe_name:match(".*(.%%S+)$") or ((RUNTIME.osType:lower() == "windows") and ".7z" or "")
    if exe_ext ~= "" and not Utils.strings.has_suffix(exe_name, exe_ext) then
        exe_name = exe_name .. exe_ext
    end
    local asset = Utils.fs.join_path(install_dir, exe_name)
    local ok, err = M.download_with_progress(url, asset)
    if not ok then
        Utils.err("Download failed: " .. (err or "unknown error"))
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
    Utils.dbg("Request:", { request = request })
    local resp, err
    if type(request) == "table" then
        resp, err = http.try_get(request)
    elseif type(request) == "string" then
        resp, err = http.try_get({
            url = request,
            headers = {
                ["User-Agent"] = "mise-plugin",
            },
        })
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
    Utils.dbg("Payload:", { res = result })
    return Utils.tbl_filter(filter_fn, result)
end
return M
