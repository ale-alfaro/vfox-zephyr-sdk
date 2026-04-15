---@class NcsTool
local M = {}

TOOLCHAIN_BUNDLES_BASE_URL =
    Utils.fs.join_path("https://files.nordicsemi.com", "artifactory", "NCS", "external", "bundles", "v3")

local MIN_VERSION = "3.0.0"
local MAX_VERSION = "3.2.1"
---@class ToolchainBundle
---@field  version string
---@field checksum string
---@field download_url string
---[[
---
--- curl -s https://files.nordicsemi.com/artifactory/NCS/external/bundles/v3/index-linux-x86_64.json | jq '[ .[] | select(.json_api_version == 2) | .key as $version | .metadata as $meta | { $version : { hash: $meta.version , url: $meta.filename } } ]'
---]]--
--- Returns the nrfutil launcher download URL for the current
---@return ToolchainBundle[]?
local function get_toolchain_bundle_index()
    local ident = Utils.net.platform_create_string("index-{os}-{arch}.json")

    local url = Utils.fs.join_path(TOOLCHAIN_BUNDLES_BASE_URL, ident)
    -- macOS uses a universal binary
    Utils.inf("URL: ", { url = url })
    if not url then
        Utils.wrn("Unsupported platform for nrfutil", { platform = ident })
        return nil
    end
    -- try_get: returns (resp, nil) on success, (nil, err_string) on failure
    local bundles = Utils.net.get_json_payload(url, function(bundle)
        if bundle["json_api_version"] and bundle["json_api_version"] == 2 then
            local version = bundle["key"] or ""
            local semver = version:match("v(%d%.%d%.%d)$")
            if semver then
                return (
                    Utils.semver.compare(semver, MIN_VERSION) >= 0
                    and Utils.semver.compare(semver, MAX_VERSION) <= 0
                )
            end
        end
        return false
    end)

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

function M.list_versions()
    if Utils.store.store_exists("ncs_toolchains") then
        Utils.inf("Store exists already, returning values stored there")
        local assets = Utils.store.read_table("ncs_toolchains") ---@type ZephyrSdkAsset
        if not assets then
            Utils.fatal("Could not get asset store")
        end
        return Utils.tbl_keys(assets)
    end
    local bundles = get_toolchain_bundle_index()
    if not bundles then
        return {}
    end
    local versions = {}
    local cache = {}
    for _, bundle in ipairs(bundles) do
        cache[bundle.version] = bundle
        versions[#versions + 1] = bundle.version
    end

    Utils.store.store_table(cache, "ncs_toolchains")
    Utils.inf("Bundles", { bundles = bundles })
    return versions
end
--- Installs a specific version of nrfutil (launcher + pinned core module).
--- Layout: install_path/bin/nrfutil, install_path/home/, install_path/download/
---@param version string The mise-provided install path
---@param install_path string The mise-provided install path
---@param download_path string The mise-provided install path
function M.install(version, install_path, download_path)
    local bundles = Utils.store.read_table("ncs_toolchains")

    if not bundles then
        Utils.err("Could not get bundle cache", { version = version })
        return nil
    end

    local bundle = bundles[version]
    if not bundle then
        Utils.err("Could not find bundle in cache", { version = version })
        return nil
    end
    -- 1. Download the launcher executable
    local install_parent = Utils.fs.dirname(install_path)
    local install_dirname = Utils.fs.basename(install_path)
    Utils.inf("Downloading nrfutil launcher", { bundle = bundle })
    Utils.sh.safe_exec({ "rm", "-r", install_path })
    local res = Utils.net.archived_asset_download(bundle.download_url, install_parent, download_path, install_dirname)

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
