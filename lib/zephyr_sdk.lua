local M = {

    GITHUB_USER = "zephyrproject-rtos",
    GITHUB_REPO = "sdk-ng",
    MIN_VERSION = "0.17.0",
    BREAKING_SDK_VERSION = "1.0.0",
    INSTALLER_NAME = "zephyr-sdk-installer",
}
--- @param version string
--- @return string bin_path
local download_minmal_sdk = function(install_dir, version)
    local fs = require("file")
    local path = require("pathlib")
    local gh = require("gh")
    local sh = require("shell_exec")
    local zephyr_sdk_home = sh.get_zephyr_sdk_home()
    local download_path = fs.join_path(zephyr_sdk_home, "downloads")
    sh.safe_exec("mkdir -p " .. download_path)

    gh.get_asset_for_tool("minimal", version, zephyr_sdk_home, download_path)
    -- ── Normalise SDK root ──────────────────────────────────────────────
    -- The minimal SDK tar may extract with a top-level zephyr-sdk-<ver>/
    -- directory. Flatten it so the SDK root is always `install_path`.
    local version_file = path.Path({ install_dir, "sdk_version" })
    if version_file == "" then
        Utils.fatal(
            "Invalid Zephyr SDK: sdk_version not found in install path or subdirectories",
            { install_path = zephyr_sdk_home }
        )
    end
    local sdk_version = require("strings").trim_space(fs.read(version_file))
    Utils.inf("Zephyr SDK version:" .. sdk_version)
    local setup_sh = path.Path({ install_dir, "setup.sh" }, { check_exists = true, fail = true })
    sh.safe_exec("chmod +x " .. setup_sh)
    return setup_sh
end

---@class ZephyrSdkToolchainPaths
---@field setup_sh string
---@field install_dir string

--- @param ctx BackendInstallCtx
--- @return ZephyrSdkToolchainPaths bin_path
local install_minmal_sdk = function(ctx)
    local version = ctx.version

    local fs = require("file")
    local sh = require("shell_exec")

    local zephyr_sdk_home = sh.get_zephyr_sdk_home()
    local install_dir = fs.join_path(zephyr_sdk_home, "zephyr-sdk-" .. version)
    local zephyr_sdk_setup_sh = fs.join_path(install_dir, "setup.sh")
    local mise_tool_path = fs.join_path(ctx.install_path, "setup.sh")
    if not fs.exists(zephyr_sdk_setup_sh) then
        Utils.inf(
            "Zephyr-SDK installer not found. Installing in",
            { install_dir = install_dir, zephyr_sdk_home = zephyr_sdk_home }
        )
        download_minmal_sdk(install_dir, version)
        Utils.inf("Minimal Installation successful")
    end
    if ctx.tool == "minimal" and not fs.exists(mise_tool_path) then
        Utils.inf("Symlinking minimal installation")
        fs.symlink(zephyr_sdk_setup_sh, mise_tool_path)
        Utils.inf("Successfully installed at", { install_path = mise_tool_path })
    end
    return { setup_sh = mise_tool_path, toolchain_root = install_dir }
end
--- @param ctx BackendInstallCtx
local install_toolchain = function(ctx)
    local tool = ctx.tool
    local fs = require("file")
    local semver = require("semver")
    local strings = require("strings")
    local sh = require("shell_exec")
    local tool_version = ctx.version
    Utils.inf("Zephyr SDK tool to install: ", { tool = tool, version = tool_version })
    local toolchain_paths = install_minmal_sdk(ctx)
    local toolchain_root = fs.join_path(toolchain_paths.install_dir, ctx.tool)

    if semver.compare(ctx.version, "1.0.0") >= 0 and ctx.tool ~= "host" then
        local prefix = ctx.tool == "llvm" and "llvm" or "gnu"
        toolchain_root = fs.join_path(toolchain_paths.install_dir, prefix, ctx.tool)
    end
    local bin_path = fs.join_path(toolchain_root, "bin")
    local gcc_path = fs.join_path(bin_path, ctx.tool .. "-gcc")

    local tool_patterns = {
        ["(llvm)"] = "-t",
        ["(host)"] = "-h",
        ["(%w+-%w+-%w+)"] = "-t",
    }
    if not fs.exists(gcc_path) then
        for pattern, install_cmd in pairs(tool_patterns) do
            local flags_matched = string.find(ctx.tool, pattern) ~= nil and install_cmd or ""
            if flags_matched ~= "" then
                local cmd_matched = strings.join({ toolchain_paths.setup_sh, flags_matched, ctx.tool }, " ")
                Utils.inf("Matched tool with toolchain install cmd", { tool = ctx.tool, cmd_matched = cmd_matched })
                sh.safe_exec(cmd_matched)
                return bin_path
            end
        end
        Utils.fatal("Toolchain object not found for tool", { tool = ctx.tool })
    end
    local mise_tool_bin_path = fs.join_path(ctx.install_path, "bin")
    if not fs.exists(fs.join_path(mise_tool_bin_path, ctx.tool .. "-gcc")) then
        Utils.inf(
            "Zephyr SDK tool installed. Symliniking into mise tool path ",
            { zephyr_sdk_tool_path = bin_path, mise_tool_path = mise_tool_bin_path }
        )
        fs.symlink(bin_path, mise_tool_bin_path)
        return
    end
end
--- @param ctx BackendInstallCtx
local install_west_shim = function(ctx)
    local fs = require("file")
    local path = require("pathlib")
    local sh = require("shell_exec")
    local plugin_path = sh.safe_exec(string.format("realpath %q", RUNTIME.pluginDirPath), {}, true)

    local local_west_shim = path.Path({ plugin_path, "bin", "west_shim.py" }, { check_exists = true, fail = true })
    local installed_west_shim = path.Path({ ctx.install_path, "west_shim.py" }, { check_exists = true })
    if installed_west_shim == "" then
        sh.safe_exec(string.format("cp %q %q", local_west_shim, ctx.install_path), {}, true)
        Utils.inf("Copied west shim", { west_shim = local_west_shim, install_path = ctx.install_path })
        local ok, msg =
            os.rename(fs.join_path(ctx.install_path, "west_shim.py"), fs.join_path(ctx.install_path, "west"))
        if not ok then
            Utils.fatal("Failed to rename shim to west command", { err_msg = msg })
        end
    end
end
---@type table<string,fun(ctx:BackendInstallCtx)>
M.available_tool_installations = {
    ["minimal"] = install_minmal_sdk,
    ["arm-zephyr-eabi"] = install_toolchain,
    ["west"] = install_west_shim,
    ["*"] = install_toolchain,
}
return M
