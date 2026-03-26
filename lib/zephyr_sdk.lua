M = {

    GITHUB_USER = "zephyrproject-rtos",
    GITHUB_REPO = "sdk-ng",
    MIN_VERSION = "0.17.0",
    BREAKING_SDK_VERSION = "1.0.0",
    ---@type table<ZephyrSdkToolchainType,ZephyrSdkToolchainInfo>
    TOOLCHAIN_TYPES = {
        ZEPHYR = {
            tool_install_cmd_mapping = function(tool)
                return " -t " .. tool
            end,
            supported_tools = { "arm-zephyr-eabi", "x86_64-zephyr-elf" },
            supported_versions = function(version)
                local semver = require("semver")
                if semver.compare(version, "1.0.0") < 0 then
                    return true
                end
                return false
            end,
        },
        GNU = {
            tool_install_cmd_mapping = function(tool)
                return " -t " .. tool
            end,
            supported_tools = { "arm-zephyr-eabi", "x86_64-zephyr-elf" },
            supported_versions = function(version)
                local semver = require("semver")
                if semver.compare(version, "1.0.0") >= 0 then
                    return true
                end
                return false
            end,
            additional_prefix = "gnu",
        },
        LLVM = {
            supported_tools = { "llvm" },
            tool_install_cmd_mapping = " -t llvm",
            supported_versions = function(version)
                local semver = require("semver")
                if semver.compare(version, "1.0.0") >= 0 then
                    return true
                end
                return false
            end,
            additional_prefix = "llvm",
        },
        HOST = {
            supported_tools = { "qemu" },
            tool_install_cmd_mapping = " -h",
            supported_versions = function(_version)
                return true
            end,
        },
    },
}
---@type table<string,table<string,ZephyrSdkToolchainType|nil>>
M.toolchain_type_mapping = {
    ["arm-zephyr-eabi|x86_64-zephyr-elf"] = {
        ["1.0.0"] = "GNU",
        ["default"] = "ZEPHYR",
    },
    ["llvm"] = {
        ["1.0.0"] = "LLVM",
        ["default"] = nil,
    },
    ["host"] = {
        ["default"] = "HOST",
    },
}
local function get_platform_archive()
    local ext = RUNTIME.osType:lower() == "windows" and "7z" or "tar.xz"
    return "minimal." .. ext
end
-- create a namespace
---@class ZephyrSdkToolchain
---@field sdkInfo ZephyrSdkInfo Path where the root of toolchain should be installed
---@field toolchainInfo ZephyrSdkToolchainInfo Path where the tool should be installed
---@field installerPath string Path where the tool should be installed
---@field extract fun(self:ZephyrSdkToolchain):nil Path where the <TOOL>/bin directory is located
---@field checkInstall fun(self:ZephyrSdkToolchain):nil Path where the <TOOL>/bin directory is located
ZephyrSdkToolchain = {}
-- create the prototype with default values
ZephyrSdkToolchain.__index = ZephyrSdkToolchain
--- Create new ZephyrSdkToolchain
---@param ctx BackendInstallCtx|BackendExecEnvCtx
---@return ZephyrSdkToolchain
function ZephyrSdkToolchain.new(ctx)
    local file = require("file")
    local semver = require("semver")
    local semver_mapping = M.toolchain_type_mapping[ctx.tool]
    if not semver_mapping then
        error("Could not find tool: " .. ctx.tool)
    end
    local tc_type = semver_mapping["default"]
    for ver, tc in pairs(semver_mapping) do
        if
            ver ~= "default"
            and string.match(ctx.version, "^[0-9]+%.[0-9]+%.[0-9]+$")
            and semver.compare(ctx.version, ver) >= 0
        then
            tc_type = tc
        end
    end
    local tcInfo = M.TOOLCHAIN_TYPES[tc_type]
    if not tcInfo then
        error("Could not find tool: " .. ctx.tool)
    end
    local newToolchain = setmetatable({
        sdkInfo = {
            version = ctx.version,
            installDir = ctx.install_path,
        },
        toolchainInfo = tcInfo,
        installerPath = file.join_path(ctx.install_path, "setup.sh"),
    }, ZephyrSdkToolchain)
    return newToolchain
end
---@param self ZephyrSdkToolchain
---@return string
function ZephyrSdkToolchain:getToolchainRoot()
    local file = require("file")
    local tcInfo = self.toolchainInfo
    local tcRoot = file.join_path(self.sdkInfo.installDir, "zephyr-sdk-" .. self.sdkInfo.version)
    return tcInfo.additional_prefix and file.join_path(tcRoot, tcInfo.additional_prefix) or tcRoot
end

--- Extracts an archive and raises on failure.
function ZephyrSdkToolchain:extract()
    local archiver = require("archiver")
    local http = require("http")
    -- Download the archive
    local archive_path = self.sdkInfo.installDir .. "/" .. get_platform_archive()
    local err = http.download_file({
        url = M.get_download_url({ version = self.sdkInfo.version }),
    }, archive_path)

    if err ~= nil then
        error("Download failed: " .. err)
    end

    -- Extract to installation directory
    err = archiver.decompress(archive_path, self.sdkInfo.installDir)
    if err ~= nil then
        error("Extraction failed: " .. err)
    end

    -- Clean up archive
    os.remove(archive_path)
end
--- https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.0/zephyr-sdk-1.0.0_linux-x86_64_minimal.tar.xz
M.get_repo_url = function()
    return string.format("https://api.github.com/repos/%s/%s/releases", M.GITHUB_USER, M.GITHUB_REPO)
end
---@return string[] versions
M.fetch_releases = function()
    local http = require("http")
    local json = require("json")
    local semver = require("semver")
    local resp, err = http.get({
        url = M.get_repo_url(),
    })

    if err ~= nil then
        error("Failed to fetch versions: " .. err)
    end
    if resp.status_code ~= 200 then
        error("GitHub API returned status " .. resp.status_code .. ": " .. resp.body)
    end

    local tags = json.decode(resp.body)
    local releases = {}

    -- Process tags/releases
    for _, tag_info in ipairs(tags) do
        local version = tag_info.tag_name:gsub("^v", "")
        local is_not_official = version:match("-([%w%d]+)$")
        local is_prerelease = tag_info.prerelease or is_not_official
        local note = is_prerelease and "pre-release" or nil
        if is_prerelease == nil and semver.compare(version, M.MIN_VERSION) >= 0 then
            table.insert(releases, version)
        end
    end
    return releases
end

local function get_platform()
    local os_name = RUNTIME.osType:lower()
    local arch = RUNTIME.archType

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

function ZephyrSdkToolchain:checkInstall()
    local log = require("log")
    local file = require("file")
    local version = self.sdkInfo.version
    local strings = require("strings")
    local sdk_path = file.join_path(self.sdkInfo.installDir, "zephyr-sdk-" .. version)
    local read_sdk_version = strings.trim_space(file.read(file.join_path(sdk_path, "sdk_version")))
    if read_sdk_version ~= version then
        error("SDK version requested " .. version .. " and the one installed " .. read_sdk_version .. " do not match")
    end
    log.info("Checked Zephyr SDK version:", version)
    local installer = file.join_path(sdk_path, "setup.sh")
    if not file.exists(installer) then
        error("setup.sh not found in SDK Install path: " .. sdk_path)
    end
end
---@param tools string[] name of tools to install
function ZephyrSdkToolchain:runInstallCmd(tools)
    -- Make setup.sh executable
    os.execute("chmod +x " .. self.installerPath)
    local base_install_cmd = "bash " .. self.installerPath
    local utils = require("utils")
    local install_cmds = self.toolchainInfo.tool_install_cmd_mapping
    local run_install_cmd = nil
    if type(install_cmds) == "string" then
        local cmd = base_install_cmd .. " " .. install_cmds
        print("Running install cmd: ", cmd)
        os.execute(cmd)
        return
    elseif type(install_cmds) == "table" then
        run_install_cmd = function(tool)
            local tool_cmd = install_cmds[tool]
            if tool_cmd then
                local cmd = base_install_cmd .. " " .. tool_cmd
                print("Running install cmd: ", cmd)
                os.execute(cmd)
            end
        end
    elseif type(install_cmds) == "function" then
        run_install_cmd = function(tool)
            local tool_cmd = install_cmds(tool)
            if tool_cmd then
                local cmd = base_install_cmd .. " " .. tool_cmd
                print("Running install cmd: ", cmd)
                os.execute(cmd)
            end
        end
    end
    if run_install_cmd ~= nil then
        for _, tool in ipairs(tools) do
            if utils.tbl_contains(self.toolchainInfo.supported_tools, tool) then
                print("Installing ", tool, " via cmd setup.sh...")
                run_install_cmd(tool)
            end
        end
    end
end
return M
