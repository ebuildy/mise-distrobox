#!/usr/bin/env bash
# End-to-end test with real podman, distrobox and mise, inside the container
# that test/e2e/Containerfile builds. Run it with `mise run test:e2e`.
set -euo pipefail

tool='distrobox:docker.io/library/alpine:jq,/bin/busybox'

mise --version
mise plugins link --force distrobox /plugin
mkdir -p "$HOME/work" && cd "$HOME/work"

echo "=== ls-remote: latest is listed last"
[[ "$(mise ls-remote "$tool" | tail -1)" == "latest" ]]

echo "=== install: packages option, a bin by name and a bin by path"
cat >mise.toml <<TOML
[tools."$tool"]
version = "3.20"
packages = "jq"
TOML
mise trust -q
mise install
ls "$(mise where "$tool")/bin"

echo "=== exported commands run in the container"
[[ "$(echo '{"a":1}' | mise x -- jq .a)" == "1" ]]
mise x -- busybox cat /etc/alpine-release | grep -q '^3\.20'
distrobox list --no-color | grep -q mise-alpine-3-20-

echo "=== a missing bin fails with a clear error"
if mise install 'distrobox:docker.io/library/alpine:nope@3.20' >fail.log 2>&1; then
    echo "expected the install to fail"
    exit 1
fi
grep -q '`nope` was not found in the distrobox container' fail.log

echo "=== uninstall removes the container"
# Nested rootless podman shares the outer container's PID namespace and cannot
# stop distrobox containers ("given PID did not die"); a real host can. Accept
# only that failure, which still shows the plugin asked distrobox to remove it.
if ! mise uninstall "$tool@3.20" >uninstall.log 2>&1; then
    grep -q 'could not be stopped' uninstall.log || {
        cat uninstall.log
        exit 1
    }
    echo "(container removal is not possible in nested podman)"
fi
echo "=== all e2e checks passed"
