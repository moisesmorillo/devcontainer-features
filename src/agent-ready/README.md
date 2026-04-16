# `agent-ready`

Opinionated devcontainer setup for AI-assisted coding workflows.

## What it does

**Shell + prompt**
- Installs zsh (via the `common-utils` dependency) and makes it the login shell
- Installs [mise](https://mise.jdx.dev/) for the remote user
- Pins and installs [Starship](https://starship.rs/) via mise
- Wires both `.bashrc` and `.zshrc` with activations so interactive shells **and** non-interactive subprocesses resolve tools

**Claude Code ready**
Pre-accepts three Claude Code dialogs so agents run without interactive prompts:
- `hasCompletedOnboarding` — workaround for `anthropics/claude-code#46259` (forces interactive login even with `CLAUDE_CODE_OAUTH_TOKEN` set)
- `bypassPermissionsModeAccepted` — skips the "Bypass Permissions mode" warning triggered by `claude --dangerously-skip-permissions`
- `projects[<cwd>].hasTrustDialogAccepted` — skips the "trust this folder?" prompt
- Aliases `claude` to `claude --dangerously-skip-permissions`

**Git commit signing**
Auto-detects the first `~/.ssh/id_*.pub` (if `~/.ssh` is bind-mounted from the host) and configures:
- `gpg.format = ssh`, `user.signingkey`, `commit.gpgsign = true`
- `gpg.ssh.allowedSignersFile` at `~/.config/git/allowed_signers` (since `~/.ssh` is usually mounted read-only)

**Auth status reporting**
Prints a clear "did GH_TOKEN / CLAUDE_CODE_OAUTH_TOKEN land?" banner at the end of post-create, so you know whether host-token inheritance worked.

## Usage

```json
{
  "features": {
    "ghcr.io/moisesmorillo/devcontainer-features/agent-ready:1": {}
  }
}
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `starshipVersion` | string | `"1.24.2"` | Starship version pinned via mise (semver without the `v` prefix) |
| `installStarship` | boolean | `true` | Install Starship and wire it into `.zshrc`. Disable if you prefer a different prompt |
| `claudeBypassPermissions` | boolean | `true` | Pre-accept `--dangerously-skip-permissions`. Disable for environments with real host access |

Example with options:

```json
{
  "features": {
    "ghcr.io/moisesmorillo/devcontainer-features/agent-ready:1": {
      "starshipVersion": "1.25.0",
      "installStarship": true,
      "claudeBypassPermissions": true
    }
  }
}
```

## Dependencies

This feature auto-installs [`common-utils`](https://github.com/devcontainers/features/tree/main/src/common-utils) with sensible defaults (zsh, configured as default shell, Oh My Zsh off). You don't need to declare it separately.

## Recommended companion setup

For host auth-token inheritance (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`), see the [init-secrets.sh shim pattern](../../README.md#companion-script-init-secretssh) in the root README.
