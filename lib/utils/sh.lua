local M = require("cmd") ---@module 'cmd'

--- Returns the current OS name lowercased.
---@return string
function M.get_os()
    return RUNTIME.osType:lower()
end

M.ARCH_MAP = { amd64 = "x86_64", arm64 = "aarch64", x86_64 = "x86_64", aarch64 = "aarch64" }
M.OS_MAP = {
    darwin = "apple-darwin",
    linux = "unknown-linux-gnu",
    windows = "pc-windows-msvc",
}
--- Returns the Artifactory platform triple for the current machine.
--- e.g. "x86_64-unknown-linux-gnu" or "aarch64-apple-darwin"
---@return string
function M.get_platform_triple()
    local os_name = RUNTIME.osType:lower()
    local arch = RUNTIME.archType
    local mapped_arch = M.ARCH_MAP[arch] or arch
    local mapped_os = M.OS_MAP[os_name]
    if not mapped_os then
        Utils.fatal("Unsupported OS", { os = os_name })
    end
    return mapped_arch .. "-" .. mapped_os
end

---@return string? Output
function M.get_mise_tool_prefix(tool)
    local handle = io.popen(string.format("mise which %s 2>/dev/null", tool))
    if not handle then
        return nil
    end
    local tool_path = handle:read("*l")
    handle:close()

    if not tool_path or tool_path == "" then
        return nil
    end

    -- Extract the bin directory from the python path
    local bin_dir = tool_path:match("(.*/)")
    if bin_dir then
        return bin_dir
    end
    return nil
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
