--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv

--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    local log = require("log")
    local install_path = ctx.install_path

    log.debug("Setting up Zephyr SDK environment for", install_path)

    local env_vars = {
        {
            key = "ZEPHYR_TOOLCHAIN_VARIANT",
            value = "zephyr",
        },
        {
            key = "ZEPHYR_SDK_INSTALL_DIR",
            value = install_path,
        },
    }

    -- Add toolchain bin directories that exist.
    -- SDK >= 1.0.0 places toolchains under a `gnu/` subdirectory.
    local arm_bin = file.join_path(install_path, "arm-zephyr-eabi", "bin")
    local arm_bin_gnu = file.join_path(install_path, "gnu", "arm-zephyr-eabi", "bin")
    if file.exists(arm_bin) then
        table.insert(env_vars, { key = "PATH", value = arm_bin })
        log.debug("PATH +=", arm_bin)
    elseif file.exists(arm_bin_gnu) then
        table.insert(env_vars, { key = "PATH", value = arm_bin_gnu })
        log.debug("PATH +=", arm_bin_gnu)
    end

    local x86_bin = file.join_path(install_path, "x86_64-zephyr-elf", "bin")
    local x86_bin_gnu = file.join_path(install_path, "gnu", "x86_64-zephyr-elf", "bin")
    if file.exists(x86_bin) then
        table.insert(env_vars, { key = "PATH", value = x86_bin })
        log.debug("PATH +=", x86_bin)
    elseif file.exists(x86_bin_gnu) then
        table.insert(env_vars, { key = "PATH", value = x86_bin_gnu })
        log.debug("PATH +=", x86_bin_gnu)
    end

    return { env_vars = env_vars }
end
