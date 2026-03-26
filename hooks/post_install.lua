--- Performs setup after Zephyr SDK installation.
--- Downloads the arm-zephyr-eabi toolchain and hosttools by running
--- the SDK's setup.sh script, which handles platform-specific logic.
---
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook

--- Runs the SDK's setup.sh to install toolchains and hosttools.
--- The minimal SDK ships with setup.sh which uses wget to download and
--- extract individual toolchain archives from GitHub releases.
---@param tc_root string Path to the toolchain root
---@param tc_install_cmd string Path to the SDK root (contains setup.sh)
---@param toolchain string SDK version
local function install_toolchain_with(tc_root, tc_install_cmd, toolchain)
    local file = require("file")
    local log = require("log")

    log.info("Installing " .. toolchain .. " toolchain via setup.sh...")
    local ok = os.execute(tc_install_cmd)
    if not ok then
        error(tc_install_cmd .. " failed: ")
    end

    local tc_path = file.join_path(tc_root, toolchain)
    if not file.exists(tc_path) then
        log.warn("" .. toolchain .. " directory not found after setup.sh, installation may have failed")
        return
    end
    local tc_gcc = file.join_path(tc_path, "bin", "" .. toolchain .. "-gcc")
    if not file.exists(tc_gcc) then
        log.warn("" .. toolchain .. "-gcc not found at " .. tc_gcc)
        return
    end
    log.info("" .. toolchain .. " toolchain installed at", tc_path)
end

--- Performs additional setup after installation
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook
--- @param ctx {rootPath: string, runtimeVersion: string, sdkInfo: SdkInfo} Context
function PLUGIN:PostInstall(ctx)
    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local version = sdkInfo.version
    local log = require("log")
    local zephyr_sdk = require("zephyr_sdk")
    zephyr_sdk.extract(sdkInfo)
    local sdk_install_paths = zephyr_sdk.sdk_install_paths(sdkInfo)
    local base_install_cmd = "bash " .. sdk_install_paths.installer
    local make_install_cmd = function(toolchain)
        return base_install_cmd .. toolchain
    end
    -- Make setup.sh executable
    os.execute("chmod +x " .. sdk_install_paths.installer)
    -- ── Install arm-zephyr-eabi toolchain ────────────────────────────
    local toolchains = zephyr_sdk.get_toolchains_to_install()
    for _, tc in ipairs(toolchains) do
        local tc_install_cmd = nil
        if not tc:match("-h") then
            log.info("Installing " .. tc .. " toolchain via setup.sh...")
            tc_install_cmd = make_install_cmd(string.format(" -t %s", tc))
            install_toolchain_with(sdk_install_paths.tc_root, tc_install_cmd, version)
        else
            log.info("Installing host tools")
            tc_install_cmd = make_install_cmd(" -h")
            local ok = os.execute(tc_install_cmd)
            if not ok then
                error(tc_install_cmd .. " failed: ")
            end
        end
    end
end
