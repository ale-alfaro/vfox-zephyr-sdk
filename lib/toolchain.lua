---@class ZephyrTool
local M = {}

---@class M.toolchains : table<string, string>
M.GnuToolchainTypes = {
    ["aarch64"] = "aarch64-zephyr-elf",
    ["arc64"] = "arc64-zephyr-elf",
    ["arc"] = "arc-zephyr-elf",
    ["arm-zephyr-eabi"] = "arm-zephyr-eabi",
    ["microblazeel"] = "microblazeel-zephyr-elf",
    ["mips"] = "mips-zephyr-elf",
    ["nios2"] = "nios2-zephyr-elf",
    ["riscv64"] = "riscv64-zephyr-elf",
    ["rx"] = "rx-zephyr-elf",
    ["sparc"] = "sparc-zephyr-elf",
    ["x86_64"] = "x86_64-zephyr-elf",
}

M.LlvmToolchainTypes = {
    ["llvm"] = "llvm",
}
local GITHUB_REPO = "zephyrproject-rtos/sdk-ng"

local MIN_VERSION = "0.17.0"
local MAX_VERSION = "1.1.0"
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
--- Map runtime OS name to Zephyr SDK naming convention
---@return string[] versions
M.list_versions = function()
    local versions = Utils.store.fetch_versions(STORE_KEY, github_fetch_releases)
    return versions or {}
end

---
---@param opts? ToolOptions Custom options from mise.toml
---@return ToolchainOptions
local function parse_toolchain_options(opts)
    Utils.inf("Parsing opts:", { opts = opts })
    local tc_opts = Utils.tbl_extend("force", {

        toolchains = {},
        hosttools = false,
        cmake_pkg = false,
        family = "zephyr",
    }, opts or {})
    if tc_opts.toolchains then
        local toolchains = {}
        for tc in string.gmatch(tostring(tc_opts.toolchains), "[%w%-_]+") do
            toolchains[#toolchains + 1] = tc
        end
        tc_opts.toolchains = toolchains
    end
    return tc_opts
end

--- Install a version of the Zephyr SDK toolchain.
--- 1. Downloads the minimal SDK archive (contains setup.sh + cmake files)
--- 2. Extracts it flat into install_path (--strip-components=1)
--- 3. Runs setup.sh to download the arm-zephyr-eabi cross-compiler, host tools,
---    and register the CMake package
---@param sdk_root string Path containing setup.sh (the flattened install dir)
---@param opts ToolchainOptions
---@return number
local function run_setup(sdk_root, opts)
    Utils.validate("sdk_root", sdk_root, "string")
    Utils.validate("opts", opts, "table")
    local setup_sh = Utils.fs.join_path(sdk_root, "setup.sh")
    if not Utils.fs.path_exists(setup_sh, { type = "file" }) then
        Utils.fatal("setup.sh not found after extraction", { sdk_root = sdk_root })
    end
    local cmd = setup_sh
    local toolchains = Utils.ensure_list(opts.toolchains) or {} ---@type string[]
    if toolchains then
        for _, tc in ipairs(toolchains) do
            cmd = cmd .. " -t " .. " " .. tc
        end
    end
    if opts.hosttools then
        cmd = cmd .. " -h"
    end
    if opts.cmake_pkg then
        cmd = cmd .. " -c"
    end

    if #cmd <= 1 then
        cmd = cmd .. " -?"
    end
    Utils.dbg("Running Zephyr SDK setup", { cmd = cmd })
    return os.execute(cmd)
end

--- Installs a specific version of nrfutil (launcher + pinned core module).
--- Layout: install_path/bin/nrfutil, install_path/home/, install_path/download/
---@param ctx BackendInstallCtx The mise-provided install path
---@param opts? ToolOptions
function M.install(ctx, opts)
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)

    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")
    local toolchain_opts = parse_toolchain_options(opts)
    if toolchain_opts.family == "ncs" then
        --- we install it like we do using NCS
        Utils.inf("ncs passed as an option for toolchain family")
        return ZephyrSdk.ncs_toolchain(ctx, opts)
    end
    local asset = Utils.store.fetch_asset_bundles(STORE_KEY, version)

    if not asset then
        Utils.fatal("Bundle not found for version and store key provided", { version = version, key = STORE_KEY })
        error()
    end

    Utils.inf("Downloading minimal-zephyr-sdk", { asset = asset })
    version = version:gsub("^v", "")
    Utils.net.archived_asset_download(
        asset.download_url,
        install_path,
        download_path,
        { name = "zephr-sdk-" .. version, strip_components = 1 }
    )
    if run_setup(install_path, toolchain_opts) ~= 0 then
        Utils.err("Running setup cmd failed with error ")
    else
        Utils.inf("Installed toolchain at", { res = install_path })
    end
end

---@param ctx BackendExecEnvCtx
---@param opts? ToolOptions
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx, opts) -- luacheck: no unused args
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)
    local version, zephyr_sdk_install_dir = ctx.version, ctx.install_path
    Utils.validate("version", version, "string")
    Utils.validate("zephyr_sdk_install_dir", zephyr_sdk_install_dir, "string")
    local toolchain_opts = parse_toolchain_options(opts) ---@as ToolchainOptions
    local toolchain_root = zephyr_sdk_install_dir
    if Utils.semver.compare(version, "1.0.0") >= 0 then
        toolchain_root = (toolchain_opts.family == "zephyr") and Utils.fs.join_path(zephyr_sdk_install_dir, "gnu")
            or Utils.fs.join_path(zephyr_sdk_install_dir, "llvm")
    end
    local env_vars = {
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = toolchain_opts.family },
        { key = "ZEPHYR_SDK_INSTALL_DIR", value = zephyr_sdk_install_dir },
    }
    if toolchain_opts.toolchains then
        for _, tc in ipairs(toolchain_opts.toolchains) do
            env_vars[#env_vars + 1] = { key = "PATH", value = Utils.fs.join_path(toolchain_root, tc, "bin") }
        end
    end
    return env_vars
end
return M
