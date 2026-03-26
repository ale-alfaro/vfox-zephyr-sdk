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
    local asset = zephyr_sdk.find_minimal_sdk(version)
    local archive_path = file.join_path(download_path, asset.name)

    log.info("Downloading minimal SDK:", asset.url)
    local err = http.download_file({ url = asset.url }, archive_path)
    if err ~= nil then
        error("Download failed (" .. asset.url .. "): " .. err)
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
    zephyr_sdk.install_from_setup_sh(install_path, sdk_version)

    return {}
end
