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
    local cache_key = string.format("%q/%q", tool_name, tool_install.version)
    ToolPathCache[cache_key] = Utils.tbl_deep_extend("force", ToolPathCache[cache_key] or {}, {
        install_dir = Utils.fs.Path({ mise_home, "installs", tool_name, tool_install.version }),
        download_dir = Utils.fs.Path({ mise_home, "downloads", tool_name, tool_install.version }),
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
---
---@alias ZephyrInstallationSeq table<string,ZephyrSdkTool>

--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    -- ── Download minimal SDK ────────────────────────────────────────────
    -- ── Install toolchains and hosttools via setup.sh ───────────────────
    require("utils")
    local semver = require("semver")
    local zephyr_sdk = require("zephyr_sdk")
    local zephyr_sdk_home = zephyr_sdk.get_zephyr_sdk_home()
    local zephyr_sdk_install_dir = Utils.fs.join_path(zephyr_sdk_home, "zephyr-sdk-" .. ctx.version)
    local env = require("env")
    local data_home = os.getenv("XDG_DATA_HOME")
    if not data_home then
        Utils.fatal("Could not get envs", { env = env })
    end
    local mise_home = Utils.fs.join_path(data_home, "mise")
    local backend_install_path = Utils.fs.dirname(ctx.install_path)
    local backend_name = string.gsub(Utils.fs.basename(backend_install_path), "-%w+$", "")
    Utils.inf("Backend name " .. backend_name .. " and install path " .. backend_install_path)
    local tool_installation_seq = {} ---@type ZephyrInstallationSeq
    if ctx.tool == "west" then
        tool_installation_seq = {
            ["west"] = {
                version = ctx.version,
                zephyr_install_path = Utils.fs.join_path(zephyr_sdk_install_dir, ctx.tool),
                mise_install_path = Utils.fs.join_path(ctx.install_path, ctx.tool),
            },
        }
    elseif string.find(ctx.tool, "llvm") or string.find(ctx.tool, "host") or string.find(ctx.tool, "%w+-%w+-%w+") then
        local zephyr_sdk_setup_script = Utils.fs.join_path(zephyr_sdk_install_dir, "setup.sh")
        if not Utils.fs.exists(zephyr_sdk_setup_script) then
            Utils.wrn("Install the minimal SDK first!")
            zephyr_sdk.minimal_install(ctx.version, Utils.fs.dirname(zephyr_sdk_setup_script))
        end
        local zephyr_install_path = Utils.fs.join_path(zephyr_sdk_install_dir, ctx.tool)
        if semver.compare(ctx.version, "1.0.0") >= 0 and ctx.tool ~= "host" then
            --- Deal with the toolchain after we are done
            local prefix = ctx.tool == "llvm" and "llvm" or "gnu"
            zephyr_install_path = Utils.fs.join_path(zephyr_sdk_install_dir, prefix, ctx.tool)
        end
        tool_installation_seq[ctx.tool] = {
            version = ctx.version,
            zephyr_install_path = zephyr_install_path,
            mise_install_path = Utils.fs.join_path(ctx.install_path, ctx.tool),
            extra = { setup_sh = zephyr_sdk_setup_script },
        }
    else
        Utils.fatal("Not able to recognize this tool tool", { tool = ctx.tool })
    end

    Utils.inf("INSTALLATION SEQUENCE", { seq = tool_installation_seq })

    for name, tool in pairs(tool_installation_seq) do
        Utils.inf("Looking for tool in cache", { tool = name })
        if not get_mise_paths(name, tool.version) then
            create_mise_paths(name, tool, mise_home)
            if not zephyr_sdk._install_funcs[name] then
                for tool_pattern, install_fn in pairs(zephyr_sdk._install_funcs) do
                    local matched = string.match(name, tool_pattern)
                    if matched then
                        Utils.inf("Matched tool: ", { matched = matched, tool = tool })
                        install_fn(matched, tool)
                        return {}
                    end
                end
                Utils.fatal("No install function for tool", { tool = tool })
            end
            zephyr_sdk._install_funcs[name](name, tool)
        end
    end
    return {}
end
