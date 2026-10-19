--- Runs distrobox commands for the install and uninstall hooks.
local M = {}

local distrobox = require("distrobox")

--- The distrobox executable from the `distrobox` tool option, or `distrobox`.
function M.executable(options)
    local exe = options and options.distrobox
    if exe == nil or exe == "" then
        return "distrobox"
    end
    return exe
end

--- Runs `distrobox` with `args`, each quoted for the shell.
function M.run(exe, args)
    local cmd = require("cmd")
    local parts = { '"$MISE_DISTROBOX"' }
    for _, arg in ipairs(args) do
        table.insert(parts, distrobox.shell_quote(arg))
    end
    return cmd.exec(table.concat(parts, " "), { env = { MISE_DISTROBOX = exe } })
end

function M.available(exe)
    local cmd = require("cmd")
    local ok = pcall(cmd.exec, 'command -v "$MISE_DISTROBOX"', { env = { MISE_DISTROBOX = exe } })
    return ok
end

function M.container_exists(exe, name)
    for _, listed in ipairs(distrobox.listed_names(M.run(exe, { "list", "--no-color" }))) do
        if listed == name then
            return true
        end
    end
    return false
end

function M.remove_container(exe, name)
    M.run(exe, { "rm", "--force", name })
end

--- The absolute path of `bin` inside the container, which distrobox-export
--- requires. `command -v` always exits 0 here, so an error means distrobox
--- itself failed, and it is raised unchanged.
function M.resolve_bin(exe, name, bin)
    local output =
        M.run(exe, { "enter", "--name", name, "--no-tty", "--", "sh", "-c", 'command -v -- "$1" || true', "sh", bin })
    local path = distrobox.last_path(output)
    if not path then
        error(
            "`"
                .. bin
                .. "` was not found in the distrobox container "
                .. name
                .. "; install it with the `packages` tool option"
        )
    end
    return path
end

function M.export_bins(exe, name, bins, bin_dir)
    local cmd = require("cmd")
    local file = require("file")
    cmd.exec('mkdir -p "$DIR"', { env = { DIR = bin_dir } })
    for _, bin in ipairs(bins) do
        local path = M.resolve_bin(exe, name, bin)
        print("exporting " .. path)
        M.run(exe, {
            "enter",
            "--name",
            name,
            "--no-tty",
            "--",
            "distrobox-export",
            "--bin",
            path,
            "--export-path",
            bin_dir,
        })
        local exported = file.join_path(bin_dir, distrobox.file_name(path))
        if not file.exists(exported) then
            error("distrobox-export did not write " .. exported)
        end
    end
end

return M
