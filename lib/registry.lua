--- Lists an image's tags with the OCI distribution API.
local M = {}

--- Splits an image name without a tag into registry host and repository, with
--- docker's defaults: `alpine` is `docker.io/library/alpine`.
function M.parse_image(image)
    local head, rest = image:match("^([^/]+)/(.+)$")
    local registry, repository
    if head and (head:find("[%.:]") or head == "localhost") then
        registry, repository = head, rest
    else
        registry, repository = "docker.io", image
    end
    if registry == "docker.io" and not repository:find("/", 1, true) then
        repository = "library/" .. repository
    end
    return registry, repository
end

--- Loopback registries serve plain HTTP, as docker assumes; everything else
--- uses HTTPS. Docker Hub's API is served from registry-1.docker.io.
function M.base_url(registry)
    if registry == "docker.io" then
        return "https://registry-1.docker.io"
    end
    local host = registry:match("^%[([^%]]+)%]") or registry:match("^([^:]+)") or registry
    if host == "localhost" or host == "::1" or host:match("^127%.") then
        return "http://" .. registry
    end
    return "https://" .. registry
end

--- `key="value"` parameters of a `WWW-Authenticate: Bearer ...` challenge.
function M.parse_bearer_challenge(header)
    if not header or not header:lower():match("^%s*bearer%s") then
        return nil
    end
    local params = {}
    for key, value in header:gmatch('(%w+)="([^"]*)"') do
        params[key:lower()] = value
    end
    if not params.realm then
        return nil
    end
    return params
end

--- The target of the `rel="next"` entry of an RFC 8288 `Link` header.
function M.next_link(header)
    if not header then
        return nil
    end
    for target, params in header:gmatch("<([^>]*)>([^,]*)") do
        if params:lower():find('rel="?next"?') then
            return target
        end
    end
    return nil
end

local function url_encode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

--- Requests an anonymous pull token for `repository` from the challenge's realm.
local function fetch_token(challenge, repository)
    local http = require("http")
    local json = require("json")
    local url = challenge.realm
        .. (challenge.realm:find("?", 1, true) and "&" or "?")
        .. "scope="
        .. url_encode("repository:" .. repository .. ":pull")
    if challenge.service then
        url = url .. "&service=" .. url_encode(challenge.service)
    end
    local resp = http.get({ url = url })
    if resp.status_code ~= 200 then
        return nil
    end
    local body = json.decode(resp.body)
    return body.token or body.access_token
end

function M.list_tags(image)
    local http = require("http")
    local json = require("json")
    local registry, repository = M.parse_image(image)
    local base = M.base_url(registry)
    local url = base .. "/v2/" .. repository .. "/tags/list?n=1000"
    local headers = {}
    local tags = {}
    -- A misbehaving registry could hand back a `next` link forever.
    for _ = 1, 1000 do
        local resp = http.get({ url = url, headers = headers })
        if resp.status_code == 401 and not headers["Authorization"] then
            local challenge = M.parse_bearer_challenge(resp.headers["www-authenticate"])
            local token = challenge and fetch_token(challenge, repository)
            if token then
                headers["Authorization"] = "Bearer " .. token
                resp = http.get({ url = url, headers = headers })
            end
        end
        if resp.status_code == 401 or resp.status_code == 403 or resp.status_code == 404 then
            -- Docker Hub answers 401 for a repository that does not exist.
            error(
                registry
                    .. "/"
                    .. repository
                    .. " was not found, or its registry needs credentials,"
                    .. " which this plugin does not support yet"
            )
        elseif resp.status_code ~= 200 then
            error("listing tags at " .. url .. " failed: HTTP " .. resp.status_code)
        end
        local page = json.decode(resp.body)
        if type(page.tags) == "table" then
            for _, tag in ipairs(page.tags) do
                table.insert(tags, tag)
            end
        end
        local next_url = M.next_link(resp.headers["link"])
        if not next_url then
            return tags
        elseif next_url:match("^https?://") then
            url = next_url
        else
            url = base .. next_url
        end
    end
    error("too many pages listing tags of " .. image)
end

return M
