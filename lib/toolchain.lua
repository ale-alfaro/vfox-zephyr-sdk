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
local RELEASES_API_URL = Utils.fs.join_path("https://api.github.com", "repos", GITHUB_REPO, "releases")

local MIN_VERSION = "0.17.0"
local os_name_map = { darwin = "macos" }
local function sdk_osname()
    return os_name_map[Utils.os()] or Utils.os()
end

--- Map runtime OS name to Zephyr SDK naming convention
---@return string[] versions
M.list_versions = function()
    if Utils.store.store_exists("minimal_toolchains") then
        Utils.inf("Store exists already, returning values stored there")
        local assets = Utils.store.read_table("minimal_toolchains") ---@type ZephyrSdkAsset
        if not assets then
            Utils.fatal("Could not get asset store")
        end
        return Utils.tbl_keys(assets)
    end
    local result = Utils.net.github_fetch_releases(GITHUB_REPO, MIN_VERSION)
    local toolchain_assets = {} ---@type ZephyrSdkReleaseCache
    local versions = {}
    for _, release in ipairs(result) do
        local version = release.tag_name:gsub("^v", "")
        local assets = release.assets or {}
        local minimal_assets_for_tag = {} ---@type AssetMap
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
        toolchain_assets[version] = { tag_name = release.tag_name, minimal_assets = minimal_assets_for_tag }
    end
    Utils.inf("Toolchain bundles collected: ", { assets = toolchain_assets, versions = versions })
    Utils.store.store_table(toolchain_assets, "minimal_toolchains")
    return versions
end

---@class ToolchainSetupOpts
---@field toolchains? string[] Toolchain targets to install (e.g. {"arm-zephyr-eabi"})
---@field hosttools? boolean Install host tools
---@field cmake_pkg? boolean Register Zephyr SDK CMake package
---@field family? ZephyrSdkToolchainFamily
---
---@param opts? table Custom options from mise.toml
---@param version string Custom options from mise.toml
---@return ToolchainSetupOpts
local function parse_toolchain_options(opts, version)
    local tc_opts = Utils.tbl_extend("force", {

        toolchains = {},
        hosttools = false,
        cmake_pkg = false,
        family = (Utils.semver.compare(version, "1.0.0") >= 0) and "gnu" or "zephyr",
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
---@param opts ToolchainSetupOpts
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
    Utils.inf("Running Zephyr SDK setup", { cmd = cmd })
    return os.execute(cmd)
end

--- Installs a specific version of nrfutil (launcher + pinned core module).
--- Layout: install_path/bin/nrfutil, install_path/home/, install_path/download/
---@param ctx BackendInstallCtx The mise-provided install path
function M.install(ctx)
    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    local opts = parse_toolchain_options(ctx.options, ctx.version)
    local assets = Utils.store.read_table("minimal_toolchains") ---@type ZephyrSdkAsset

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
    local osname = sdk_osname()
    local arch = Utils.arch()
    local asset = (minimal_assets[osname] or {})[arch]

    if not asset then
        Utils.err(
            "Could not find asset in store for version",
            { osname = osname, platform = arch, assets = minimal_assets }
        )
        return nil
    end

    Utils.inf("Downloading minimal-zephyr-sdk", { asset = asset })
    version = version:gsub("^v", "")
    local ext = (Utils.os() == "windows") and ".7z" or ".tar.xz"
    local archive_name = string.format("zephyr-sdk-%s_%s-%s_minimal%s", version, sdk_osname(), Utils.arch(), ext)
    local archive_path = Utils.fs.join_path(download_path, archive_name)
    local _ok, err = Utils.net.http.try_download_file({ url = asset.download_url }, archive_path)
    if err then
        Utils.err("Download failed", { url = asset.download_url, err = err })
        return nil
    end
    Utils.net.decompres_strip_components(archive_path, install_path, 1)
    if run_setup(install_path, opts) ~= 0 then
        Utils.err("Running setup cmd failed with error ")
    else
        Utils.inf("Installed toolchain at", { res = install_path })
    end
end

---@param ctx BackendExecEnvCtx
---@return EnvKey[] env_vars Array of {key, value} tables
function M.envs(ctx) -- luacheck: no unused args
    local zephyr_sdk_install_dir = ctx.install_path
    local opts = parse_toolchain_options(ctx.options, ctx.version)
    local toolchain_root = (opts.family ~= "zephyr") and Utils.fs.join_path(zephyr_sdk_install_dir, opts.family)
        or zephyr_sdk_install_dir
    local env_vars = {
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = opts.family },
        { key = "ZEPHYR_SDK_INSTALL_DIR", value = zephyr_sdk_install_dir },
    }
    if opts.toolchains then
        for _, tc in ipairs(opts.toolchains) do
            env_vars[#env_vars + 1] = { key = "PATH", value = Utils.fs.Path({ toolchain_root, tc, "bin" }) }
        end
    end
    return env_vars
end
return M
