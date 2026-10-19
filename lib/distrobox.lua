--- Pure helpers for the distrobox backend. Nothing here calls mise modules, so
--- test/distrobox_test.lua can load this file with a plain Lua interpreter.
local M = {}

local USAGE = "expected distrobox:IMAGE:bin1,bin2 (e.g. distrobox:registry.fedoraproject.org/fedora-toolbox:htop,jq)"

--- Records which container an install exported its commands from, so
--- uninstall removes that container even if the tool options changed since.
M.CONTAINER_MARKER = ".mise-distrobox-container"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- A bin is a command name looked up on the container's PATH, or an absolute
--- path inside the container.
function M.validate_bin(bin)
    local absolute = bin:sub(1, 1) == "/"
    local name = absolute and bin:sub(2) or bin
    local valid = name ~= ""
        and name:sub(1, 1) ~= "-"
        and (absolute or not name:find("/", 1, true))
        and not name:find("[^%w_%.%-%+/]")
    if valid then
        for part in (name .. "/"):gmatch("([^/]*)/") do
            if part == "" or part == "." or part == ".." then
                valid = false
            end
        end
    end
    if not valid then
        error(string.format("distrobox bin must be a command name or an absolute path, got %q", bin))
    end
end

--- Splits `IMAGE:bin1,bin2`. The last `:` separates the bins, so a registry
--- port stays in the image.
function M.parse_tool(tool)
    local image, bins = tool:match("^(.*):([^:]*)$")
    if not image then
        error(USAGE .. ", got distrobox:" .. tool)
    end
    local valid_image = image ~= ""
        and not image:find("^[-/]")
        and not image:find("..", 1, true)
        and not image:find("//", 1, true)
        and not image:find("[^%w%._%-/:]")
    if not valid_image then
        error(USAGE .. ", got distrobox:" .. tool)
    end
    local list = {}
    for bin in bins:gmatch("[^,]+") do
        bin = trim(bin)
        if bin ~= "" then
            M.validate_bin(bin)
            table.insert(list, bin)
        end
    end
    if #list == 0 then
        error(USAGE .. ", got distrobox:" .. tool)
    end
    return { image = image, bins = list }
end

--- OCI tag grammar: `[A-Za-z0-9_][A-Za-z0-9._-]{0,127}`.
function M.is_valid_tag(tag)
    return type(tag) == "string" and #tag > 0 and #tag <= 128 and not tag:find("^[%.%-]") and not tag:find("[^%w_%.%-]")
end

function M.validate_tag(tag)
    if not M.is_valid_tag(tag) then
        error(string.format("%q is not a valid OCI image tag", tostring(tag)))
    end
end

--- Tags such as `sha256-<digest>` and `sha256-<digest>.sig` that registries
--- (the OCI referrers fallback) and cosign push next to an image to hold its
--- signatures, attestations and SBOMs.
function M.is_artifact_tag(tag)
    local digest, rest = tag:match("^sha256%-(%x+)(.*)$")
    return digest ~= nil and #digest == 64 and (rest == "" or rest:sub(1, 1) == ".")
end

--- Keeps installable tags in registry order, and moves `latest` to the end:
--- mise resolves `@latest` to the last version, and registries list tags
--- alphabetically, so the container convention wins when the image has one.
function M.versions_from_tags(tags)
    local versions = {}
    local has_latest = false
    for _, tag in ipairs(tags) do
        if tag == "latest" then
            has_latest = true
        elseif M.is_valid_tag(tag) and not M.is_artifact_tag(tag) then
            table.insert(versions, tag)
        end
    end
    if has_latest then
        table.insert(versions, "latest")
    end
    return versions
end

--- 32-bit FNV-1a, as 8 hex digits. Lua 5.1 has no bit operations, so the XOR
--- is done one bit at a time.
local function fnv1a(s)
    local function xor(a, b)
        local result, bit = 0, 1
        while a > 0 or b > 0 do
            if a % 2 ~= b % 2 then
                result = result + bit
            end
            a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
        end
        return result
    end
    local hash = 2166136261
    for i = 1, #s do
        hash = xor(hash, s:byte(i))
        -- 16777619 = 2^24 + 403; split so every product stays exact in a double
        hash = (hash * 403 + (hash % 256) * 16777216) % 4294967296
    end
    return string.format("%08x", hash)
end

local function slug(s)
    return (s:gsub("[^%w]", "-")):sub(1, 32)
end

--- One container per tool and tag. The hash keeps two tools that export
--- different bins from the same image from sharing (and removing) one
--- container.
function M.container_name(tool, tag, packages)
    local readable = tool.image:match("([^/]+)$") or tool.image
    local key = table.concat({ tool.image, tag, table.concat(tool.bins, ","), packages or "" }, ":")
    return "mise-" .. slug(readable) .. "-" .. slug(tag) .. "-" .. fnv1a(key)
end

function M.is_valid_container_name(name)
    return name:sub(1, 5) == "mise-" and not name:find("[^%w_%.%-]")
end

--- Names from the `ID | NAME | STATUS | IMAGE` table `distrobox list` prints.
function M.listed_names(output)
    local names = {}
    local first = true
    for line in output:gmatch("[^\r\n]+") do
        if first then
            first = false
        else
            local name = line:match("^[^|]*|([^|]*)|")
            if name then
                table.insert(names, trim(name))
            end
        end
    end
    return names
end

--- The last absolute path in the output of `command -v`, skipping any
--- messages distrobox prints while it starts the container.
function M.last_path(output)
    local path
    for line in output:gmatch("[^\r\n]+") do
        line = trim(line)
        if line:sub(1, 1) == "/" then
            path = line
        end
    end
    return path
end

function M.file_name(path)
    return path:match("([^/]+)$") or path
end

--- Single-quotes `s` for a POSIX shell.
function M.shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

return M
