--- Creates a container from IMAGE:VERSION and exports the requested commands
--- into install_path/bin.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backendinstall
--- @param ctx BackendInstallCtx
--- @return table
function PLUGIN:BackendInstall(ctx)
    local distrobox = require("distrobox")
    local file = require("file")
    local runner = require("runner")

    local tool = distrobox.parse_tool(ctx.tool)
    distrobox.validate_tag(ctx.version)
    if RUNTIME.osType ~= "linux" then
        error("the distrobox plugin only supports Linux")
    end
    local options = ctx.options or {}
    local exe = runner.executable(options)
    if not runner.available(exe) then
        error("the distrobox plugin needs `" .. exe .. "` on PATH; install it from https://distrobox.it")
    end
    local packages = options.packages
    if packages ~= nil and packages:match("^%s*$") then
        packages = nil
    end

    local image = tool.image .. ":" .. ctx.version
    local name = distrobox.container_name(tool, ctx.version, packages)

    -- A reinstall (or a previous failed attempt) may have left the container
    -- behind; recreate it so a moved tag is pulled again.
    if runner.container_exists(exe, name) then
        runner.remove_container(exe, name)
    end
    print("creating container " .. name .. " from " .. image)
    local create = { "create", "--yes", "--name", name, "--image", image }
    if packages then
        table.insert(create, "--additional-packages")
        table.insert(create, packages)
    end
    runner.run(exe, create)

    local bin_dir = file.join_path(ctx.install_path, "bin")
    local ok, err = pcall(runner.export_bins, exe, name, tool.bins, bin_dir)
    if not ok then
        -- mise removes the half-written install dir; take the container with
        -- it so a failed install leaves nothing behind.
        pcall(runner.remove_container, exe, name)
        error(err)
    end

    local marker = assert(io.open(file.join_path(ctx.install_path, distrobox.CONTAINER_MARKER), "w"))
    marker:write(name)
    marker:close()
    return {}
end
