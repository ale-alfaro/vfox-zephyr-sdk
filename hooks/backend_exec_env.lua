--- Configures environment variables for the Zephyr SDK
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv

--- @param ctx BackendExecEnvCtx
--- @return BackendExecEnvResult
function PLUGIN:BackendExecEnv(ctx)
    require("zephyr_sdk")
    Utils.inf("Preparing envs for tool: ", { ctx = ctx })
    local tool = ZephyrSdk[ctx.tool]
    if not tool then
        return {}
    end
    local envs = tool.envs(ctx)
    Utils.inf("Envs: ", { envs = envs })
    return { env_vars = envs }
end
