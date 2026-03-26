--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv

--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    local log = require("log")
    local semver = require("semver")
    local zephyr_sdk = require("zephyr_sdk")

    local install_path = ctx.install_path
    local version = ctx.version
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

    -- SDK >= 1.0.0 places toolchains under a gnu/ subdirectory
    local tc_root = install_path
    if semver.compare(version, zephyr_sdk.BREAKING_SDK_VERSION) >= 0 then
        tc_root = file.join_path(install_path, "gnu")
    end

    -- Add toolchain bin directories that exist
    local toolchain_names = { "arm-zephyr-eabi", "x86_64-zephyr-elf" }
    for _, tc_name in ipairs(toolchain_names) do
        local bin_path = file.join_path(tc_root, tc_name, "bin")
        if file.exists(bin_path) then
            table.insert(env_vars, { key = "PATH", value = bin_path })
            log.debug("PATH +=", bin_path)
        end
    end

    return { env_vars = env_vars }
end
