--- LLVM/Clang toolchain variant, packaged inside the Zephyr SDK (>= 1.0.0).
---
--- Like `gnuarmemb`, this is a standalone, option-less tool: the tool name IS
--- the variant (`ZEPHYR_TOOLCHAIN_VARIANT=llvm`). It is deliberately NOT one of
--- the selectable `toolchain` targets and exposes none of the SDK tool options
--- (`toolchains`/`hosttools`/`cmake_pkg`) — any options passed are ignored.
---
--- It reuses the shared Zephyr SDK engine in `toolchain.lua` (download of the
--- SDK, version gating to >= 1.0.0, and the `llvm`-family env vars, which point
--- Zephyr at the toolchain via ZEPHYR_SDK_INSTALL_DIR).
---@class ZephyrTool
local M = {}

local toolchain = require("toolchain")

-- Fixed configuration. User-supplied ctx.options are intentionally not
-- forwarded, so this tool never installs extra toolchains, host tools or the
-- CMake package.
local LLVM_OPTS = { toolchains = "llvm", family = "llvm" }

---@return string[] versions
M.list_versions = function()
    return toolchain.list_versions(LLVM_OPTS)
end

---@param ctx BackendInstallCtx
function M.install(ctx)
    return toolchain.install(ctx, LLVM_OPTS)
end

---@param ctx BackendExecEnvCtx
---@return EnvKey[]
function M.envs(ctx)
    return toolchain.envs(ctx, LLVM_OPTS)
end

return M
