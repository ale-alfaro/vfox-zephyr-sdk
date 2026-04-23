--- Shell command execution utilities.
--- Wraps mise's built-in `cmd` module with safe execution, cross-platform
--- token expansion, and convenience wrappers for common filesystem operations.

local cmd = require("cmd") ---@module 'cmd'

-- ─── Core execution ──────────────────────────────────────────────────

---@class Utils.sh
local M = {}

--- Execute a shell command and return its captured output.
--- Delegates to mise's built-in `cmd.exec`.

-- ─── Safe execution ──────────────────────────────────────────────────

---@param exec_cmd string[]
---@param opts? utils.CmdExecOpts
---@return string? output
function M.exec(exec_cmd, opts)
    Utils.validate("exec_cmd", exec_cmd, "table")
    Utils.validate("opts", opts, "table", true)
    opts = opts or {}
    local sh_cmd = Utils.strings.join(Utils.ensure_list(exec_cmd), " ") or ""
    Utils.dbg("sh.exec: " .. sh_cmd)
    local ok, result = pcall(cmd.exec, sh_cmd)
    if not ok then
        if not opts.silent then
            Utils.err("Command failed", { cmd = sh_cmd })
            if type(result) == "string" then
                Utils.err("stderr:  " .. result)
            end
        end
        if opts.fail then
            assert(false)
        end
        return nil
    end
    return result ~= nil and Utils.strings.trim_space(result) or ""
end

--- Execute a formatted shell command and return its captured output.
---@param opts? utils.CmdExecOpts
---@param fmt string Format string (passed to string.format)
---@param ... any Format arguments
---@return string|nil output Captured stdout
function M.execf(opts, fmt, ...)
    return M.exec(Utils.strings.split(string.format(fmt, ...), " "), opts)
end
-- ─── Tool discovery ──────────────────────────────────────────────────

--- Check if an executable exists in PATH.
---@param exe string Executable name
---@return string? path Full path to executable, or nil if not found
function M.which(exe)
    local mise = M.exec({ "which", "mise" }, { silent = true })
        or Utils.fs.join_path(os.getenv("HOME") or "~", ".local", "bin", "mise")
    local bin_path = M.exec({ mise, "which", exe }, { silent = true }) or M.exec({ "which", exe }, { silent = true })
    return (bin_path ~= "") and bin_path or nil
end

--- Get the bin directory for a mise-managed tool.
---@param tool string Tool name (e.g. "uvx", "python")
---@return string? bin_dir Directory path ending with `/`, or nil
function M.whichdir(tool)
    local tool_path = M.which(tool)
    return (tool_path ~= nil) and tool_path:match("(.*/)") or nil
end

-- ─── Filesystem convenience ──────────────────────────────────────────

--- Resolve the real (absolute, symlink-resolved) path.
---@param filepath string Path to resolve
---@return string? resolved Resolved path, or nil on failure
function M.realpath(filepath)
    return M.exec({ "realpath", filepath }, { fail = true }) --[[@as string?]]
end

--- Get the current working directory.
---@return string? cwd Current directory, or nil on failure
function M.cwd()
    return M.exec({ "pwd" }, { fail = true }) --[[@as string?]]
end

--- Create a directory and any missing parents.
---@param dir string Directory path to create
function M.mkdir(dir)
    M.exec({ "mkdir", "-p", dir }, { fail = true })
end

--- Set file permissions (POSIX only).
---@param mode string Permission mode (e.g. "+x", "755")
---@param filepath string File path
function M.chmod(mode, filepath)
    M.exec({ "chmod", mode, filepath }, { fail = true })
end

return M
