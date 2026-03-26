--- Downloads and installs the Zephyr SDK for a specific version.
--- Handles the full lifecycle: download minimal SDK, extract, normalize,
--- and install toolchains via setup.sh.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall

--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    local http = require("http")
    local archiver = require("archiver")
    local file = require("file")
    local log = require("log")
    local cmd = require("cmd")
    local strings = require("strings")
    local zephyr_sdk = require("zephyr_sdk")

    local version = ctx.version
    local install_path = ctx.install_path
    local download_path = ctx.download_path

    -- ── Download minimal SDK ────────────────────────────────────────────
    local url = zephyr_sdk.get_download_url({ version = version })
    local archive_name = url:match("([^/]+)$")
    local archive_path = file.join_path(download_path, archive_name)

    log.info("Downloading minimal SDK:", url)
    local err = http.download_file({ url = url }, archive_path)
    if err ~= nil then
        error("Download failed (" .. url .. "): " .. err)
    end

    -- ── Extract archive ─────────────────────────────────────────────────
    log.info("Extracting SDK to", install_path)
    err = archiver.decompress(archive_path, install_path)
    if err ~= nil then
        error("Extraction failed (" .. archive_path .. "): " .. err)
    end

    os.remove(archive_path)

    -- ── Normalise SDK root ──────────────────────────────────────────────
    -- The minimal SDK tar may extract with a top-level zephyr-sdk-<ver>/
    -- directory. Flatten it so the SDK root is always `install_path`.
    if not file.exists(file.join_path(install_path, "sdk_version")) then
        local subdir = file.join_path(install_path, "zephyr-sdk-" .. version)
        if not file.exists(file.join_path(subdir, "sdk_version")) then
            error("Invalid Zephyr SDK: sdk_version not found in " .. install_path .. " or " .. subdir)
        end
        log.debug("Flattening SDK subdirectory:", subdir, "→", install_path)
        local ok, mv_err = pcall(
            cmd.exec,
            "mv " .. subdir .. "/* " .. subdir .. "/.??* " .. install_path .. "/ 2>/dev/null; rm -rf " .. subdir
        )
        if not ok then
            error("Failed to flatten SDK directory: " .. tostring(mv_err))
        end
    end

    local sdk_version = strings.trim_space(file.read(file.join_path(install_path, "sdk_version")))
    log.info("Zephyr SDK version:", sdk_version)

    -- ── Install toolchains and hosttools via setup.sh ───────────────────
    local setup_sh = file.join_path(install_path, "setup.sh")
    if not file.exists(setup_sh) then
        error("setup.sh not found in " .. install_path)
    end
    cmd.exec("chmod +x " .. setup_sh)

    local toolchains = zephyr_sdk.get_toolchains_to_install()
    for _, tc in ipairs(toolchains) do
        if tc == "-h" then
            log.info("Installing host tools via setup.sh...")
            local ok = os.execute("bash " .. setup_sh .. " -h")
            if not ok then
                error("setup.sh -h failed")
            end
        else
            log.info("Installing " .. tc .. " toolchain via setup.sh...")
            local ok = os.execute("bash " .. setup_sh .. " -t " .. tc)
            if not ok then
                error("setup.sh -t " .. tc .. " failed")
            end
        end
    end

    return {}
end
