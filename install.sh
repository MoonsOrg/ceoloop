#!/bin/bash
# ============================================================================
# CEOLoop -- one-line installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MoonsOrg/ceoloop/main/install.sh | bash
#
# Installs CEOLoop globally:
#   1. Clones repo to ~/.ceoloop/
#   2. Symlinks bin/ceoloop to ~/.local/bin/ceoloop
#   3. Creates registry.json
#
# After install, cd into your project and run: ceoloop init
# ============================================================================
set -euo pipefail

REPO_URL="https://github.com/MoonsOrg/ceoloop.git"
CEOLOOP_HOME="$HOME/.ceoloop"
BIN_DIR="$HOME/.local/bin"
SYMLINK="$BIN_DIR/ceoloop"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}ok${NC} $*"; }
warn() { echo -e "  ${YELLOW}WARNING${NC} $*"; }
err()  { echo -e "  ${RED}ERROR${NC} $*" >&2; }
info() { echo "  $*"; }

echo ""
echo "  CEOLoop -- Installer"
echo ""

# --- Check prerequisites ---
info "Checking prerequisites..."
MISSING=""

# git
if command -v git >/dev/null 2>&1; then
  ok "git: $(command -v git)"
else
  MISSING="$MISSING git(xcode-select --install)"
fi

# jq
if command -v jq >/dev/null 2>&1; then
  ok "jq: $(command -v jq)"
else
  MISSING="$MISSING jq(brew install jq)"
fi

# tmux
TMUX_BIN=""
for candidate in /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
  [ -x "$candidate" ] && TMUX_BIN="$candidate" && break
done
command -v tmux >/dev/null 2>&1 && TMUX_BIN="$(command -v tmux)"
if [ -n "$TMUX_BIN" ]; then
  ok "tmux: $TMUX_BIN"
else
  MISSING="$MISSING tmux(brew install tmux)"
fi

# claude
CLAUDE_BIN=""
for candidate in /opt/homebrew/bin/claude /usr/local/bin/claude "$HOME/.local/bin/claude"; do
  [ -x "$candidate" ] && CLAUDE_BIN="$candidate" && break
done
command -v claude >/dev/null 2>&1 && CLAUDE_BIN="$(command -v claude)"
if [ -n "$CLAUDE_BIN" ]; then
  ok "claude: $CLAUDE_BIN"
else
  MISSING="$MISSING claude(https://claude.ai/code)"
fi

if [ -n "$MISSING" ]; then
  echo ""
  err "Missing prerequisites:"
  for item in $MISSING; do
    name="${item%%(*}"
    install="${item#*(}"
    install="${install%)}"
    echo "    - $name: install with: $install" >&2
  done
  echo ""
  err "Install the missing tools and run again."
  exit 1
fi

# --- Install or update ---
echo ""

if [ -d "$CEOLOOP_HOME" ]; then
  # Already installed -- update
  info "CEOLoop already installed at $CEOLOOP_HOME"
  info "Updating..."
  (cd "$CEOLOOP_HOME" && git pull --quiet)
  VERSION="$(cat "$CEOLOOP_HOME/VERSION" 2>/dev/null | tr -d '[:space:]')"
  ok "updated to v$VERSION"
else
  # Fresh install -- clone
  info "Cloning CEOLoop to $CEOLOOP_HOME..."
  git clone --quiet "$REPO_URL" "$CEOLOOP_HOME"
  VERSION="$(cat "$CEOLOOP_HOME/VERSION" 2>/dev/null | tr -d '[:space:]')"
  ok "cloned v$VERSION"
fi

# --- Create registry.json if not exists ---
REGISTRY="$CEOLOOP_HOME/registry.json"
if [ ! -f "$REGISTRY" ]; then
  echo '{"projects":[]}' > "$REGISTRY"
  ok "created registry.json"
fi

# --- Make the CLI executable ---
chmod +x "$CEOLOOP_HOME/bin/ceoloop"

# --- Symlink to ~/.local/bin ---
mkdir -p "$BIN_DIR"

# Remove old symlink if it points somewhere else
if [ -L "$SYMLINK" ]; then
  rm -f "$SYMLINK"
fi

ln -sf "$CEOLOOP_HOME/bin/ceoloop" "$SYMLINK"
ok "symlinked $SYMLINK -> $CEOLOOP_HOME/bin/ceoloop"

# --- Check if ~/.local/bin is on PATH ---
echo ""
if echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  ok "$BIN_DIR is on PATH"
else
  warn "$BIN_DIR is not on your PATH"
  echo ""
  info "Add it to your shell profile:"
  echo ""
  if [ -f "$HOME/.zshrc" ]; then
    info "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    info "  source ~/.zshrc"
  elif [ -f "$HOME/.bashrc" ]; then
    info "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    info "  source ~/.bashrc"
  else
    info "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.profile"
    info "  source ~/.profile"
  fi
fi

# --- Success ---
echo ""
echo "  CEOLoop installed."
echo ""
echo "  Next: cd into your project and run:"
echo "    ceoloop init"
echo ""
