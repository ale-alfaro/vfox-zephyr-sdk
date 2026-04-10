---@param version string
---@param install_dir string
---@param download_dir string
local download_minmal_sdk = function(version, install_dir, download_dir)
    local fs = require("file")
    local pathlib = require("pathlib")
    local gh = require("gh")
    local sh = require("shell_exec")
    if not pathlib.directory_exists(download_dir) then
        sh.safe_exec("mkdir -p " .. download_dir)
    end

    Utils.inf("Getting assets for version:", { sdk_version = version, install_dir = install_dir })
    gh.get_asset_for_tool("minimal", version, install_dir, download_dir)
    -- ── Normalise SDK root ──────────────────────────────────────────────
    -- The minimal SDK tar may extract with a top-level zephyr-sdk-<ver>/
    -- directory. Flatten it so the SDK root is always `install_path`.
    local version_file = pathlib.Path({ install_dir, "sdk_version" })
    if version_file == "" then
        Utils.fatal(
            "Invalid Zephyr SDK: sdk_version not found in install path or subdirectories",
            { install_path = install_dir }
        )
    end
    local sdk_version = require("strings").trim_space(fs.read(version_file))
    Utils.inf("Zephyr SDK version:" .. sdk_version)
end

local M = {}

M.toolchain_patterns = {
    ["(llvm)"] = "-t",
    ["(host)"] = "-h",
    ["(%w+-%w+-%w+)"] = "-t",
}

---@type table<string, fun(tool:ZephyrSdkTool)>
M._install_funcs = {

    --- @param tool ZephyrSdkTool
    ["minimal"] = function(tool)
        local fs = require("file")
        local sh = require("shell_exec")

        if not fs.exists(tool.zephyr_install_path) then
            local pathlib = require("pathlib")
            local zephyr_sdk_download_path = pathlib.Path({ sh.get_zephyr_sdk_home(), "downloads" }, { create = true })
            Utils.inf(
                "Zephyr-SDK installer not found. Installing in zephyr home first",
                { zephyr_sdk_bin_path = tool.zephyr_install_path }
            )
            download_minmal_sdk(tool.version, pathlib.dirname(tool.zephyr_install_path), zephyr_sdk_download_path)

            sh.safe_exec("chmod +x " .. tool.zephyr_install_path)
            Utils.inf("Minimal Installation successful")
        end
        if not fs.exists(tool.mise_install_path) then
            Utils.inf(
                "Now Symlinking minimal installation to mise install path ",
                { mise_executable = tool.mise_install_path, zephyr_sdk_executable = tool.zephyr_install_path }
            )
            fs.symlink(tool.zephyr_install_path, tool.mise_install_path)
        end
        Utils.inf("Successfully installed at", { mise_executable = tool.mise_install_path })
    end,
    --- @param tool ZephyrSdkTool
    ["bin/.*"] = function(tool)
        local fs = require("file")
        local pathlib = require("pathlib")
        local strings = require("strings")
        local sh = require("shell_exec")
        local zephyr_sdk_bin_path, mise_bin_path = tool.zephyr_install_path, tool.mise_install_path

        local zephyr_sdk_setup_sh = tool.executables[1] or "setup.sh"
        if not pathlib.directory_exists(zephyr_sdk_bin_path) then
            local matched = false
            for pattern, install_cmd in pairs(M.toolchain_patterns) do
                local flags_matched = string.find(tool.tool, pattern) ~= nil and install_cmd or ""
                if flags_matched ~= "" then
                    matched = true
                    local cmd_matched = strings.join({ zephyr_sdk_setup_sh, flags_matched, tool }, " ")
                    Utils.inf("Matched tool with toolchain install cmd", { tool = tool, cmd_matched = cmd_matched })
                    if not sh.safe_exec(cmd_matched) then
                        Utils.fatal("Toolchain not able to install for tool", { tool = tool })
                    end
                    break
                end
            end
            if not matched then
                Utils.fatal("Toolchain object not found for tool", { tool = tool })
            end
        end
        if not pathlib.directory_exists(mise_bin_path) then
            Utils.inf(
                "Zephyr SDK tool installed. Symliniking into mise tool path ",
                { zephyr_sdk_bin_path = zephyr_sdk_bin_path, mise_bin_path = mise_bin_path }
            )
            fs.symlink(zephyr_sdk_bin_path, mise_bin_path)
            return
        end
    end,
    --- @param tool ZephyrSdkTool
    ["west"] = function(tool)
        local fs = require("file")
        local sh = require("shell_exec")

        local plugin_path = sh.safe_exec(string.format("realpath %q", RUNTIME.pluginDirPath), {}, true)
        local local_west = fs.join_path(plugin_path, "bin", "west")
        if not fs.exists(tool.mise_install_path) then
            sh.safe_exec(string.format("cp %q %q", local_west, tool.mise_install_path), {}, true)
            Utils.inf("Copied west shim", { west_shim = local_west, mise_west = tool.mise_install_path })
        end
        if not fs.exists(tool.zephyr_install_path) then
            fs.symlink(tool.mise_install_path, tool.zephyr_install_path)
            Utils.inf(
                "Created symlik to west in Zephyr install path",
                { mise_install_path = tool.mise_install_path, zephyr_west = tool.zephyr_install_path }
            )
        end
    end,
}
return M
