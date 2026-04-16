local M = require("cmd") ---@module 'cmd'

local function get_mise_path()
    local which_cmd = string.format("which mise 2>/dev/null")
    local mise_path = M.exec(which_cmd)
    if mise_path ~= "" then
        return Utils.strings.trim_space(mise_path)
    end
    return Utils.fs.join_path(os.getenv("HOME") or "~", ".local", "bin", "mise")
end

---@param tool string
---@return string? Output
function M.get_mise_tool_prefix(tool)
    local which_cmd = string.format("%s which %s 2>/dev/null", get_mise_path(), tool)
    local tool_path = M.exec(which_cmd)

    if not tool_path or tool_path == "" then
        error("No tool path")
        return nil
    end

    -- Extract the bin directory from the python path
    local bin_dir = tool_path:match("(.*/)")
    if bin_dir then
        return bin_dir
    end
    error("tool path is not valid")
    return nil
end
---@param exec_cmd string|string[]
---@param opts SafeCmdExecOpts?
---@return string|string[]|nil Output
function M.safe_exec(exec_cmd, opts)
    Utils.validate("exec_cmd", exec_cmd, { "string", "table" }, "Exec cmd must be string or array")
    Utils.validate("opts", opts, "table", true)
    opts = opts or {}
    exec_cmd = exec_cmd or ""
    local sh_cmd = Utils.strings.join(Utils.ensure_list(exec_cmd), " ") or ""
    local ok, result
    Utils.inf("Executing command: " .. sh_cmd)
    ok, result = pcall(M.exec, sh_cmd, opts)
    if not ok then
        Utils.err("Command execution failed : ")
        if result then
            local err_msg = Utils.strings.split(tostring(result) or "", "\n")
            for _, line in ipairs(err_msg) do
                Utils.err(line)
            end
        end
        if opts.fail then
            error("Command execution failed")
        end
        return nil
    end
    if opts.output_lines then
        return Utils.strings.split(result, "\n")
    end
    return Utils.strings.trim_space(result)
end

function M.has_cmd(exe)
    local cmd_map = {
        darwin = "which",
        linux = "which",
        windows = "where",
    }
    local c = cmd_map[M.get_os()] or "which"
    return M.safe_exec({ c, exe })
end

return M
