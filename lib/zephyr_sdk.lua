M = {

    GITHUB_USER = "zephyrproject-rtos",
    GITHUB_REPO = "sdk-ng",
    MIN_VERSION = "0.17.0",
    BREAKING_SDK_VERSION = "1.0.0",
}

--- https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.0/zephyr-sdk-1.0.0_linux-x86_64_minimal.tar.xz
M.get_repo_url = function()
    return string.format("https://api.github.com/repos/%s/%s/releases", M.GITHUB_USER, M.GITHUB_REPO)
end
local function get_platform()
    -- RUNTIME object is provided by mise/vfox
    -- RUNTIME.osType: "Windows", "Linux", "Darwin"
    -- RUNTIME.archType: "amd64", "386", "arm64", etc.

    local os_name = RUNTIME.osType:lower()
    local arch = RUNTIME.archType

    -- Map to your tool's platform naming convention
    -- Adjust these mappings based on how your tool names its releases
    -- https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.17.0/zephyr-sdk-0.17.0_linux-x86_64_minimal.tar.xz
    -- https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.0/zephyr-sdk-1.0.0_linux-x86_64_minimal.tar.xz

    local platform_map = {
        ["darwin"] = {
            ["arm64"] = "macos-aarch64",
        },
        ["linux"] = {
            ["amd64"] = "linux-x86_64",
            ["arm64"] = "linux-aarch64",
        },
        ["windows"] = {
            ["amd64"] = "windows-x86_64",
        },
    }

    local os_map = platform_map[os_name]
    if os_map then
        return os_map[arch] or "linux-x86_64" -- fallback
    end

    -- Default fallback
    return "linux-x86_64"
end
local function get_platform_archive()
    local ext = RUNTIME.osType:lower() == "windows" and "7z" or "tar.xz"
    return "minimal." .. ext
end

--- @param ctx {version: string, runtimeVersion: string} Context
M.get_download_url = function(ctx)
    local clean_version = ctx.version:gsub("^v", "")
    local version_with_v = ctx.version:gsub("^([%d%.]+)$", "v%1") or clean_version
    local asset_version = version_with_v:gsub("^v", "zephyr-sdk-")
    local platform = get_platform()
    local archive = get_platform_archive()

    local asset_suffix = table.concat({ asset_version, platform, archive }, "_")
    return table.concat(
        { "https://github.com/zephyrproject-rtos/sdk-ng/releases/download", version_with_v, asset_suffix },
        "/"
    )
end
M.get_toolchains_to_install = function()
    local os_name = RUNTIME.osType:lower()

    local platform_map = {
        ["darwin"] = { "arm-zephyr-eabi" },
        ["linux"] = { "arm-zephyr-eabi", "x86_64-zephyr-elf", "-h" },
        ["windows"] = { "arm-zephyr-eabi" },
    }

    return platform_map[os_name] or { "arm-zephyr-eabi" } -- fallback
end

--- Downloads a file and raises on failure.
---@param url string
---@param dest string
function M.download(url, dest)
    local http = require("http")
    local err = http.download_file({ url = url }, dest)
    if err ~= nil then
        error("Download failed (" .. url .. "): " .. err)
    end
end

--- Extracts an archive and raises on failure.
M.extract = function(sdkInfo)
    local archiver = require("archiver")
    local http = require("http")
    -- Download the archive
    local archive_path = sdkInfo.path .. "/" .. get_platform_archive()
    local err = http.download_file({
        url = M.get_download_url({ version = sdkInfo.version }),
    }, archive_path)

    if err ~= nil then
        error("Download failed: " .. err)
    end

    -- Extract to installation directory
    err = archiver.decompress(archive_path, sdkInfo.path)
    if err ~= nil then
        error("Extraction failed: " .. err)
    end

    -- Clean up archive
    os.remove(archive_path)
end
--- @param  sdkInfo SdkInfo: SdkInfo Context
M.sdk_install_paths = function(sdkInfo)
    local semver = require("semver")
    local log = require("log")
    local file = require("file")
    local version = sdkInfo.version
    local strings = require("strings")
    local sdk_path = file.join_path(sdkInfo.path, "zephyr-sdk-" .. version)
    local read_sdk_version = strings.trim_space(file.read(file.join_path(sdk_path, "sdk_version")))
    if read_sdk_version ~= version then
        error("SDK version requested " .. version .. " and the one installed " .. read_sdk_version .. " do not match")
    end
    log.info("Checked Zephyr SDK version:", version)
    local installer = file.join_path(sdk_path, "setup.sh")
    if not file.exists(installer) then
        error("setup.sh not found in SDK Install path: " .. sdk_path)
    end
    local paths = { sdk_path = sdk_path, tc_root = sdk_path, installer = file.join_path(sdk_path, "setup.sh") }
    if semver.compare(version, M.BREAKING_SDK_VERSION) >= 0 then
        log.info(
            string.format(
                "SDK version is equal or greater that the breaking change version (%s) : %s",
                M.BREAKING_SDK_VERSION,
                version
            )
        )
        log.info("Appending 'gnu' to sdk_path ", sdk_path)
        paths.tc_root = file.join_path(sdk_path, "gnu")
    end

    return paths
end
return M
