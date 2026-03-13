--- Returns download information for a specific Zephyr SDK version.
--- Downloads the minimal SDK (cmake files, sdk_version, setup scripts).
--- The arm-zephyr-eabi toolchain and hosttools are downloaded in post_install.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook
--- @param ctx PreInstallCtx
--- @return ZephyrSdkAssetResult
function PLUGIN:PreInstall(ctx)
    local zephyr_sdk = require("zephyr_sdk")
    return zephyr_sdk.find_minimal_sdk(ctx.version)
end
