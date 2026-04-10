--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv

--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    require("utils")
    local semver = require("semver")
    local sh = require("shell_exec")
    local zephyr_sdk_root = sh.get_zephyr_sdk_home()
    local toolchain_variant = "zephyr"
    if ctx.tool == "llvm" and semver.compare(ctx.version, "1.0.0") >= 0 then
        toolchain_variant = "llvm"
    end
    local bin_path = file.join_path(ctx.install_path, "bin")
    if ctx.tool == "minimal" or ctx.tool == "west" then
        bin_path = ctx.install_path
    end

    local env_vars = {
        {
            key = "ZEPHYR_TOOLCHAIN_VARIANT",
            value = toolchain_variant,
        },
        {
            key = "ZEPHYR_SDK_INSTALL_DIR",
            value = zephyr_sdk_root,
        },
        {
            key = "PATH",
            value = bin_path,
        },
    }

    Utils.inf("Setting up Zephyr SDK environment :", { env_vars = env_vars })
    -- Add toolchain bin directories that exist

    return { env_vars = env_vars }
end
