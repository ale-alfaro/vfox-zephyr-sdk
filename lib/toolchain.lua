---@class ZephyrTool
local M = {}

---@class M.toolchains : table<string, string>

local GITHUB_REPO = "zephyrproject-rtos/sdk-ng"
local MIN_VERSION = "0.17.0"
local MAX_VERSION = "1.1.0"
-- The SDK only ships an LLVM/Clang toolchain from 1.0.0 onwards.
local LLVM_MIN_VERSION = "1.0.0"
-- Installed when the bare `zephyr-sdk` (toolchain) tool is used without any
-- toolchain option, so a plain install yields a usable GNU cross-compiler
-- instead of every toolchain (or none).
local DEFAULT_TARGET = "arm-zephyr-eabi"
local STORE_KEY = "zephyr_minimal_toolchains"

--- Fetch available SDK release versions from GitHub.
--- Filters out pre-releases, drafts, and versions below MIN_VERSION.
local github_fetch_releases = function() ---@as AssetBundleFetchFn
    local request = Utils.net.gh_api(GITHUB_REPO, "releases", { reqType = "GET" })

    local bundles = Utils.net.get_json_payload(request, function(bundle) ---@as ToolchainBundle[]?
        if bundle["tag_name"] then
            return Utils.semver.check_version(bundle.tag_name, {
                version = { min = MIN_VERSION, max = MAX_VERSION },
                prerelease = false,
            })
        end
        return false
    end)
    if type(bundles) ~= "table" or #bundles == 0 then
        error("JSON payload did not have any content ")
    end
    local releases = {} ---@as table<Version, ToolchainBundle>
    local ext = (Utils.os() == "windows") and ".7z" or ".tar.xz"
    local asset_pattern = Utils.platform_create_string("_{os}-{arch}_minimal{ext}", {
        exttype = "archive",
        override = {
            ["{ext}"] = ext,
        },
    })
    for _, release in ipairs(bundles) do
        local version = release.tag_name:gsub("^v", "")
        local assets = release.assets or {}
        for _, asset in ipairs(assets) do
            if asset.name ~= nil and Utils.strings.has_suffix(asset.name, asset_pattern) then
                releases[version] = {
                    name = asset.name,
                    version = version,
                    download_url = asset.browser_download_url or asset.url,
                    checksum = asset.digest,
                }
            end
        end
    end
    return releases
end

--- List installable Zephyr SDK versions for the requested variant.
--- The `llvm` variant is only packaged from LLVM_MIN_VERSION onwards, so it
--- filters the shared release list down to the versions that ship it.
---@param ctx BackendListVersionsCtx
---@return string[] versions
M.list_versions = function(ctx)
    Utils.validate_ctx(ctx, "list-versions")
    local opts = ctx.options or {} ---@as ZephyrSdkToolOptions
    local versions = Utils.store.fetch_versions(STORE_KEY, github_fetch_releases)
    if opts and opts.target == "llvm" then
        versions = Utils.list_filter(function(version)
            return Utils.semver.compare(version, LLVM_MIN_VERSION) >= 0
        end, versions)
    end
    return versions
end
--- Install a version of the Zephyr SDK toolchain.
--- 1. Downloads the minimal SDK archive (contains setup.sh + cmake files)
--- 2. Extracts it flat into install_path (--strip-components=1)
--- 3. Runs setup.sh to download the family and target-specific toolchain
---@param ctx BackendInstallCtx The mise-provided install path
function M.install(ctx)
    Utils.validate_ctx(ctx, "install")
    local opts = ctx.options or {} ---@as ZephyrSdkToolOptions
    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    if opts.family == "llvm" and Utils.semver.compare(version, LLVM_MIN_VERSION) < 0 then
        Utils.fatal("The llvm toolchain variant requires Zephyr SDK >= " .. LLVM_MIN_VERSION, { version = version })
    end
    local asset = Utils.store.fetch_toolchain_asset(STORE_KEY, github_fetch_releases, version)

    if not asset then
        error("Toolchain assets could not be found locally or online " .. version)
    end

    Utils.inf("Downloading minimal-zephyr-sdk", { asset = asset })
    version = version:gsub("^v", "")
    Utils.net.archived_asset_download(
        asset.download_url,
        install_path,
        download_path,
        { name = "zephyr-sdk-" .. version, strip_components = 1 }
    )
    local setup_sh = Utils.fs.join_path(install_path, "setup.sh")
    if not Utils.fs.path_exists(setup_sh, { type = "file" }) then
        Utils.fatal("setup.sh not found after extraction", { sdk_root = setup_sh })
    end
    Utils.dbg("Running Zephyr SDK setup script", { setup_sh = setup_sh })
    Utils.sh.chmod("+x", setup_sh)
    local target = opts.target or DEFAULT_TARGET
    local cmd = string.format("%q %s", setup_sh, (opts.family == "llvm" and " -l" or string.format(" -t %s", target)))

    local out = Utils.sh.exec(Utils.strings.split(cmd, " "), { fail = true })
    if out ~= nil then
        Utils.err("Running setup cmd failed with error ")
    end
end

---@param ctx BackendExecEnvCtx
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx) -- luacheck: no unused args
    Utils.validate_ctx(ctx, "exec")
    local opts = ctx.options or {} ---@as ZephyrSdkToolOptions
    local version, install_dir = ctx.version, ctx.install_path
    -- Both GNU and LLVM ship inside the SDK root, so Zephyr's toolchain search
    -- only needs ZEPHYR_SDK_INSTALL_DIR plus the variant name. The SDK's LLVM is
    -- NOT a standalone `llvm` toolchain variant (that one expects an out-of-tree
    -- LLVM_TOOLCHAIN_PATH and lives in <zephyr>/cmake/toolchain/llvm/). It is the
    -- `zephyr` variant with the `llvm` compiler sub-flavor, selected via the
    -- combined `zephyr/llvm` syntax that FindHostTools splits into
    -- ZEPHYR_TOOLCHAIN_VARIANT=zephyr + TOOLCHAIN_VARIANT_COMPILER=llvm. That
    -- routes the include to <sdk>/cmake/zephyr/llvm/generic.cmake, which exists.
    -- The PATH entries below are a convenience for invoking the compilers
    -- directly; the {VARIANT}_TOOLCHAIN_PATH var is not required here.
    local is_new_layout = Utils.semver.compare(version, "1.0.0") >= 0
    local variant = "zephyr"
    if is_new_layout then
        variant = Utils.fs.join_path(variant, (opts.family == "llvm") and "llvm" or "gnu")
    end
    local env_vars = {
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = variant },
        { key = "ZEPHYR_SDK_INSTALL_DIR", value = install_dir },
    }
    if opts.family == "llvm" then
        Utils.inf("Toolchain family is llvm", { env = env_vars })
    else
        local toolchain_root = is_new_layout and Utils.fs.join_path(install_dir, "gnu") or install_dir
        env_vars[#env_vars + 1] = { key = "PATH", value = Utils.fs.join_path(toolchain_root, opts.target, "bin") }
        Utils.inf("Toolchain family is gnu", { env = env_vars })
    end
    return env_vars
end
return M
