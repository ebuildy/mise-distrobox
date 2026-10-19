# mise-distrobox

A [mise](https://mise.jdx.dev) backend plugin that installs commands from any
OCI container image. It creates a [distrobox](https://distrobox.it) container
from the image and exports the commands you list with `distrobox-export`, so
they run like any other mise tool:

```sh
mise plugins install distrobox https://github.com/ebuildy/mise-distrobox
mise use distrobox:registry.fedoraproject.org/fedora-toolbox:htop,jq@latest
htop
```

Each exported command is a small wrapper that runs the real command inside the
container, with your home and working directories shared. Use it for tools that
are packaged for another Linux distribution but not for yours, or that need a
full userland that a single binary download cannot provide.

## Requirements

- Linux
- `distrobox`, and podman, docker or lilipod for distrobox to run containers

## Usage

The tool name is the image without a tag, a `:`, and a comma-separated list of
commands. The version is the image tag:

```text
distrobox:IMAGE:bin1,bin2@TAG
```

- **Image:** an image name without a registry uses Docker Hub, as with
  `docker pull` (`distrobox:alpine:jq` is `docker.io/library/alpine`). The last
  `:` separates the commands, so a registry port stays part of the image
  (`distrobox:localhost:5000/tools/box:x`).
- **Commands:** a name, which the plugin looks up on the container's `PATH`, or
  an absolute path inside the container
  (`distrobox:ghcr.io/acme/tools:/opt/acme/bin/acme@1.4`).
- **Versions:** `mise ls-remote distrobox:alpine:jq` lists the image's tags from
  its registry, without signature and attestation tags (`sha256-…`). Registries
  list tags alphabetically, so the plugin puts `latest` last, and `@latest`
  installs the image's `latest` tag when it has one. For images without a
  `latest` tag, use an explicit tag.

A tag such as `latest` can move. `mise install --force` recreates the container
and pulls the image again.

The first run of an exported command can be slow, because distrobox starts the
container.

### Tool options

```toml
[tools."distrobox:docker.io/library/debian:rg"]
version = "bookworm"
packages = "ripgrep"
```

| Option      | Effect                                                                                         |
| ----------- | ---------------------------------------------------------------------------------------------- |
| `packages`  | Space-separated packages distrobox installs while creating the container, for missing commands |
| `distrobox` | The distrobox executable to run, if it is not `distrobox` on `PATH`                            |

## How it works

`mise install` runs, for each tool version:

1. `distrobox create --yes --name mise-<image>-<tag>-<hash> --image IMAGE:TAG`
   (plus `--additional-packages`). Each tool version gets its own container; the
   hash covers the image, tag, commands and packages, so two tools that use the
   same image never share a container.
2. For each command, `command -v` inside the container to find its path, then
   `distrobox-export --bin PATH --export-path <install dir>/bin`.

If an export fails, the plugin removes the container again.

`mise uninstall` removes the wrappers and the container. The image stays in your
container engine's storage; remove it with `podman image rm` or `docker image rm`.

## Limitations

- Tags are listed anonymously, so private images, which need registry
  credentials, are not supported yet.
- If you set the `distrobox` option and later remove the tool from your config,
  `mise prune` cannot see that option and looks for `distrobox` on `PATH` to
  remove the container.

## Development

```sh
mise run test:unit   # helpers in lib/, plain Lua
mise run test        # links the plugin; installs only on Linux with distrobox
mise run test:e2e    # real install in a podman container (needs podman)
mise run lint
```
