--- Downloads and installs the Zephyr SDK for a specific version.
--- Handles the full lifecycle: download minimal SDK, extract, normalize,
--- and install toolchains via setup.sh.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
--- Fetch SHA256 checksum for the file
-- local function fetch_checksum(filename)
--     -- Google provides checksums at a .sha256 file
--     local checksum_url = BASE_URL .. "/" .. filename .. ".sha256"
--
--     local resp, err = http.get({
--         url = checksum_url,
--     })
--
--     if err ~= nil or resp.status_code ~= 200 then
--         -- Checksum file might not exist for all versions
--         return nil
--     end
--
--     -- The file contains just the hash
--     local hash = string.match(resp.body, "^(%x+)")
--     return hash
-- end
--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    -- ── Download minimal SDK ────────────────────────────────────────────
    -- ── Install toolchains and hosttools via setup.sh ───────────────────
    require("utils")

    local strings = require("strings")
    local zephyr_sdk = require("zephyr_sdk")
    local install_fn = zephyr_sdk.available_tool_installations[ctx.tool]
    if not install_fn then
        Utils.fatal(
            "No known tool found with name given",
            { ctx = ctx, avaialable_tools = zephyr_sdk.available_tool_installations }
        )
    end
    install_fn(ctx)
    return {}
end
