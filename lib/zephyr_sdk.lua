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
    toolchain = true,
    west = true,
    -- Standalone, option-less variant tools. `llvm` is the SDK-packaged
    -- LLVM/Clang variant (SDK >= 1.0.0); `gnuarmemb` is the Arm GNU Toolchain
    -- (arm-none-eabi), which lives outside the SDK with its own source,
    -- versioning and install layout.
    llvm = true,
    gnuarmemb = true,
    -- `zephyr` (GNU) variant: one entry per Zephyr SDK cross-compiler target.
    ["aarch64"] = { target = "aarch64-zephyr-elf", family = "zephyr" },
    ["arc64"] = { target = "arc64-zephyr-elf", family = "zephyr" },
    ["arc"] = { target = "arc-zephyr-elf", family = "zephyr" },
    ["arm"] = { target = "arm-zephyr-eabi", family = "zephyr" },
    ["microblazeel"] = { target = "microblazeel-zephyr-elf", family = "zephyr" },
    ["mips"] = { target = "mips-zephyr-elf", family = "zephyr" },
    ["nios2"] = { target = "nios2-zephyr-elf", family = "zephyr" },
    ["riscv64"] = { target = "riscv64-zephyr-elf", family = "zephyr" },
    ["rx"] = { target = "rx-zephyr-elf", family = "zephyr" },
    ["sparc"] = { target = "sparc-zephyr-elf", family = "zephyr" },
    ["x86_64"] = { target = "x86_64-zephyr-elf", family = "zephyr" },
}

---@class ZephyrSdk.VariantSpec
---@field target string Toolchain passed to `setup.sh -t` (e.g. "arm-zephyr-eabi", "llvm")
---@field family ZephyrSdkToolchainFamily Value exported as `ZEPHYR_TOOLCHAIN_VARIANT`

--- Build a thin wrapper around the generic `toolchain` module that injects the
--- resolved toolchain target and variant family into opts. Lets callers use
--- `zephyr-sdk:arm` as an alias for
--- `zephyr-sdk:toolchain[toolchains='arm-zephyr-eabi',family='zephyr']`.
---@param spec ZephyrSdk.VariantSpec
---@return ZephyrTool
local function build_toolchain_alias(spec)
    local toolchain = require("toolchain")
    local overrides = { toolchains = spec.target, family = spec.family }
    local inject = function(fn)
        return function(ctx, opts)
            opts = Utils.tbl_extend("force", opts or {}, overrides)
            return fn(ctx, opts)
        end
    end
    return {
        -- Version availability depends on the variant (e.g. LLVM needs the SDK
        -- >= 1.0.0), so forward the family instead of using the raw list.
        list_versions = function()
            return toolchain.list_versions(overrides)
        end,
        install = inject(toolchain.install),
        envs = inject(toolchain.envs),
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
        elseif type(spec) == "string" then
            t[key] = build_toolchain_alias({ target = spec, family = "zephyr" })
        else
            error("Tool not registered " .. key)
        end
        return t[key]
    end,
})
