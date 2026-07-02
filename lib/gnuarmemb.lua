--- GNU Arm Embedded toolchain (`arm-none-eabi`).
---
--- Unlike the Zephyr SDK toolchains, this is maintained by Arm, versioned on
--- its own cadence (e.g. "14.2.rel1") and installed outside the SDK tree. It is
--- therefore modelled as a standalone tool rather than a `toolchain` alias.
---
--- Zephyr selects it with `ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb` and locates the
--- compiler via `GNUARMEMB_TOOLCHAIN_PATH` (the toolchain root, i.e. the
--- directory that contains `bin/arm-none-eabi-gcc`).
---@class ZephyrTool
local M = {}

local VARIANT = "gnuarmemb"
local DOWNLOAD_BASE = "https://developer.arm.com/-/media/Files/downloads/gnu"

-- Versions surfaced by `ls-remote`. install() builds the download URL on demand
-- so any Arm-published version string also works, matching the requirement to
-- support gnuarmemb "regardless of version".
local KNOWN_VERSIONS = { "14.3.rel1", "14.2.rel1", "13.3.rel1", "13.2.rel1" }

-- Arm names its host/arch tokens differently from the Zephyr SDK convention, so
-- map explicitly (keyed by Utils.os()/Utils.arch()).
local HOST_TOKENS = {
    linux = { x86_64 = "x86_64", aarch64 = "aarch64" },
    macos = { x86_64 = "darwin-x86_64", aarch64 = "darwin-arm64" },
    windows = { x86_64 = "mingw-w64-i686", aarch64 = "mingw-w64-i686" },
}

--- Resolve the Arm host token for the current platform.
---@return string
local function host_token()
    local os_name, arch = Utils.os(), Utils.arch()
    local token = (HOST_TOKENS[os_name] or {})[arch]
    if not token then
        Utils.fatal("Unsupported host for the gnuarmemb toolchain", { os = os_name, arch = arch })
    end
    return token
end

--- Archive basename (no extension) for a version on this host. Also the name of
--- the single top-level directory inside the archive, used to strip it away.
---@param version string
---@return string
local function asset_basename(version)
    return string.format("arm-gnu-toolchain-%s-%s-arm-none-eabi", version, host_token())
end

--- Full download URL for a version on this host.
---@param version string
---@return string
local function asset_url(version)
    local ext = (Utils.os() == "windows") and ".zip" or ".tar.xz"
    return Utils.fs.join_path(DOWNLOAD_BASE, version, "binrel", asset_basename(version) .. ext)
end

---@return string[] versions
M.list_versions = function()
    return KNOWN_VERSIONS
end

--- Download and extract the GNU Arm Embedded toolchain into install_path.
--- The archive nests everything under a single directory, which is stripped so
--- install_path becomes the toolchain root (the GNUARMEMB_TOOLCHAIN_PATH value).
---@param ctx BackendInstallCtx
---@param opts? ToolOptions
function M.install(ctx, opts)
    Utils.validate("ctx", ctx, "table")
    Utils.validate("opts", opts, "table", true)
    local version, install_path, download_path = ctx.version, ctx.install_path, ctx.download_path
    Utils.validate("version", version, "string")
    Utils.validate("install_path", install_path, "string")
    Utils.validate("download_path", download_path, "string")

    local url = asset_url(version)
    Utils.inf("Downloading GNU Arm Embedded toolchain", { version = version, url = url })
    local res = Utils.net.archived_asset_download(url, install_path, download_path, {
        name = asset_basename(version),
        strip_components = 1,
    })
    if not res then
        Utils.fatal("Failed to install the gnuarmemb toolchain", { version = version, url = url })
    end
    Utils.inf("Installed gnuarmemb toolchain at", { res = res })
end

--- Environment for the GNU Arm Embedded variant. Sets the variant name, the
--- {VARIANT}_TOOLCHAIN_PATH pointer Zephyr uses to find it, and puts the
--- compilers on PATH for direct use.
---@param ctx BackendExecEnvCtx
---@param opts? ToolOptions
---@return EnvKey[]
function M.envs(ctx, opts) -- luacheck: no unused args
    Utils.validate("ctx", ctx, "table")
    local install_path = ctx.install_path
    Utils.validate("install_path", install_path, "string")
    -- Zephyr forms the pointer as <UPPER(variant)>_TOOLCHAIN_PATH.
    local path_var = string.upper(VARIANT) .. "_TOOLCHAIN_PATH"
    return {
        { key = "ZEPHYR_TOOLCHAIN_VARIANT", value = VARIANT },
        { key = path_var, value = install_path },
        { key = "PATH", value = Utils.fs.join_path(install_path, "bin") },
    }
end

return M
