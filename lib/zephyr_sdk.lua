---@nodoc
require("utils.core")
---@class ZephyrSdk
_G.ZephyrSdk = _G.ZephyrSdk or {}

---@class ZephyrSdk._tools : table<string, ZephyrTool>
ZephyrSdk._tools = {
    toolchain = true,
    west = true,
}
ZephyrSdk._targets = {
    ["aarch64"] = "aarch64-zephyr-elf",
    ["arc64"] = "arc64-zephyr-elf",
    ["arc"] = "arc-zephyr-elf",
    ["arm"] = "arm-zephyr-eabi",
    ["microblazeel"] = "microblazeel-zephyr-elf",
    ["mips"] = "mips-zephyr-elf",
    ["nios2"] = "nios2-zephyr-elf",
    ["riscv64"] = "riscv64-zephyr-elf",
    ["rx"] = "rx-zephyr-elf",
    ["sparc"] = "sparc-zephyr-elf",
    ["x86_64"] = "x86_64-zephyr-elf",
}

---@type ToolOptions[]
ZephyrSdk.tool_options = {}

--- Build a thin wrapper around the generic `toolchain` module that injects the
--- resolved toolchain name into opts. Lets callers use `zephyr-sdk:arm` as an
--- alias for `zephyr-sdk:toolchain[toolchains='arm-zephyr-eabi']`.
---@param target string Full toolchain name (e.g. "arm-zephyr-eabi")
---@return ZephyrTool
local function build_alias(target)
    local toolchain = require("toolchain")
    local inject = function(fn)
        return function(ctx, opts)
            opts = Utils.tbl_extend("force", opts or {}, { toolchains = target })
            return fn(ctx, opts)
        end
    end
    return {
        list_versions = toolchain.list_versions,
        install = inject(toolchain.install),
        envs = inject(toolchain.envs),
    }
end
--- Build an ncs-flavoured wrapper around the generic `toolchain` / `west` module.
--- Keeps ncs packaged as a pseudo-tool (accessed via `ncs_<tool>`) without a
--- dedicated registry entry.
---@param name string Base tool name ("toolchain" or "west")
---@param tool ZephyrTool Original module to decorate
---@return ZephyrTool
local function build_ncs_variant(name, tool)
    if name == "west" then
        return {
            list_versions = tool.list_versions,
            install = function(ctx, opts)
                opts = Utils.tbl_extend("force", opts or {}, {
                    additional_requirements = {
                        Utils.fs.join_path(RUNTIME.pluginDirPath, "scripts", "requirements-ncs.in"),
                    },
                })
                return tool.install(ctx, opts)
            end,
            envs = tool.envs,
        }
    elseif name == "toolchain" then
        local ncs = require("extras.ncs")
        return {
            list_versions = ncs.list_versions,
            install = ncs.install,
            envs = function(ctx, opts)
                local sdk_ctx = Utils.tbl_extend("force", ctx, {
                    install_path = Utils.fs.join_path(ctx.install_path, "opt", "zephyr-sdk"),
                })
                return tool.envs(sdk_ctx, opts)
            end,
        }
    end
    error("No ncs variant defined for tool " .. name)
end

-- Lazy-load tool modules on first access; resolve toolchain aliases on demand.
setmetatable(ZephyrSdk, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
        local base = key:match("^ncs_(.+)$")
        if base and ZephyrSdk._tools[base] then
            t[key] = build_ncs_variant(base, require(base))
            return t[key]
        end
        if ZephyrSdk._tools[key] then
            t[key] = require(key)
            return t[key]
        end
        local target = ZephyrSdk._targets[key]
        if target then
            t[key] = build_alias(target)
            return t[key]
        end
        error("Tool not registered " .. key)
    end,
})
