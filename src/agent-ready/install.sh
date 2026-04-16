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
USERNAME="${_REMOTE_USER:-vscode}"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"

if [[ -z "$USER_HOME" ]]; then
  echo "ERROR: agent-ready: user '$USERNAME' not found. Is common-utils installed?" >&2
  exit 1
fi

# Defensive: zsh must exist. dependsOn common-utils ensures it, but we
# fail fast with a clear message if someone disabled the dependency.
if ! command -v zsh >/dev/null 2>&1; then
  echo "ERROR: agent-ready: zsh is required but not installed." >&2
  echo "Declare the common-utils feature with installZsh=true, or install zsh in your base image." >&2
  exit 1
fi

echo "==> [agent-ready] Installing apt packages (zstd, jq)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends zstd jq ca-certificates
apt-get clean && rm -rf /var/lib/apt/lists/*

echo "==> [agent-ready] Installing mise for $USERNAME..."
# Run the installer as the target user so $HOME is correct and no chown is needed.
su - "$USERNAME" -c 'curl -fsSL https://mise.run | sh'

if [[ "$INSTALL_STARSHIP" == "true" ]]; then
  echo "==> [agent-ready] Pinning starship@$STARSHIP_VERSION via mise..."
  su - "$USERNAME" -c "\$HOME/.local/bin/mise use -g starship@$STARSHIP_VERSION"
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
