---@param version string
---@param install_dir string
---@param download_dir string
local download_minmal_sdk = function(version, install_dir, download_dir)
    Utils.validate("version", version, "string", "Version must be string")
    Utils.validate("install_dir", install_dir, "string", "install_dir must be string")
    Utils.validate("download_dir", download_dir, "string", "download_dir must be string")
    local gh = require("gh")
    if not Utils.fs.directory_exists(download_dir) then
        Utils.sh.safe_exec({ "mkdir", "-p", download_dir }, { fail = true })
    end

    Utils.inf("Getting assets for version:", { sdk_version = version, install_dir = install_dir })
    gh.get_asset_for_tool("minimal", version, install_dir, download_dir)
    -- ── Normalise SDK root ──────────────────────────────────────────────
    -- The minimal SDK tar may extract with a top-level zephyr-sdk-<ver>/
    -- directory. Flatten it so the SDK root is always `install_path`.
    local version_file = Utils.fs.Path({ install_dir, "sdk_version" })
    if not version_file then
        local nested_dir = Utils.fs.join_path(install_dir, "zephyr-sdk-" .. version)
        if Utils.fs.directory_exists(nested_dir) then
            Utils.inf("Flattening nested SDK directory", { nested_dir = nested_dir })
            Utils.sh.safe_exec(
                string.format("mv %q/* %q/ && rmdir %q", nested_dir, install_dir, nested_dir),
                { fail = true }
            )
            version_file = Utils.fs.Path({ install_dir, "sdk_version" })
        end
    end
    if not version_file then
        Utils.fatal(
            "Invalid Zephyr SDK: sdk_version not found in install path or subdirectories",
            { install_path = install_dir }
        )
    end
    local sdk_version = require("strings").trim_space(Utils.fs.read(version_file))
    Utils.inf("Zephyr SDK version:" .. sdk_version)
end

local M = {}

---@return string zephyr_sdk_home
M.get_zephyr_sdk_home = function()
    local os_name = RUNTIME.osType:lower()
    local home = os.getenv("HOME")
    local mac_linux_loc = home .. "/zephyr-sdk-root"
    local platform_map = {
        darwin = mac_linux_loc,
        linux = mac_linux_loc,
        windows = "C:\\zephyr-sdk-root",
    }

    return platform_map[os_name]
end

---@param version string
---@param zephyr_install_path string
M.minimal_install = function(version, zephyr_install_path)
    Utils.validate("version", version, "string")
    Utils.validate("zephyr_install_path", zephyr_install_path, "string")

    local zephyr_sdk_download_path = Utils.fs.Path(
        { M.get_zephyr_sdk_home(), "downloads" },
        { type = "directory", create = true }
    )
    Utils.inf(
        "Zephyr-SDK installer not found. Installing in zephyr home first",
        { zephyr_sdk_bin_path = zephyr_install_path }
    )
    download_minmal_sdk(version, zephyr_install_path, zephyr_sdk_download_path)

    Utils.sh.safe_exec({ "chmod", "+x", zephyr_install_path }, { fail = true })
    Utils.inf("Minimal Installation successful")
end

---@type table<string, fun(name:string,tool:ZephyrSdkTool)>
M._install_funcs = {

    --- @param name string
    --- @param tool ZephyrSdkTool
    ["(%w+-%w+-%w+)"] = function(name, tool)
        Utils.validate("name", name, "string", "Name must be string")
        Utils.validate("tool", tool, "table", "Tool must be table")
        local zephyr_sdk_bin_path, mise_bin_path = tool.zephyr_install_path, tool.mise_install_path

        local zephyr_sdk_setup_sh = assert(tool.extra["setup_sh"])
        if not Utils.fs.directory_exists(zephyr_sdk_bin_path) then
            Utils.inf("Matched with toolchain install cmd", { toolchain = name })
            if not Utils.sh.safe_exec({ zephyr_sdk_setup_sh, "-t", name }) then
                Utils.fatal("Toolchain not able to install for tool", { tool = tool })
            end
        end
        if not Utils.fs.directory_exists(mise_bin_path) then
            Utils.inf(
                "Zephyr SDK tool installed. Symliniking into mise tool path ",
                { zephyr_sdk_bin_path = zephyr_sdk_bin_path, mise_bin_path = mise_bin_path }
            )
            Utils.fs.symlink(zephyr_sdk_bin_path, mise_bin_path)
            return
        end
    end,
    ["(host)"] = function(_name, tool)
        local zephyr_sdk_setup_sh = assert(tool.extra["setup_sh"])
        if not Utils.sh.safe_exec({ zephyr_sdk_setup_sh, "-h" }) then
            Utils.fatal("Toolchain not able to install for tool", { tool = tool })
        end
    end,
    ["(llvm)"] = function(_name, tool)
        local zephyr_sdk_setup_sh = assert(tool.extra["setup_sh"])
        if not Utils.sh.safe_exec({ zephyr_sdk_setup_sh, "-h" }) then
            Utils.fatal("Toolchain not able to install for tool", { tool = tool })
        end
    end,
    --- @param name string
    --- @param tool ZephyrSdkTool
    ["(west)"] = function(name, tool)
        Utils.validate("name", name, "string", "Name must be string")
        Utils.validate("tool", tool, "table", "Tool must be table")

        local plugin_path = Utils.sh.safe_exec(string.format("realpath %q", RUNTIME.pluginDirPath), { fail = true })
        local local_west = Utils.fs.join_path(plugin_path, "bin", "west")
        if not Utils.fs.exists(tool.mise_install_path) then
            Utils.sh.safe_exec(string.format("cp %q %q", local_west, tool.mise_install_path), { fail = true })
            Utils.inf("Copied west shim", { west_shim = local_west, mise_west = tool.mise_install_path })
        end
        if not Utils.fs.exists(tool.zephyr_install_path) then
            Utils.fs.symlink(tool.mise_install_path, tool.zephyr_install_path)
            Utils.inf(
                "Created symlik to west in Zephyr install path",
                { mise_install_path = tool.mise_install_path, zephyr_west = tool.zephyr_install_path }
            )
        end
    end,
}
return M
