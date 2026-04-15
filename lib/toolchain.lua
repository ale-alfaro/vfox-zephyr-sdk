---@class ZephyrTool
local M = {}

GITHUB_USER = "zephyrproject-rtos"
GITHUB_REPO = "sdk-ng"

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
--- Can be used  to list all  releases and then be filtered by the tag. Look at the assets array property (in jq '.assets | select')
--- gh api \
--  -H "Accept: application/vnd.github+json" \
--  -H "X-GitHub-Api-Version: 2026-03-10" \
--  /repos/zephyrproject-rtos/sdk-ng/releases/tags/v1.0.0 --jq '.assets[] | select(.name | endswith("arm-zephyr-eabi.tar.xz")) | .name as $key | { $key : .url }'
--- The asset download URL can also be found inside the assets.
---
TOOLCHAIN_RELEASES_BASE_URL =
    Utils.fs.join_path("https://api.github.com", "repos", GITHUB_USER, GITHUB_REPO, "releases")

TOOLCHAIN_DOWNLOADS_BASE_URL = Utils.fs.join_path(TOOLCHAIN_RELEASES_BASE_URL, "downloads")
TOOLCHAIN_ASSETS_BASE_URL = Utils.fs.join_path(TOOLCHAIN_RELEASES_BASE_URL, "assets")
local MIN_VERSION = "0.17.0"
---@class ToolchainBundle
---@field  name string
---@field  version string
---@field checksum string
---@field download_url string
---

M.cache = {}

--- @param tool string
--- @param version string
--- @param install_path string
--- @param downloads_dir string
M.get_assets_for_toolchain = function(tool, version, install_path, downloads_dir)
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
    local url = Utils.fs.join_path(TOOLCHAIN_RELEASES_BASE_URL, tag, asset_pattern)
    Utils.inf("URL: ", { url = TOOLCHAIN_RELEASES_BASE_URL })
    if not url then
        Utils.wrn("Unsupported platform for nrfutil", { platform = asset_pattern })
        return nil
    end
    local bundles = Utils.net.archived_asset_download(url, install_path, downloads_dir)

    if #bundles == 0 then
        Utils.wrn("JSON payload did not have any content", { bundles = bundles })
        return nil
    end
    return Utils.tbl_map(function(release)
        local meta = release.metadata or {}
        local download_url = (meta.filename ~= nil) and Utils.fs.join_path(TOOLCHAIN_DOWNLOADS_BASE_URL, meta.filename)
            or ""
        local bundle = {
            version = release.key or "",
            checksum = meta.version or "",
            download_url = download_url,
        }
        return bundle
    end, bundles)
end

local STORE_KEYS = {
    ["toolchain"] = "minimal_toolchain",
}
---@return string[] versions
M.list_versions = function()
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
    local toolchain_assets = {} ---@type table<string,{minimal_assets: table<string, ToolchainBundle>}>
    local versions = {}
    for _, release in ipairs(result) do
        local version = release.tag_name:gsub("^v", "")
        local assets = release.assets or {}
        local minimal_assets_for_tag = {} ---@type table<string, ToolchainBundle>
        for _, asset in ipairs(assets) do
            if asset.name ~= nil and Utils.strings.contains(asset.name, "minimal") then
                local osname, plat = asset.name:match(".*_(%w+)%-([%w_]+)_minimal.*$")

                if osname == nil then
                    Utils.fatal("NO PLATFORM IDENTIFIER: ", { asset = asset })
                    error("")
                end
                minimal_assets_for_tag[osname] = Utils.tbl_extend("error", minimal_assets_for_tag[osname] or {}, {
                    [plat] = {
                        name = asset.name,
                        version = version,
                        download_url = asset.browser_download_url or asset.url,
                        checksum = asset.digest,
                    },
                })
            end
        end
        versions[#versions + 1] = version
        toolchain_assets[version] = {
            minimal_assets = minimal_assets_for_tag,
        }
    end
    Utils.inf("Toolchain bundles collected: ", { assets = toolchain_assets, versions = versions })
    Utils.store.store_table(toolchain_assets, "minimal_toolchains")
    return versions
end

--- Installs a specific version of nrfutil (launcher + pinned core module).
--- Layout: install_path/bin/nrfutil, install_path/home/, install_path/download/
---@param version string The mise-provided install path
---@param install_path string The mise-provided install path
---@param download_path string The mise-provided install path
function M.install(version, install_path, download_path)
    local assets = Utils.store.read_table("minimal_toolchains") ---@type table<string,{minimal_assets: table<string, ToolchainBundle>}>

    if not assets then
        Utils.err("Could not get asset store")
        return nil
    end

    local asset_for_version = assets[version]

    if not asset_for_version or not asset_for_version.minimal_assets then
        Utils.err("Could not find asset in store for version", { version = version, assets = assets })
        return nil
    end
    local minimal_assets = asset_for_version.minimal_assets
    local osname = Utils.os()
    local arch = Utils.arch()
    local asset = (minimal_assets[osname] or {})[arch]

    if not asset then
        Utils.err(
            "Could not find asset in store for version",
            { osname = osname, platform = arch, assets = minimal_assets }
        )
        return nil
    end
    -- 1. Download the launcher executable
    Utils.inf("Downloading nrfutil launcher", { asset = asset })
    local ext = (osname == "windows") and ".7z" or ".tar.xz"
    local res = Utils.net.archived_asset_download(
        asset.download_url,
        install_path,
        download_path,
        { name = string.format("zephyr-sdk-%s", version), ext = ext }
    )

    -- 2. Download the versioned core module tarball
    -- 3. Bootstrap: pin core version via tarball path, run nrfutil to trigger install
    Utils.inf("Installed toolchain at", { res = res })
    return res
end

---@param _version string The mise-provided install path
---@param install_path string The mise-provided install path
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(_version, install_path) -- luacheck: no unused args
    local zephyr_sdk_install_dir = Utils.fs.Path({ install_path, "opt", "zephyr-sdk" })
    local bin_path = Utils.fs.Path({ zephyr_sdk_install_dir, "arm-zephyr-eabi", "bin" })

    local env_vars = {
        { key = "PATH", value = bin_path },
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = "zephyr" },
        { key = "ZEPHYR_SDK_INSTALL_DIR", value = zephyr_sdk_install_dir },
    }
    return env_vars
end
return M
