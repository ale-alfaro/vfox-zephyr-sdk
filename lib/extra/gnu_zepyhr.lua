--- @class ZephyrSdkTool
local M = {}
M.install = function(name, tool)
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
end

return M
