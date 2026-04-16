#!/usr/bin/env bash
# agent-ready feature — install.sh
#
# Runs as root at image-build time. Responsibilities:
#   1. Install apt packages mise needs (zstd for tarball extraction, jq for post-create)
#   2. Install mise as the remote user (tools live in $HOME/.local/share/mise)
#   3. Pin starship via mise so the prompt is reproducible
#   4. Seed ~/.bashrc and ~/.zshrc with activations and claude alias
#   5. Drop post-create.sh into /usr/local/share/agent-ready/ so the
#      devcontainer runtime can invoke it per the manifest's postCreateCommand
#
# Feature options arrive as uppercase env vars: STARSHIPVERSION, INSTALLSTARSHIP, CLAUDEBYPASSPERMISSIONS.
# _REMOTE_USER is injected by the devcontainer CLI and points to the
# user configured as remoteUser in devcontainer.json (usually "vscode").

set -euo pipefail

STARSHIP_VERSION="${STARSHIPVERSION:-1.24.2}"
INSTALL_STARSHIP="${INSTALLSTARSHIP:-true}"
NEOVIM_VERSION="${NEOVIMVERSION:-latest}"
LAZYGIT_VERSION="${LAZYGITVERSION:-latest}"
USERNAME="${_REMOTE_USER:-vscode}"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"

if [[ -z "$USER_HOME" ]]; then
  echo "ERROR: agent-ready: user '$USERNAME' not found." >&2
  echo "Set 'remoteUser' in devcontainer.json, or use a base image that creates a user." >&2
  exit 1
fi

# Install apt packages. We batch zstd (mise tarball extraction), jq
# (post-create.sh needs it for claude.json), and zsh (fallback if the
# consumer didn't declare common-utils) into a single apt transaction
# so the package index is only fetched once.
NEEDS_APT=(ca-certificates)
command -v zstd >/dev/null 2>&1 || NEEDS_APT+=(zstd)
command -v jq   >/dev/null 2>&1 || NEEDS_APT+=(jq)
command -v zsh  >/dev/null 2>&1 || NEEDS_APT+=(zsh)

echo "==> [agent-ready] Installing apt packages: ${NEEDS_APT[*]}..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends "${NEEDS_APT[@]}"
apt-get clean && rm -rf /var/lib/apt/lists/*

# Make zsh the login shell if it isn't already. Idempotent: no-op when
# common-utils already ran chsh, or when the base image set zsh as default.
CURRENT_SHELL="$(getent passwd "$USERNAME" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "/usr/bin/zsh" && "$CURRENT_SHELL" != "/bin/zsh" ]]; then
  echo "==> [agent-ready] Setting zsh as default shell for $USERNAME (was $CURRENT_SHELL)..."
  chsh -s "$(command -v zsh)" "$USERNAME"
fi

echo "==> [agent-ready] Installing mise for $USERNAME..."
# Run the installer as the target user so $HOME is correct and no chown is needed.
su - "$USERNAME" -c 'curl -fsSL https://mise.run | sh'

if [[ "$INSTALL_STARSHIP" == "true" ]]; then
  echo "==> [agent-ready] Pinning starship@$STARSHIP_VERSION via mise..."
  su - "$USERNAME" -c "\$HOME/.local/bin/mise use -g starship@$STARSHIP_VERSION"
fi

# Neovim and lazygit round out the "agent-ready" toolkit — agents
# commonly invoke an editor and a git TUI. Both accept "none" to skip
# (e.g. for minimal images) or a pinned version for reproducibility.
if [[ "$NEOVIM_VERSION" != "none" ]]; then
  echo "==> [agent-ready] Installing neovim@$NEOVIM_VERSION via mise..."
  su - "$USERNAME" -c "\$HOME/.local/bin/mise use -g neovim@$NEOVIM_VERSION"
fi

if [[ "$LAZYGIT_VERSION" != "none" ]]; then
  echo "==> [agent-ready] Installing lazygit@$LAZYGIT_VERSION via mise..."
  su - "$USERNAME" -c "\$HOME/.local/bin/mise use -g lazygit@$LAZYGIT_VERSION"
fi

echo "==> [agent-ready] Seeding shell rc files..."
# Append activations only if missing. We write to BOTH rc files because:
#   - .zshrc is the primary interactive shell after common-utils chsh
#   - .bashrc keeps `sh -c`, cron-style subprocesses, and CI steps working
for rc in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
  touch "$rc"
  if [[ "$rc" == *".zshrc" ]]; then
    grep -q 'mise activate zsh' "$rc" 2>/dev/null || \
      echo 'eval "$(~/.local/bin/mise activate zsh)"' >> "$rc"
    if [[ "$INSTALL_STARSHIP" == "true" ]]; then
      grep -q 'starship init zsh' "$rc" 2>/dev/null || \
        echo 'eval "$(starship init zsh)"' >> "$rc"
    fi
  else
    grep -q 'mise activate bash' "$rc" 2>/dev/null || \
      echo 'eval "$(~/.local/bin/mise activate bash)"' >> "$rc"
  fi
  grep -q 'dangerously-skip-permissions' "$rc" 2>/dev/null || \
    echo 'alias claude="claude --dangerously-skip-permissions"' >> "$rc"
  chown "$USERNAME:$USERNAME" "$rc"
done

echo "==> [agent-ready] Staging post-create.sh at /usr/local/share/agent-ready/..."
mkdir -p /usr/local/share/agent-ready
cp "$(dirname "$0")/post-create.sh" /usr/local/share/agent-ready/post-create.sh
chmod 0755 /usr/local/share/agent-ready/post-create.sh
# Propagate the claudeBypassPermissions option to post-create via a file.
# Env vars don't survive between feature install and postCreateCommand,
# so we pin the decision at build time.
echo "${CLAUDEBYPASSPERMISSIONS:-true}" > /usr/local/share/agent-ready/.bypass-permissions
chmod 0644 /usr/local/share/agent-ready/.bypass-permissions

echo "==> [agent-ready] Install complete."
