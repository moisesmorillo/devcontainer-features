#!/usr/bin/env bash
# agent-ready feature — post-create.sh
#
# Runs as the remote user AFTER the container is created, BEFORE the
# consuming repo's postCreateCommand. Has access to:
#   - Mounts (including ~/.ssh bind-mounted from host)
#   - env_file-injected vars (GH_TOKEN, CLAUDE_CODE_OAUTH_TOKEN)
#   - Volumes (including claude-data if the repo mounts it at ~/.claude)
#
# Responsibilities:
#   1. Fix ~/.claude ownership if it's a fresh named volume
#   2. Pre-accept Claude Code dialogs so agents run headlessly
#   3. Auto-configure SSH commit signing from the mounted ~/.ssh key
#   4. Report host-injected auth-token status to the developer

set -euo pipefail

SHARE_DIR="/usr/local/share/agent-ready"
BYPASS_PERMISSIONS="$(cat "$SHARE_DIR/.bypass-permissions" 2>/dev/null || echo "true")"

echo "==> [agent-ready] Running post-create..."

# ---------------------------------------------------------------------------
# Claude Code: fix volume ownership + pre-accept dialogs.
# ---------------------------------------------------------------------------
# If ~/.claude is backed by a fresh docker named volume, Docker creates
# it as root:root. `claude` fails silently on permission errors.
if [[ -d "$HOME/.claude" ]]; then
  sudo chown -R "$(id -u):$(id -g)" "$HOME/.claude" 2>/dev/null || true
fi

# Three dialogs we pre-accept by seeding ~/.claude.json:
#   hasCompletedOnboarding          — workaround for anthropics/claude-code#46259
#                                     (CLAUDE_CODE_OAUTH_TOKEN is ignored otherwise)
#   bypassPermissionsModeAccepted   — skips the "Bypass Permissions mode" warning
#                                     raised by the --dangerously-skip-permissions alias
#   projects[pwd].hasTrustDialogAccepted
#                                   — skips the "trust this folder?" prompt
#
# We merge with jq instead of overwriting: the claude-data volume may
# persist history, MCP configs, or plugins that we must preserve.
CLAUDE_JSON="$HOME/.claude.json"
WORKSPACE_PATH="$(pwd)"
if [[ ! -f "$CLAUDE_JSON" ]]; then
  echo '{}' > "$CLAUDE_JSON"
fi

JQ_PROGRAM='
  .hasCompletedOnboarding = true
  | .projects[$ws].hasTrustDialogAccepted = true
'
if [[ "$BYPASS_PERMISSIONS" == "true" ]]; then
  JQ_PROGRAM="$JQ_PROGRAM | .bypassPermissionsModeAccepted = true"
fi
jq --arg ws "$WORKSPACE_PATH" "$JQ_PROGRAM" \
  "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"

# ---------------------------------------------------------------------------
# Git safe.directory — accept the bind-mounted workspace.
# ---------------------------------------------------------------------------
# Docker bind-mounts don't preserve ownership 1:1 across host/container
# boundaries. Git 2.35.2+ refuses to operate on repos it sees as
# "owned by someone else" (CVE-2022-24765 mitigation). Marking $(pwd)
# safe tells git this mismatch is intentional. Without it, `git status`
# errors out and tools built on top (lazygit, hooks, CI scripts) panic.
# $(pwd) resolves to the workspaceFolder — post-create runs with CWD
# set there by the devcontainer runtime.
git config --global --add safe.directory "$(pwd)"

# ---------------------------------------------------------------------------
# Git SSH commit signing — auto-detect public key from mounted ~/.ssh.
# ---------------------------------------------------------------------------
SSH_PUB_KEY=""
for key in "$HOME"/.ssh/id_*.pub; do
  [[ -f "$key" ]] && SSH_PUB_KEY="$key" && break
done

if [[ -n "$SSH_PUB_KEY" ]]; then
  echo "==> [agent-ready] Configuring SSH commit signing with $(basename "$SSH_PUB_KEY")..."
  git config --global gpg.format ssh
  git config --global user.signingkey "$SSH_PUB_KEY"
  git config --global commit.gpgsign true

  # Store allowed_signers under .config/git because .ssh is typically
  # mounted read-only from the host.
  ALLOWED_SIGNERS="$HOME/.config/git/allowed_signers"
  mkdir -p "$(dirname "$ALLOWED_SIGNERS")"
  git config --global gpg.ssh.allowedSignersFile "$ALLOWED_SIGNERS"

  EMAIL=$(git config user.email 2>/dev/null || true)
  if [[ -z "$EMAIL" ]]; then
    # SSH public keys typically carry a comment with user@host or email.
    EMAIL=$(awk '{print $NF}' "$SSH_PUB_KEY")
  fi
  echo "${EMAIL:-unknown} $(cat "$SSH_PUB_KEY")" > "$ALLOWED_SIGNERS"
fi

# ---------------------------------------------------------------------------
# Auth-token status report.
# ---------------------------------------------------------------------------
# Tokens arrive via env_file loaded by docker-compose. When absent, the
# developer can still run `gh auth login` / `claude login` inside the
# container — we just flag the missing value.
echo "==> [agent-ready] Auth status:"
if [[ -n "${GH_TOKEN:-}" ]]; then
  echo "    gh     — GH_TOKEN inherited from host (length=${#GH_TOKEN})"
else
  echo "    gh     — no host token; run 'gh auth login' inside the container"
fi
if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "    claude — CLAUDE_CODE_OAUTH_TOKEN inherited from host"
else
  echo "    claude — no host token; run 'claude login' inside the container"
fi

echo "==> [agent-ready] Post-create complete."
