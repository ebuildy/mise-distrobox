--- Puts the exported wrappers on PATH.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendexecenv
--- @param ctx BackendExecEnvCtx
--- @return {env_vars: table[]}
function PLUGIN:BackendExecEnv(ctx)
    local file = require("file")
    return {
        env_vars = {
            { key = "PATH", value = file.join_path(ctx.install_path, "bin") },
        },
    }
end
