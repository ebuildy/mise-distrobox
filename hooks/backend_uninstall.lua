--- Removes the container the install created. The wrappers live in
--- install_path, which mise deletes afterwards.
--- Documentation: https://mise.jdx.dev/backend-plugin-development.html#backenduninstall
function PLUGIN:BackendUninstall(ctx)
    local distrobox = require("distrobox")
    local file = require("file")
    local log = require("log")
    local runner = require("runner")

    local marker = file.join_path(ctx.install_path, distrobox.CONTAINER_MARKER)
    if not file.exists(marker) then
        return
    end
    local name = (file.read(marker):gsub("%s+$", ""))
    if not distrobox.is_valid_container_name(name) then
        log.warn("not removing distrobox container with unexpected name", name)
        return
    end
    local exe = runner.executable(ctx.options)
    if not runner.available(exe) then
        log.warn(exe, "not found; leaving distrobox container", name, "in place")
        return
    end
    if runner.container_exists(exe, name) then
        runner.remove_container(exe, name)
    end
end
