-- Unit tests for lib/: run with `mise run test:unit` (plain Lua, no mise needed).
package.path = "./lib/?.lua;" .. package.path

local distrobox = require("distrobox")
local registry = require("registry")

local failures = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("ok   " .. name)
    else
        failures = failures + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end

local function eq(actual, expected)
    if type(expected) == "table" then
        assert(type(actual) == "table", "expected a table, got " .. tostring(actual))
        assert(#actual == #expected, string.format("expected %d items, got %d", #expected, #actual))
        for i = 1, #expected do
            eq(actual[i], expected[i])
        end
        for k, v in pairs(expected) do
            if type(k) ~= "number" then
                eq(actual[k], v)
            end
        end
    else
        assert(actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
    end
end

local function fails(fn, ...)
    local ok = pcall(fn, ...)
    assert(not ok, "expected an error for " .. table.concat({ ... }, ","))
end

check("parses image and bins", function()
    eq(
        distrobox.parse_tool("fedora/fedora-toolbox:htop,jq"),
        { image = "fedora/fedora-toolbox", bins = { "htop", "jq" } }
    )
    eq(
        distrobox.parse_tool("localhost:5000/tools/box:/opt/bin/x"),
        { image = "localhost:5000/tools/box", bins = { "/opt/bin/x" } }
    )
    eq(distrobox.parse_tool("alpine: jq , curl "), { image = "alpine", bins = { "jq", "curl" } })
end)

check("rejects bad tool names", function()
    for _, bad in ipairs({
        "alpine",
        "alpine:",
        ":jq",
        "alpine:a/b",
        "alpine:../x",
        "alpine:-x",
        "-alpine:jq",
        "a lpine:jq",
        "alpine:/usr/../bin/x",
        "alpine:$(id)",
    }) do
        fails(distrobox.parse_tool, bad)
    end
end)

check("validates tags", function()
    for _, good in ipairs({ "latest", "41", "3.20.1", "bookworm-slim", "v1_2" }) do
        assert(distrobox.is_valid_tag(good), good)
    end
    for _, bad in ipairs({ "", "-x", ".x", "a/b", "a:b", string.rep("a", 129) }) do
        assert(not distrobox.is_valid_tag(bad), bad)
    end
end)

check("filters tags and puts latest last", function()
    local sig = "sha256-" .. string.rep("a", 64) .. ".sig"
    eq(
        distrobox.versions_from_tags({ "3.19", "edge", "latest", sig, "3.20", "bad/tag" }),
        { "3.19", "edge", "3.20", "latest" }
    )
    eq(distrobox.versions_from_tags({ "1", "2" }), { "1", "2" })
    assert(distrobox.is_artifact_tag("sha256-" .. string.rep("0", 64)))
    assert(not distrobox.is_artifact_tag("sha256-short.sig"))
    assert(not distrobox.is_artifact_tag("sha256-" .. string.rep("0", 64) .. "x"))
end)

check("container names are stable and distinct", function()
    local jq = distrobox.parse_tool("docker.io/library/alpine:jq")
    local curl = distrobox.parse_tool("docker.io/library/alpine:curl")
    local name = distrobox.container_name(jq, "3.20", nil)
    assert(name:match("^mise%-alpine%-3%-20%-%x%x%x%x%x%x%x%x$"), name)
    assert(distrobox.is_valid_container_name(name))
    eq(name, distrobox.container_name(jq, "3.20", nil))
    assert(name ~= distrobox.container_name(curl, "3.20", nil))
    assert(name ~= distrobox.container_name(jq, "3.20", "bash"))
    assert(not distrobox.is_valid_container_name("fedora"))
    assert(not distrobox.is_valid_container_name("mise-a;rm"))
end)

check("reads names from distrobox list", function()
    local output = table.concat({
        "ID           | NAME                 | STATUS        | IMAGE",
        "0123abcd     | mise-alpine-x        | Up 2 minutes  | alpine:3.20",
        "4567ef01     | fedora               | Exited        | fedora:41",
    }, "\n")
    eq(distrobox.listed_names(output), { "mise-alpine-x", "fedora" })
end)

check("finds the path in command -v output", function()
    eq(distrobox.last_path("Starting container...\n/usr/bin/jq\n"), "/usr/bin/jq")
    eq(distrobox.last_path("nothing here"), nil)
end)

check("quotes for the shell", function()
    eq(distrobox.shell_quote("it's"), "'it'\\''s'")
end)

check("parses image references", function()
    local function ref(image)
        local registry_host, repository = registry.parse_image(image)
        return registry_host .. " " .. repository
    end
    eq(ref("alpine"), "docker.io library/alpine")
    eq(ref("fedora/fedora-toolbox"), "docker.io fedora/fedora-toolbox")
    eq(ref("registry.fedoraproject.org/fedora-toolbox"), "registry.fedoraproject.org fedora-toolbox")
    eq(ref("localhost:5000/tools/box"), "localhost:5000 tools/box")
    eq(registry.base_url("docker.io"), "https://registry-1.docker.io")
    eq(registry.base_url("localhost:5000"), "http://localhost:5000")
    eq(registry.base_url("ghcr.io"), "https://ghcr.io")
end)

check("parses auth challenges and links", function()
    local c = registry.parse_bearer_challenge(
        'Bearer realm="https://auth.docker.io/token",service="registry.docker.io",scope="repository:a:pull,push"'
    )
    assert(c, "expected a bearer challenge")
    eq(c.realm, "https://auth.docker.io/token")
    eq(c.service, "registry.docker.io")
    eq(registry.parse_bearer_challenge('Basic realm="x"'), nil)
    eq(
        registry.next_link('</v2/library/alpine/tags/list?last=3.20&n=1000>; rel="next"'),
        "/v2/library/alpine/tags/list?last=3.20&n=1000"
    )
    eq(registry.next_link('<https://a/prev>; rel="prev", <https://a/next>; rel="next"'), "https://a/next")
    eq(registry.next_link(nil), nil)
end)

if failures > 0 then
    print(failures .. " test(s) failed")
    os.exit(1)
end
print("all tests passed")
