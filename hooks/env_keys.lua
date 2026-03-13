--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook
--- @param ctx EnvKeysCtx
--- @return EnvKey[]
function PLUGIN:EnvKeys(ctx)
    local file = require("file")
    local log = require("log")
    local mainPath = ctx.path

    log.debug("Setting up Zephyr SDK environment for", mainPath)

    local env_vars = {
        {
            key = "ZEPHYR_TOOLCHAIN_VARIANT",
            value = "zephyr",
        },
        {
            key = "ZEPHYR_SDK_INSTALL_DIR",
            value = mainPath,
        },
    }

    -- Add toolchain bin directories that exist
    local arm_bin = file.join_path(mainPath, "arm-zephyr-eabi", "bin")
    if file.exists(arm_bin) then
        table.insert(env_vars, { key = "PATH", value = arm_bin })
        log.debug("PATH +=", arm_bin)
    end

    local x86_bin = file.join_path(mainPath, "x86_64-zephyr-elf", "bin")
    if file.exists(x86_bin) then
        table.insert(env_vars, { key = "PATH", value = x86_bin })
        log.debug("PATH +=", x86_bin)
    end

    return env_vars
end
