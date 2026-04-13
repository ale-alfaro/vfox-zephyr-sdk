local M = require("cmd") ---@module 'cmd'

function M.shell_quote(value)
    local str = tostring(value or "")
    return "'" .. str:gsub("'", "'\"'\"'") .. "'"
end

---@class ShCmdExecOpts : CmdExecOpts
---@field fail? boolean If true a failure in the command exec will error out

---@param exec_cmd string|string[]
---@param opts ShCmdExecOpts?
---@return string? Output
function M.safe_exec(exec_cmd, opts)
    Utils.validate("exec_cmd", exec_cmd, { "string", "table" }, "Exec cmd must be string or array")
    Utils.validate("opts", opts, "table", true)
    opts = opts or {}
    local cmd
    if type(exec_cmd) == "table" and Utils.islist(exec_cmd) then
        cmd = Utils.strings.join(exec_cmd, " ")
    elseif type(exec_cmd) == "string" then
        cmd = exec_cmd
    else
        Utils.err("Command invalid: ", { exec_cmd = exec_cmd })
    end
    Utils.inf("Executing command: ", { cmd = cmd })
    local ok, result = pcall(M.exec, cmd, opts)
    if not ok then
        local err_msg = tostring(result)
        if opts.fail then
            Utils.fatal("Command execution failed : ", { err = err_msg })
        else
            Utils.err("Command execution failed : ", { err = err_msg })
        end
        return nil
    end
    return Utils.strings.trim_space(result)
end
-- function M.mv(src, dst)
--   os.rename(src, dst)
-- end

return M
