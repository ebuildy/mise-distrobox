--- Lists the image's tags from its registry.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendlistversions
--- @param ctx BackendListVersionsCtx
--- @return {versions: string[]}
function PLUGIN:BackendListVersions(ctx)
    local distrobox = require("distrobox")
    local registry = require("registry")

    local tool = distrobox.parse_tool(ctx.tool)
    local versions = distrobox.versions_from_tags(registry.list_tags(tool.image))
    if #versions == 0 then
        error("no tags found for " .. tool.image)
    end
    return { versions = versions }
end
