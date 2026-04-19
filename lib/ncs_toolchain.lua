---@class ZephyrTool
local M = {}

local TOOLCHAIN_BUNDLES_BASE_URL =
    Utils.fs.join_path("https://files.nordicsemi.com", "artifactory", "NCS", "external", "bundles", "v3")

local MIN_VERSION = "3.0.0"
local MAX_VERSION = "3.2.1"
---
local STORE_KEY = "ncs_toolchains"
--- Returns the nrfutil launcher download URL for the current
---@return ToolchainBundle[]?
local function get_toolchain_bundle_index()
    local index_json_name = Utils.platform_create_string("index-{os}-{arch}.json")

    local url = Utils.fs.join_path(TOOLCHAIN_BUNDLES_BASE_URL, index_json_name)
    -- macOS uses a universal binary
    Utils.dbg("URL: ", { url = url })
    -- try_get: returns (resp, nil) on success, (nil, err_string) on failure
    local bundles = Utils.net.get_json_payload(url, function(bundle) ---@as ToolchainBundle[]?
        if bundle["json_api_version"] and bundle["json_api_version"] == 2 then
            local version = bundle["key"] or ""
            return Utils.semver.check_version(version, {
                version = { min = MIN_VERSION, max = MAX_VERSION },
                prerelease = false,
            })
        end
        return false
    end)

    if not bundles or #bundles == 0 then
        Utils.err("JSON payload did not have any content", { bundles = bundles })
        return nil
    end
    local releases = {} ---@as table<Version, ToolchainBundle>
    for _, bundle in ipairs(bundles) do
        local meta = bundle.metadata
        local version = (bundle.key or ""):match("^v(.*)")
        if version and meta and meta.filename then
            local download_url = Utils.fs.join_path(TOOLCHAIN_BUNDLES_BASE_URL, meta.filename)
            releases[version] = {
                version = version,
                checksum = meta.version or "",
                download_url = download_url,
            }
        end
    end
    return releases
end

function M.list_versions()
    if RUNTIME.osType:lower() == "darwin" then
        Utils.wrn("NCS toolchain is not supported on MacOS")
        return {}
    end
    local versions = Utils.store.fetch_versions(STORE_KEY, get_toolchain_bundle_index)
    return versions or {}
end
--- Installs a specific version of nrfutil (launcher + pinned core module).
--- Layout: install_path/bin/nrfutil, install_path/home/, install_path/download/
---@param ctx BackendInstallCtx The mise-provided install path
---@param opts? ToolOptions The mise-provided install path
function M.install(ctx, opts)
    if RUNTIME.osType:lower() == "darwin" then
        Utils.wrn("NCS toolchain is not supported on MacOS")
        return {}
    end
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)
    opts = opts or {}
    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")
    if
        opts.family == "ncs"
        and (Utils.semver.compare(ctx.version, MIN_VERSION) < 0 and Utils.semver.compare(ctx.version, MAX_VERSION) > 0)
    then
        Utils.fatal("NCS passed as an option with a wrong version")
        return {}
    end

    local bundle = Utils.store.fetch_asset_bundles(STORE_KEY, version)
    if not bundle then
        Utils.fatal("Bundle not found for version and store key provided", { version = version, key = STORE_KEY })
        error()
    end
    local install_parent = Utils.fs.dirname(install_path)
    local install_dirname = Utils.fs.basename(install_path)
    Utils.inf("Downloading ncs toolchain", { bundle = bundle })
    local ok, err_msg = os.remove(install_path)
    if not ok then
        Utils.wrn("Could not remove installation directory to replace it with the toolchain", { err = err_msg })
        local zephyr_sdk_install_dir = Utils.fs.join_path(install_path, "opt", "zephyr-sdk")
        if Utils.fs.directory_exists(zephyr_sdk_install_dir) then
            Utils.wrn("Zephyr SDK installation already exists")
        else
            Utils.err("The installation directory is not empty. Can't proceed unless its completely empty")
            return nil
        end
    end
    local res = Utils.net.archived_asset_download(bundle.download_url, install_parent, download_path, {
        name = install_dirname,
    })

    -- 2. Download the versioned core module tarball
    -- 3. Bootstrap: pin core version via tarball path, run nrfutil to trigger install
    Utils.inf("Installed toolchain at", { res = res })
    return {}
end

---@param ctx BackendExecEnvCtx
---@param opts? ToolOptions The mise-provided install path
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx, opts) -- luacheck: no unused args
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)
    local version, install_path = ctx.version, ctx.install_path
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    local zephyr_sdk_install_dir = Utils.fs.join_path(install_path, "opt", "zephyr-sdk")
    local bin_path = Utils.fs.join_path(zephyr_sdk_install_dir, "arm-zephyr-eabi", "bin")

    local env_vars = {
        { key = "PATH", value = bin_path },
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = "zephyr" },
        { key = "ZEPHYR_SDK_INSTALL_DIR", value = zephyr_sdk_install_dir },
    }
    return env_vars
end
return M
