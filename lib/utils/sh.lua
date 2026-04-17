--- Shell command execution utilities.
--- Wraps mise's built-in `cmd` module with safe execution, cross-platform
--- token expansion, and convenience wrappers for common filesystem operations.

local cmd = require("cmd") ---@module 'cmd'

-- ─── Core execution ──────────────────────────────────────────────────

---@class Utils.sh
local M = {}

--- Execute a shell command and return its captured output.
--- Delegates to mise's built-in `cmd.exec`.

--- Execute a formatted shell command and return its captured output.
---@param fmt string Format string (passed to string.format)
---@param ... any Format arguments
---@return string output Captured stdout
function M.execf(fmt, ...)
    local ok, res = pcall(cmd.exec, string.format(fmt, ...))
    return ok ~= nil and res or ""
end

-- ─── Cross-platform command tokens ───────────────────────────────────
--
-- Tokens like `{mkdir}`, `{copyfile}` embedded in command strings are
-- expanded to platform-specific shell commands by `map_cmds`.

-- ─── Safe execution ──────────────────────────────────────────────────

---@param exec_cmd string[]
---@param fail? boolean
---@return string? output
function M.exec(exec_cmd, fail)
    Utils.validate("exec_cmd", exec_cmd, "table")
    Utils.validate("fail", fail, "boolean", true)
    local sh_cmd = Utils.strings.join(Utils.ensure_list(exec_cmd), " ") or ""
    Utils.dbg("sh.exec: " .. sh_cmd)
    local ok, result = pcall(cmd.exec, sh_cmd)
    if not ok then
        Utils.err("Command failed: " .. sh_cmd)
        if result then
            for _, line in ipairs(Utils.strings.split(tostring(result), "\n")) do
                Utils.err("  " .. line)
            end
        end
        if fail then
            error("Command failed: " .. sh_cmd)
        end
        return nil
    end
    if not result then
        return result
    end
    return Utils.strings.trim_space(result)
end

-- ─── Tool discovery ──────────────────────────────────────────────────

--- Check if an executable exists in PATH.
---@param exe string Executable name
---@return string? path Full path to executable, or nil if not found
function M.which(exe)
    local mise = M.exec({ "which", "mise" }) or Utils.fs.join_path(os.getenv("HOME") or "~", ".local", "bin", "mise")
    return M.exec({ mise, "which", exe })
end

--- Get the bin directory for a mise-managed tool.
---@param tool string Tool name (e.g. "uvx", "python")
---@return string? bin_dir Directory path ending with `/`, or nil
function M.whichdir(tool)
    local tool_path = M.which(tool) or ""
    return tool_path:match("(.*/)")
end

-- ─── Filesystem convenience ──────────────────────────────────────────

--- Resolve the real (absolute, symlink-resolved) path.
---@param filepath string Path to resolve
---@return string? resolved Resolved path, or nil on failure
function M.realpath(filepath)
    return M.exec({ "realpath", filepath }) --[[@as string?]]
end

--- Get the current working directory.
---@return string? cwd Current directory, or nil on failure
function M.cwd()
    return M.exec({ "pwd" }) --[[@as string?]]
end

--- Create a directory and any missing parents.
---@param dir string Directory path to create
---@return boolean success
function M.mkdir(dir)
    return M.exec({ "mkdir", dir }) ~= nil
end

--- Set file permissions (POSIX only).
---@param mode string Permission mode (e.g. "+x", "755")
---@param filepath string File path
---@return boolean success
function M.chmod(mode, filepath)
    return M.exec({ "chmod", mode, filepath }) ~= nil
end

return M
