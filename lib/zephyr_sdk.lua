local http = require("http")
local json = require("json")
local strings = require("strings")
local log = require("log")

local M = {}

local GITHUB_REPO = "zephyrproject-rtos/sdk-ng"
local RELEASES_URL = "https://api.github.com/repos/" .. GITHUB_REPO .. "/releases"
local MIN_VERSION = "0.16.0"

function M.get_platform()
    local os_map = { linux = "linux", darwin = "macos" }
    local arch_map = { amd64 = "x86_64", arm64 = "aarch64", x86_64 = "x86_64", aarch64 = "aarch64" }
    local os_name = os_map[RUNTIME.osType] or RUNTIME.osType
    local arch = arch_map[RUNTIME.archType] or RUNTIME.archType
    log.debug(
        "Platform:",
        os_name .. "-" .. arch,
        "(osType=" .. RUNTIME.osType .. ", archType=" .. RUNTIME.archType .. ")"
    )
    return os_name, arch
end

--- Scrapes the GitHub releases HTML page to get release tags.
--- This avoids the GitHub API rate limit that affects unauthenticated requests.
---@return ZephyrSdkRelease[]
function M.fetch_releases()
    local html = require("html")
    local semver = require("semver")

    log.info("Fetching Zephyr SDK releases from GitHub...")
    local resp, err = http.get({
        url = "https://github.com/zephyrproject-rtos/sdk-ng/releases",
    })
    if err ~= nil then
        error("Failed to fetch releases page: " .. err)
    end

    local doc = html.parse(resp.body)
    local release_links = doc:find("a[href*='/releases/tag/']")
    local releases = {}

    for _, element in ipairs(release_links) do
        local href = element:attr("href")
        local tag = href:match("/releases/tag/(.+)")
        if tag and string.match(tag, "^v%d+%.%d+%.%d+") then
            local version = tag:gsub("^v", "")
            if semver.compare(version, MIN_VERSION) >= 0 then
                table.insert(releases, {
                    tag_name = tag,
                    prerelease = false, -- HTML scraping cannot detect pre-releases
                })
            end
        end
    end

    log.info("Found", #releases, "releases (>= " .. MIN_VERSION .. ")")
    return releases
end

local release_cache = {}

--- Fetches a specific release by tag from the GitHub API and caches it.
---@param version string Version without "v" prefix
---@return ZephyrSdkRelease
function M.fetch_release(version)
    local tag = "v" .. version
    if release_cache[tag] then
        return release_cache[tag]
    end

    log.debug("Fetching release details for", tag, "from GitHub API...")
    local resp, err = http.get({ url = RELEASES_URL .. "/tags/" .. tag })
    if err ~= nil then
        error("Failed to fetch release " .. tag .. ": " .. err)
    end
    if resp.status_code ~= 200 then
        error("Zephyr SDK release " .. tag .. " not found (HTTP " .. resp.status_code .. ")")
    end

    local ok, release = pcall(json.decode, resp.body)
    if not ok then
        error("Failed to parse release JSON for " .. tag .. ": " .. tostring(release))
    end

    release_cache[tag] = release
    return release
end

--- Returns the minimal SDK download (cmake files, sdk_version, setup scripts).
---@param version string
---@return ZephyrSdkAssetResult
function M.find_minimal_sdk(version)
    local os_name, arch = M.get_platform()
    local platform = os_name .. "-" .. arch
    local suffix = "_" .. platform .. "_minimal.tar.xz"
    local release = M.fetch_release(version)

    for _, asset in ipairs(release.assets) do
        if strings.has_suffix(asset.name, suffix) then
            log.info("Minimal SDK asset:", asset.name)
            return { version = version, url = asset.browser_download_url, name = asset.name }
        end
    end
    error("No minimal SDK found for " .. platform .. " in release v" .. version)
end

--- Downloads a file and raises on failure.
---@param url string
---@param dest string
function M.download(url, dest)
    local err = http.download_file({ url = url }, dest)
    if err ~= nil then
        error("Download failed (" .. url .. "): " .. err)
    end
end

--- Extracts an archive and raises on failure.
---@param archive string
---@param dest string
function M.extract(archive, dest)
    local archiver = require("archiver")
    local err = archiver.decompress(archive, dest)
    if err ~= nil then
        error("Extraction failed (" .. archive .. "): " .. err)
    end
end

--- Runs the SDK's setup.sh to install toolchains and hosttools.
--- The minimal SDK ships with setup.sh which uses wget to download and
--- extract individual toolchain archives from GitHub releases.
---@param sdk_path string Path to the SDK root (contains setup.sh)
function M.install_from_setup_sh(sdk_path)
    local file = require("file")
    local cmd = require("cmd")

    local installer = file.join_path(sdk_path, "setup.sh")
    if not file.exists(installer) then
        error("setup.sh not found in SDK root: " .. sdk_path)
    end

    -- Make setup.sh executable
    local ok, err = pcall(cmd.exec, "chmod +x " .. installer)
    if not ok then
        error("Failed to chmod +x setup.sh: " .. tostring(err))
    end

    -- ── Install arm-zephyr-eabi toolchain ────────────────────────────
    log.info("Installing arm-zephyr-eabi toolchain via setup.sh...")
    ok, err = pcall(cmd.exec, "bash " .. installer .. " -t arm-zephyr-eabi", { timeout = 300000 })
    if not ok then
        error("setup.sh -t arm-zephyr-eabi failed: " .. tostring(err))
    end

    local arm_tc = file.join_path(sdk_path, "arm-zephyr-eabi")
    if not file.exists(arm_tc) then
        error("arm-zephyr-eabi directory not found after setup.sh")
    end
    local arm_gcc = file.join_path(arm_tc, "bin", "arm-zephyr-eabi-gcc")
    if not file.exists(arm_gcc) then
        error("arm-zephyr-eabi-gcc not found at " .. arm_gcc)
    end
    log.info("arm-zephyr-eabi toolchain installed at", arm_tc)

    -- ── Install hosttools (platform-specific) ────────────────────────
    if RUNTIME.osType == "linux" then
        log.info("Installing x86_64-zephyr-elf toolchain and hosttools via setup.sh...")
        ok, err = pcall(cmd.exec, "bash " .. installer .. " -t x86_64-zephyr-elf -h", { timeout = 300000 })
        if not ok then
            log.warn("setup.sh -t x86_64-zephyr-elf -h failed: " .. tostring(err))
            return
        end

        local host_tc = file.join_path(sdk_path, "x86_64-zephyr-elf")
        if not file.exists(host_tc) then
            log.warn("x86_64-zephyr-elf directory not found after setup.sh, hosttools may have failed")
            return
        end
        local host_gcc = file.join_path(host_tc, "bin", "x86_64-zephyr-elf-gcc")
        if not file.exists(host_gcc) then
            log.warn("x86_64-zephyr-elf-gcc not found at " .. host_gcc)
            return
        end
        log.info("x86_64-zephyr-elf toolchain installed at", host_tc)
    elseif RUNTIME.osType == "darwin" then
        log.info("Installing hosttools for macOS via setup.sh...")
        ok, err = pcall(cmd.exec, "bash " .. installer .. " -h", { timeout = 300000 })
        if not ok then
            log.warn("setup.sh -h failed on macOS: " .. tostring(err))
            log.warn("macOS hosttools may not be available for this SDK version")
            return
        end
        log.info("macOS hosttools installation complete")
    elseif RUNTIME.osType == "windows" then
        log.warn("Windows is not supported by this plugin. Zephyr SDK setup.sh only supports Linux and macOS.")
    end
end

return M
