--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv

--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    require("utils")
    local zephyr_sdk = require("zephyr_sdk")
    local semver = require("semver")
    local zephyr_sdk_root = zephyr_sdk.get_zephyr_sdk_home() -- this is ~/zephyr-sdk-root
    local zephyr_sdk_install_dir = Utils.fs.join_path(zephyr_sdk_root, "zephyr-sdk-" .. ctx.version) -- ~/zephyr_sdk_root/zephyr-sdk-<VERSION>
    local mise_install_path = ctx.install_path -- ~/zephyr_sdk_root/zephyr-sdk-<VERSION>
    if zephyr_sdk_install_dir == "" and ctx.tool ~= "minimal" then
        Utils.fatal(
            "No toolchains installed! Run `mise install zephyr-sdk:{TOOLCHAIN}@{VERSION}` to be able to install a toolchain ",
            { install_dir = zephyr_sdk_install_dir }
        )
    end
    local toolchain_variant = "zephyr"
    if semver.compare(ctx.version, "1.0.0") >= 0 then
        toolchain_variant = ctx.tool == "llvm" and "llvm" or toolchain_variant
        local path_added = ctx.tool == "llvm" and "llvm" or "gnu"
        zephyr_sdk_install_dir = Utils.fs.Path(
            { zephyr_sdk_install_dir, path_added },
            { type = "directory", fail = true }
        )
    end
    if Utils.fs.directory_exists(Utils.fs.join_path(ctx.install_path, "bin")) then
        mise_install_path = Utils.fs.join_path(ctx.install_path, "bin")
    end
    local env_vars = {
        {
            key = "ZEPHYR_TOOLCHAIN_VARIANT",
            value = toolchain_variant,
        },
        {
            key = "ZEPHYR_SDK_INSTALL_DIR",
            value = zephyr_sdk_install_dir,
        },
        { key = "PATH", value = mise_install_path },
        { key = "PATH", value = zephyr_sdk_install_dir },
    }

    Utils.inf(
        "Scanning Zephyr SDK install directory for toolchains :",
        { zephyr_sdk_install_dir = zephyr_sdk_install_dir }
    )
    local toolchains_installed =
        Utils.fs.scandir(zephyr_sdk_install_dir, { type = "directory", pattern = "(%w+-%w+-%w+)" })
    Utils.inf("Found toolchains :", { toolchains_installed = toolchains_installed })
    for _, tc in ipairs(toolchains_installed) do
        if tc ~= ctx.tool then
            table.insert(env_vars, { key = "PATH", value = Utils.fs.join_path(tc, "bin") })
        end
    end

    Utils.inf("Setting up Zephyr SDK environment :", { env_vars = env_vars })

    return { env_vars = env_vars }
end
