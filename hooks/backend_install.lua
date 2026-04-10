---@class MiseToolPaths
---@field installs string
---@field downloads string
---@field shims string
---@field executables? string[]
ToolPathCache = {}

---@param tool_name string
---@param tool_install ZephyrSdkTool
---@param mise_home string
local create_mise_paths = function(tool_name, tool_install, mise_home)
    local pathlib = require("pathlib")
    local cache_key = string.format("%q/%q", tool_name, tool_install.version)
    ToolPathCache[cache_key] = Utils.tbl_deep_extend("force", ToolPathCache[cache_key] or {}, {
        install_dir = pathlib.Path({ mise_home, "installs", tool_name, tool_install.version }),
        download_dir = pathlib.Path({ mise_home, "downloads", tool_name, tool_install.version }),
        shims = tool_install.mise_install_path,
        executables = { tool_install.zephyr_install_path },
    })
    Utils.inf("ToolPathCache entry created", { cache_key = cache_key, entry = ToolPathCache[cache_key] })
end
---@param tool string
---@param version string
---@return MiseToolPaths? zephyr_sdk_home
local get_mise_paths = function(tool, version)
    local cache_key = string.format("%q/%q", tool, version)
    if ToolPathCache[cache_key] then
        return ToolPathCache[cache_key]
    else
        Utils.wrn("No entry in cache for tool " .. tool .. " with version " .. version)
    end
end
local update_mise_paths = function(tool, version, update_table)
    local cache_key = string.format("%s-%s", tool, version)
    ToolPathCache = Utils.tbl_deep_extend("keep", ToolPathCache[cache_key], update_table)
end

--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    -- ── Download minimal SDK ────────────────────────────────────────────
    -- ── Install toolchains and hosttools via setup.sh ───────────────────
    require("utils")
    local sh = require("shell_exec")
    local fs = require("file")
    local pathlib = require("pathlib")
    local semver = require("semver")
    local zephyr_sdk = require("zephyr_sdk")
    local zephyr_sdk_home = sh.get_zephyr_sdk_home()
    local zephyr_sdk_install_dir = fs.join_path(zephyr_sdk_home, "zephyr-sdk-" .. ctx.version)
    local env = require("env")
    local data_home = os.getenv("XDG_DATA_HOME")
    if not data_home then
        Utils.fatal("Could not get envs", { env = env })
    end
    local mise_home = fs.join_path(data_home, "mise")
    local backend_install_path = pathlib.dirname(ctx.install_path)
    local backend_name = string.gsub(pathlib.basename(backend_install_path), "-%w+$", "")
    Utils.inf("Backend name " .. backend_name .. " and install path " .. backend_install_path)
    local tool_installation_seq
    if ctx.tool == "minimal" then
        tool_installation_seq = {
            ["minimal"] = {
                version = ctx.version,
                zephyr_install_path = fs.join_path(zephyr_sdk_install_dir, "setup.sh"),
                mise_install_path = fs.join_path(ctx.install_path, "setup.sh"),
                executables = { "setup.sh" },
            },
        }
    elseif ctx.tool == "west" then
        tool_installation_seq = {
            ["west"] = {
                version = ctx.version,
                zephyr_install_path = fs.join_path(zephyr_sdk_install_dir, ctx.tool),
                mise_install_path = fs.join_path(ctx.install_path, ctx.tool),
            },
        }
    elseif string.find(ctx.tool, "%w+-%w+-%w+") then
        if not get_mise_paths("minimal", ctx.version) then
            Utils.wrn("Install the minimal SDK first!")
            tool_installation_seq = {
                ["minimal"] = {
                    version = ctx.version,
                    zephyr_install_path = fs.join_path(zephyr_sdk_install_dir, "setup.sh"),
                    mise_install_path = fs.join_path(ctx.install_path, "setup.sh"),
                    executables = { "setup.sh" },
                },
            }
        end
        if semver.compare(ctx.version, "1.0.0") >= 0 and ctx.tool ~= "host" then
            --- Deal with the toolchain after we are done
            local prefix = ctx.tool == "llvm" and "llvm" or "gnu"
            tool_installation_seq = Utils.tbl_deep_extend("force", tool_installation_seq, {
                [string.format("bin/%q/%q", prefix, ctx.tool)] = {
                    version = ctx.version,
                    zephyr_install_path = fs.join_path(zephyr_sdk_install_dir, prefix, ctx.tool),
                    mise_install_path = fs.join_path(ctx.install_path, ctx.tool),
                    executables = { fs.join_path(zephyr_sdk_install_dir, "setup.sh") },
                },
            })
        else
            tool_installation_seq = Utils.tbl_deep_extend("force", tool_installation_seq, {
                [string.format("bin/%s", ctx.tool)] = {
                    version = ctx.version,
                    zephyr_install_path = fs.join_path(zephyr_sdk_install_dir, ctx.tool),
                    mise_install_path = fs.join_path(ctx.install_path, ctx.tool),
                    executables = { fs.join_path(zephyr_sdk_install_dir, "setup.sh") },
                },
            })
        end
    else
        Utils.fatal("Not able to recognize this tool tool", { tool = ctx.tool })
    end

    Utils.inf("INSTALLATION SEQUENCE", { seq = tool_installation_seq })
    for name, tool_install in pairs(tool_installation_seq) do
        Utils.inf("INSTALLING TOOL", { tool = name, info = tool_install })
        if not get_mise_paths(name, tool_install.version) then
            create_mise_paths(name, tool_installation_seq[name], mise_home)
            if not zephyr_sdk._install_funcs[name] then
                for tool_pattern, install_fn in pairs(zephyr_sdk._install_funcs) do
                    if string.find(name, tool_pattern) then
                        install_fn(tool_install)
                        return {}
                    end
                end
                Utils.fatal("No install function for tool", { tool = tool_install })
            end
            zephyr_sdk._install_funcs[name](tool_install)
        end
    end
    return {}
end
