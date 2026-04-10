local M = {}

local cmd = require("cmd")
local strings = require("strings")
function M.shell_quote(value)
    local str = tostring(value or "")
    return "'" .. str:gsub("'", "'\"'\"'") .. "'"
end

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
---@param exec_cmd string
---@param opts CmdExecOpts?
---@param fail boolean? If true a failure in the command exec will error out
---@return string? Output
function M.safe_exec(exec_cmd, opts, fail)
    if type(exec_cmd) ~= "string" then
        Utils.err("Command invalid: ", { exec_cmd = exec_cmd })
    end
    Utils.inf("Executing command: ", { cmd = exec_cmd })
    local success, res
    if opts then
        success, res = pcall(cmd.exec, exec_cmd, opts)
    else
        success, res = pcall(cmd.exec, exec_cmd)
    end
    if not success then
        if fail then
            Utils.fatal("Command execution failed : ", { res = res })
        else
            Utils.err("Command execution failed : ", { res = res })
        end
        return nil
    end
    return strings.trim_space(res)
end
-- function M.mv(src, dst)
--   os.rename(src, dst)
-- end

return M
