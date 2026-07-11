---@nodoc
require("utils.core")
---@class ZephyrSdk
_G.ZephyrSdk = _G.ZephyrSdk or {}

--- Registry of tools exposed by the plugin. Values decide how the metatable
--- below resolves the tool on first access:
---   * `true`  -> a dedicated module loaded via `require(<key>)`
---     (e.g. `toolchain`, `west`, `gnuarmemb`).
---   * table   -> a `zephyr` (GNU) variant alias over the shared `toolchain`
---     module (see `ZephyrSdk.VariantSpec`), one per SDK cross-compiler target.
---   * string  -> shorthand for `{ target = <string>, family = "zephyr" }`.
---
--- The tool name doubles as the `ZEPHYR_TOOLCHAIN_VARIANT` mental model:
--- arch names (arm, aarch64, …) are the `zephyr` GNU variant, while `llvm` and
--- `gnuarmemb` are standalone, option-less variant tools of their own.
---@class ZephyrSdk._tools : table<string, ZephyrTool>
ZephyrSdk._tools = {
    west = true,
    gnuarmemb = true,
    llvm = { name = "toolchain", options = { target = "llvm", family = "llvm" } },
    ["aarch64"] = { name = "toolchain", options = { target = "aarch64-zephyr-elf", family = "zephyr" } },
    ["arc64"] = { name = "toolchain", options = { target = "arc64-zephyr-elf", family = "zephyr" } },
    ["arc"] = { name = "toolchain", options = { target = "arc-zephyr-elf", family = "zephyr" } },
    ["arm"] = { name = "toolchain", options = { target = "arm-zephyr-eabi", family = "zephyr" } },
    ["microblazeel"] = { name = "toolchain", options = { target = "microblazeel-zephyr-elf", family = "zephyr" } },
    ["mips"] = { name = "toolchain", options = { target = "mips-zephyr-elf", family = "zephyr" } },
    ["nios2"] = { name = "toolchain", options = { target = "nios2-zephyr-elf", family = "zephyr" } },
    ["riscv64"] = { name = "toolchain", options = { target = "riscv64-zephyr-elf", family = "zephyr" } },
    ["rx"] = { name = "toolchain", options = { target = "rx-zephyr-elf", family = "zephyr" } },
    ["sparc"] = { name = "toolchain", options = { target = "sparc-zephyr-elf", family = "zephyr" } },
    ["x86_64"] = { name = "toolchain", options = { target = "x86_64-zephyr-elf", family = "zephyr" } },
}

--- Build a thin wrapper around the generic `toolchain` module that injects the
--- resolved toolchain target and variant family into opts. Lets callers use
--- `zephyr-sdk:arm` as an alias for
--- `zephyr-sdk:toolchain[target='arm-zephyr-eabi',family='zephyr']`.
---@param spec ZephyrTool
---@return ZephyrTool
local function build_toolchain_alias(spec)
    Utils.validate("spec", spec, "table")
    local tool_name = spec.name
    local tool_options = spec.options
    Utils.validate("tool_name", tool_name, "string")
    Utils.validate("tool_options", tool_options, "table")
    local tool = require(tool_name)
    local inject = function(fn)
        return function(ctx)
            Utils.validate("ctx", ctx, "table")
            ctx.options = ctx.options or {}
            ctx.options = Utils.tbl_extend("force", ctx.options, tool_options)
            return fn(ctx)
        end
    end
    return {
        name = spec.name,
        opts = spec.options,
        -- Version availability depends on the variant (e.g. LLVM needs the SDK
        -- >= 1.0.0), so forward the family instead of using the raw list.
        list_versions = inject(tool.list_versions),
        install = inject(tool.install),
        envs = inject(tool.envs),
    }
end

-- Lazy-load tool modules on first access; resolve toolchain aliases on demand.
setmetatable(ZephyrSdk, {
    --- @param t table<string,ZephyrTool>
    __index = function(t, key)
        local spec = ZephyrSdk._tools[key]
        if type(spec) == "boolean" then
            t[key] = require(key)
        elseif type(spec) == "table" then
            t[key] = build_toolchain_alias(spec)
        else
            error("Tool not registered " .. key)
        end
        return t[key]
    end,
})
