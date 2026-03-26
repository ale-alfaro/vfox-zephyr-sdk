--- Returns download information for a specific version
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook
--- @param ctx {version: string, runtimeVersion: string} Context
--- @return PreInstallResult Version and download information
function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    -- ctx.runtimeVersion contains the full version string if needed
    local lib = require("zephyr_sdk")
    local url = lib.get_download_url(ctx)
    return {
        version = version,
        url = url,
        -- sha256 = sha256, -- Optional but recommended for security
        note = "Downloading zephyr-sdk " .. version,
        -- addition = { -- Optional: download additional components
        --     {
        --         name = "component",
        --         url = "https://example.com/component.tar.gz"
        --     }
        -- }
    }
end
