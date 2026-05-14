local M = {}

local TOOLCHAIN_BUNDLES_BASE_URL =
    Utils.fs.join_path("https://files.nordicsemi.com", "artifactory", "NCS", "external", "bundles", "v3")

local MIN_VERSION = "3.0.0"
local MAX_VERSION = "3.2.1"
local STORE_KEY = "ncs_toolchains"

---@return ToolchainBundle[]?
local function get_toolchain_bundle_index()
    local index_json_name = Utils.platform_create_string("index-{os}-{arch}.json")
    local url = Utils.fs.join_path(TOOLCHAIN_BUNDLES_BASE_URL, index_json_name)
    Utils.dbg("URL: ", { url = url })
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
    return Utils.store.fetch_versions(STORE_KEY, get_toolchain_bundle_index)
end

--- nrfutil unpacks the bundle under `<NRFUTIL_HOME>/toolchains/<bundle-id>/`.
--- We don't know the bundle-id ahead of time (it's the toolchain checksum), so
--- scan for the first subdir that contains the conventional `opt/zephyr-sdk`
--- payload and return the SDK root.
---@param install_path string
---@return string?
local function find_sdk_root(install_path)
    local toolchains_dir = Utils.fs.join_path(install_path, "toolchains")
    if not Utils.fs.directory_exists(toolchains_dir) then
        return nil
    end
    for _, dir in ipairs(Utils.fs.scandir(toolchains_dir, { type = "directory" })) do
        local candidate = Utils.fs.join_path(dir, "opt", "zephyr-sdk")
        if Utils.fs.directory_exists(candidate) then
            return candidate
        end
    end
    return nil
end

---@param ctx BackendInstallCtx
---@param opts? ToolOptions
function M.install(ctx, opts)
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)
    opts = opts or {}
    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")

    if
        opts.family == "ncs"
        and (Utils.semver.compare(version, MIN_VERSION) < 0 or Utils.semver.compare(version, MAX_VERSION) > 0)
    then
        Utils.fatal("NCS passed as an option with an unsupported version", { version = version })
        error()
    end

    local nrfutil = Utils.sh.which("nrfutil")
    if not nrfutil then
        Utils.fatal(
            "nrfutil is required to install NCS toolchain bundles. "
                .. "Install it first with: `mise install zephyr-sdk:nrfutil@latest`"
        )
        error()
    end

    local bundle = Utils.store.fetch_asset_bundles(STORE_KEY, get_toolchain_bundle_index, version)
    if not bundle then
        Utils.fatal("Bundle not found for version and store key", { version = version, key = STORE_KEY })
        error()
    end

    Utils.sh.mkdir(download_path)
    local bundle_name = assert(bundle.download_url:match("([^/]+)$"), "bundle download_url has no filename")
    local local_bundle = Utils.fs.join_path(download_path, bundle_name)
    Utils.inf("Downloading NCS toolchain bundle", { bundle = bundle, dest = local_bundle })
    local ok, err = Utils.net.download_with_progress(bundle.download_url, local_bundle)
    if not ok then
        Utils.fatal("Failed to download toolchain bundle", { err = err })
        error()
    end

    -- Pin both env vars under mise's tree:
    --   NRFUTIL_HOME      -> nrfutil's own packages/config/state
    --   --ncs-install-dir -> where sdk-manager unpacks the toolchain bundle
    -- (the latter defaults to ~/ncs on Linux, /opt/nordic/ncs on macOS,
    -- C:/ncs on Windows, regardless of NRFUTIL_HOME -- this is the bit that
    -- otherwise leaks outside mise's install tree).
    -- setenv (instead of cmd.exec opts.env) preserves PATH/HOME/TMPDIR.
    Utils.sh.mkdir(install_path)
    require("env").setenv("NRFUTIL_HOME", install_path)

    Utils.inf("Bootstrapping sdk-manager into NCS install root", { home = install_path })
    Utils.sh.exec({ nrfutil, "install", "sdk-manager" }, { fail = true })

    Utils.inf("Installing toolchain bundle via nrfutil sdk-manager")
    Utils.sh.exec({
        nrfutil,
        "sdk-manager",
        "toolchain",
        "install",
        "--toolchain-bundle",
        local_bundle,
        "--ncs-install-dir",
        install_path,
    }, { fail = true })

    -- Surface the SDK root at the conventional `<install_path>/opt/zephyr-sdk`
    -- path so `build_ncs_toolchain_variant.envs` (which forwards to toolchain.envs)
    -- keeps working without knowing the bundle-id.
    local sdk_root = find_sdk_root(install_path)
    if not sdk_root then
        Utils.fatal("Could not locate installed Zephyr SDK under toolchains/", { install_path = install_path })
        error()
    end
    local link_parent = Utils.fs.join_path(install_path, "opt")
    Utils.sh.mkdir(link_parent)
    local link = Utils.fs.join_path(link_parent, "zephyr-sdk")
    os.remove(link)
    Utils.fs.symlink(sdk_root, link)
    Utils.inf("Linked SDK root", { from = link, to = sdk_root })
end

return M
