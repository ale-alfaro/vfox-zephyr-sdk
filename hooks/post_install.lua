--- Performs setup after Zephyr SDK installation.
--- Downloads the arm-zephyr-eabi toolchain and hosttools by running
--- the SDK's setup.sh script, which handles platform-specific logic.
---
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook
--- @param ctx PostInstallCtx
function PLUGIN:PostInstall(ctx)
    local file = require("file")
    local log = require("log")
    local cmd = require("cmd")
    local strings = require("strings")
    local zephyr_sdk = require("zephyr_sdk")
    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path
    local version = sdkInfo.version

    -- ── Normalise SDK root ────────────────────────────────────────────
    -- The minimal SDK tar may extract with a top-level zephyr-sdk-<ver>/
    -- directory. Flatten it so the SDK root is always `path`.
    if not file.exists(file.join_path(path, "sdk_version")) then
        local subdir = file.join_path(path, "zephyr-sdk-" .. version)
        if not file.exists(file.join_path(subdir, "sdk_version")) then
            error("Invalid Zephyr SDK: sdk_version not found in " .. path .. " or " .. subdir)
        end
        log.debug("Flattening SDK subdirectory:", subdir, "→", path)
        local ok, err = pcall(
            cmd.exec,
            "mv " .. subdir .. "/* " .. subdir .. "/.??* " .. path .. "/ 2>/dev/null; rm -rf " .. subdir
        )
        if not ok then
            error("Failed to flatten SDK directory: " .. tostring(err))
        end
    end

    local sdk_version = strings.trim_space(file.read(file.join_path(path, "sdk_version")))
    log.info("Zephyr SDK version:", sdk_version)

    -- ── Install toolchains and hosttools via setup.sh ─────────────────
    zephyr_sdk.install_from_setup_sh(path)
end
