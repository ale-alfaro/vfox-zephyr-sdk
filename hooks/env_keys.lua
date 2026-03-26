--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook
--- @param ctx EnvKeysCtx
--- @return EnvKey[]
function PLUGIN:EnvKeys(ctx)
    local file = require("file")
    local log = require("log")
    local zephyr_sdk = require("zephyr_sdk")
    local mainPath = ctx.path
    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path
    local version = sdkInfo.version

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

    local toolchains = zephyr_sdk.get_toolchains_to_install()
    local sdk_path = file.join_path(path, "zephyr-sdk-" .. version)
    for idx in 1, #toolchains do
        local tc = toolchains[idx]
        -- Add toolchain bin directories that exist
        local bin_path = file.join_path(sdk_path, tc, "bin")
        if file.exists(bin_path) then
            table.insert(env_vars, { key = "PATH", value = bin_path })
            log.debug("PATH +=", bin_path)
        end
    end

    return env_vars
end
