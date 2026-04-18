--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    require("zephyr_sdk")
    local tool = ZephyrSdk[ctx.tool]
    if not tool then
        Utils.err("Could not find tool : ", { tool = ctx.tool, version = ctx.version, install = ctx.install_path })
        return {}
    end
    Utils.dbg("Preparing to install tool: ", { tool = tool, ctx = ctx })
    tool.install(ctx)
    return {}
end
