# devcontainer-features

Custom devcontainer features for AI-assisted coding workflows.

Designed so coding agents (Claude Code, Cursor Agent, Codex) can operate inside devcontainers without hitting interactive prompts, missing tools, or auth friction.

## Features

| Feature | Description | Docs |
|---|---|---|
| [`agent-ready`](src/agent-ready) | Opinionated base: zsh + mise + starship, Claude Code pre-accepts, SSH commit signing, host-token status report | [README](src/agent-ready/README.md) |

## Using a feature

Reference it in your `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/moisesmorillo/devcontainer-features/agent-ready:1": {}
  }
}
```

Version pinning follows semver: `:1` tracks the 1.x line, `:1.0` tracks 1.0.x, `:1.0.0` is exact.

## Companion script: `init-secrets.sh`

Features run **inside** the container, but some setup needs to run on the **host** (reading macOS Keychain / gh CLI config to inherit auth tokens). That's what [`scripts/init-secrets.sh`](scripts/init-secrets.sh) is for. Consume it with a three-line shim in your repo:

```bash
# .devcontainer/init-secrets.sh
#!/usr/bin/env bash
exec bash -c "$(curl -fsSL https://raw.githubusercontent.com/moisesmorillo/devcontainer-features/v1.0.0/scripts/init-secrets.sh)"
```

And wire it in `devcontainer.json`:

```json
{
  "initializeCommand": [".devcontainer/init-secrets.sh"]
}
```

The script extracts `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` from host storage (macOS Keychain on Darwin, `~/.config/gh/hosts.yml` + `~/.claude/.credentials.json` on Linux) and writes them to `.devcontainer/.env.devcontainer`, which your `docker-compose.yml` should consume via:

```yaml
services:
  app:
    env_file:
      - path: .env.devcontainer
        required: false
```

Remember to gitignore `.devcontainer/.env.devcontainer`.

## Releasing

Tag a version and GitHub Actions publishes all features in `src/` to `ghcr.io`:

```bash
git tag v1.1.0
git push --tags
```

The workflow auto-generates the tag ladder (`:1`, `:1.1`, `:1.1.0`, `:latest`).

## License

MIT. See [LICENSE](LICENSE).
