--- nrfutil launcher + sdk-manager bootstrap.
--- Installs the platform-specific nrfutil launcher at install_path/nrfutil
--- (or nrfutil.exe on Windows) and bootstraps the sdk-manager core module
--- with NRFUTIL_HOME pinned to install_path so nothing leaks into ~/.nrfutil.

---@class ZephyrTool
local M = {}

local LAUNCHER_BASE =
    Utils.fs.join_path("https://files.nordicsemi.com", "artifactory", "swtools", "external", "nrfutil", "executables")

-- Triple per platform. macOS ships a universal binary so aarch64/x86_64 share it.
local LAUNCHER_TRIPLE = {
    linux = { x86_64 = "x86_64-unknown-linux-gnu" },
    darwin = { x86_64 = "universal-apple-darwin", aarch64 = "universal-apple-darwin" },
    windows = { x86_64 = "x86_64-pc-windows-msvc" },
}

local function launcher_url()
    local os_name = Utils.os()
    local arch = Utils.arch()
    local triple = LAUNCHER_TRIPLE[os_name] and LAUNCHER_TRIPLE[os_name][arch]
    if not triple then
        Utils.fatal("nrfutil launcher not published for this platform", { os = os_name, arch = arch })
        error()
    end
    local exe = (os_name == "windows") and "nrfutil.exe" or "nrfutil"
    return Utils.fs.join_path(LAUNCHER_BASE, triple, exe), exe
end

--- The launcher is unversioned at artifactory; sdk-manager and other modules
--- carry their own versions inside nrfutil itself. Exposing "latest" lets mise
--- pin the install in the toml without us inventing a versioning scheme.
---@return string[]
function M.list_versions()
    return { "latest" }
end

---@param ctx BackendInstallCtx
function M.install(ctx)
    Utils.validate("ctx", ctx, "table")
    Utils.validate("install_path", ctx.install_path, "string")

    local url, exe = launcher_url()
    local launcher = Utils.fs.join_path(ctx.install_path, exe)

    Utils.inf("Downloading nrfutil launcher", { url = url, dest = launcher })
    local ok, err = Utils.net.download_with_progress(url, launcher)
    if not ok then
        Utils.fatal("Failed to download nrfutil launcher", { err = err })
        error()
    end
    if Utils.os() ~= "windows" then
        Utils.sh.chmod("+x", launcher)
    end

    Utils.inf("Bootstrapping sdk-manager core module", { home = ctx.install_path })
    -- setenv (not opts.env) so the existing PATH / HOME / TMPDIR are preserved
    -- when nrfutil shells out to fetch the core-module tarball.
    require("env").setenv("NRFUTIL_HOME", ctx.install_path)
    Utils.sh.exec({ launcher, "install", "sdk-manager" }, { fail = true })
end

---@param ctx BackendExecEnvCtx
---@return EnvKey[]
function M.envs(ctx) -- luacheck: no unused args
    Utils.validate("ctx", ctx, "table")
    Utils.validate("install_path", ctx.install_path, "string")
    return {
        { key = "PATH", value = ctx.install_path },
        { key = "NRFUTIL_HOME", value = ctx.install_path },
    }
end

return M
