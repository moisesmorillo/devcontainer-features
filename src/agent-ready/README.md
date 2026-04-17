# `agent-ready`

Opinionated devcontainer setup for AI-assisted coding workflows.

## What it does

**Shell + prompt**
- Installs zsh (auto-installed if missing; pairs cleanly with `common-utils` if declared)
- Installs [mise](https://mise.jdx.dev/) for the remote user
- Pins and installs [Starship](https://starship.rs/) via mise
- Wires both `.bashrc` and `.zshrc` with activations so interactive shells **and** non-interactive subprocesses resolve tools

**Agent toolkit**
- [Claude Code](https://docs.claude.com/en/docs/claude-code) — the agent CLI itself (global default; repo `mise.toml` can override the version)
- Auto-installs plugins declared in the workspace's `.claude/settings.json` during post-create (idempotent — skips already-installed, retries "unknown" states)
- [Neovim](https://neovim.io/) — editor that agents commonly invoke
- [Lazygit](https://github.com/jesseduffield/lazygit) — fast git TUI
- All installed via mise, all can be version-pinned or disabled per-project

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

Self-contained — declare it alone and you get zsh, mise, starship, Claude Code pre-accepts, and SSH commit signing:

```json
{
  "features": {
    "ghcr.io/moisesmorillo/devcontainer-features/agent-ready:1": {}
  }
}
```

The feature auto-detects what's already present: if `zsh` is missing it installs it via apt and runs `chsh`; if it's already set up (e.g. because you declared `common-utils` alongside), the install step is a no-op.

### Optional: pair with `common-utils`

If you already want [`common-utils`](https://github.com/devcontainers/features/tree/main/src/common-utils) for other reasons (sudoers setup, a specific non-root user, Oh My Zsh, etc.), declare it alongside. `installsAfter` ensures it runs first:

```json
{
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "installZsh": true,
      "installOhMyZsh": false,
      "configureZshAsDefaultShell": true,
      "username": "vscode"
    },
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
| `neovimVersion` | string | `"latest"` | Neovim version installed via mise. Set to `"none"` to skip, or pin (e.g. `"0.10.2"`) |
| `lazygitVersion` | string | `"latest"` | Lazygit version installed via mise. Set to `"none"` to skip, or pin (e.g. `"0.44.1"`) |
| `claudeCodeVersion` | string | `"latest"` | Claude Code CLI version. Consumer repos can override by declaring `claude-code` in their own `mise.toml`. Set to `"none"` to skip (disables plugin install too) |
| `installClaudePlugins` | boolean | `true` | Auto-install plugins declared in the workspace's `.claude/settings.json` during post-create |

Example with options:

```json
{
  "features": {
    "ghcr.io/moisesmorillo/devcontainer-features/agent-ready:1": {
      "starshipVersion": "1.25.0",
      "installStarship": true,
      "claudeBypassPermissions": true,
      "neovimVersion": "0.10.2",
      "lazygitVersion": "none",
      "claudeCodeVersion": "latest",
      "installClaudePlugins": true
    }
  }
}
```

### Version control for claude-code

The feature installs `claude-code` globally via mise as a **default**, not a mandate. If your repo's `mise.toml` declares `claude-code = "2.1.110"` (or any version), mise's local-wins precedence means the repo's pinned version is what runs in that working directory. Keep `claude-code` in your `mise.toml` for reproducibility; the feature's global install is there to guarantee `claude` exists on fresh containers before your `mise install --yes` completes (which matters so post-create's plugin installer can actually invoke `claude plugin install`).

## Recommended companion setup

For host auth-token inheritance (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`), see the [init-secrets.sh shim pattern](../../README.md#companion-script-init-secretssh) in the root README.
