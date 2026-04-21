---@nodoc
require("utils.core")
---@class ZephyrSdk
_G.ZephyrSdk = _G.ZephyrSdk or {}

---@class ZephyrSdk._tools : table<string, ZephyrTool>
ZephyrSdk._tools = {
    toolchain = true,
    ncs_toolchain = true,
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

-- Lazy-load tool modules on first access; resolve toolchain aliases on demand.
setmetatable(ZephyrSdk, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
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
