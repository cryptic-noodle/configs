#!/usr/bin/env bash
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────
#  Zsh + Antidote Setup & Plugin Manager (User-level, No sudo)
# ─────────────────────────────────────────────────────────────

# -------------------------
# Logging helpers
# -------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

info()    { echo -e "${BLUE}==>${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
fatal()   { echo -e "${RED}✖${RESET} $*" >&2; exit 1; }

# -------------------------
# Preconditions
# -------------------------
command -v zsh >/dev/null 2>&1 || fatal "zsh is not installed"
command -v git >/dev/null 2>&1 || fatal "git is not installed"

[[ -t 1 ]] || fatal "Interactive terminal required"

HOME_DIR="$HOME"
ZDOTDIR="${ZDOTDIR:-$HOME_DIR}"

ANTIDOTE_DIR="$ZDOTDIR/.antidote"
PLUGINS_FILE="$ZDOTDIR/.zsh_plugins.txt"
ALIASES_FILE="$ZDOTDIR/.zshrc_aliases"
ZSHRC_FILE="$ZDOTDIR/.zshrc"

# -------------------------
# Install Antidote (if needed)
# -------------------------
if [[ ! -d "$ANTIDOTE_DIR" ]]; then
  info "Cloning Antidote"
  git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_DIR"
else
  info "Antidote already installed"
fi

# Ensure plugins file exists
touch "$PLUGINS_FILE"

# -------------------------
# Managed plugin catalog
# -------------------------
PLUGINS=(
  "romkatv/powerlevel10k"
  "zsh-users/zsh-autosuggestions"
  "zsh-users/zsh-syntax-highlighting"
  "zsh-users/zsh-completions"
  "getantidote/use-omz"
  "ohmyzsh/ohmyzsh path:lib"
  "ohmyzsh/ohmyzsh path:plugins/git"
  "ohmyzsh/ohmyzsh path:plugins/rails"
  "ohmyzsh/ohmyzsh path:plugins/bundler"
)

has_plugin() {
  grep -Fxq "$1" "$PLUGINS_FILE"
}

toggle_plugin() {
  local p="$1"
  if has_plugin "$p"; then
    sed -i "\|^$p\$|d" "$PLUGINS_FILE"
  else
    echo "$p" >>"$PLUGINS_FILE"
  fi
}

# -------------------------
# Interactive plugin manager
# -------------------------
while true; do
  clear
  info "Antidote Plugin Manager"
  echo

  i=1
  for p in "${PLUGINS[@]}"; do
    if has_plugin "$p"; then
      printf " [%d] [x] %s\n" "$i" "$p"
    else
      printf " [%d] [ ] %s\n" "$i" "$p"
    fi
    ((i++))
  done

  echo
  echo " [a] Add custom plugin"
  echo " [r] Remove plugin by line number"
  echo " [s] Save and exit"
  echo " [q] Quit without saving"
  echo

  read -rp "Select option: " choice </dev/tty

  case "$choice" in
    [1-9])
      toggle_plugin "${PLUGINS[$((choice-1))]}"
      ;;
    a)
      read -rp "Enter plugin line: " custom </dev/tty
      [[ -n "$custom" ]] && echo "$custom" >>"$PLUGINS_FILE"
      ;;
    r)
      echo
      nl -ba "$PLUGINS_FILE"
      read -rp "Line number to remove: " ln </dev/tty
      sed -i "${ln}d" "$PLUGINS_FILE"
      ;;
    s)
      success "Plugin configuration saved"
      break
      ;;
    q)
      warn "Aborted — no changes saved"
      exit 0
      ;;
  esac
done

# -------------------------
# Ensure .zshrc
# -------------------------
if [[ ! -f "$ZSHRC_FILE" ]]; then
  info "Creating .zshrc"
  cat >"$ZSHRC_FILE" <<'EOF'
# Antidote
source ~/.antidote/antidote.zsh
antidote load

# Aliases
[[ -f ~/.zshrc_aliases ]] && source ~/.zshrc_aliases
EOF
else
  info ".zshrc already exists (not overwriting)"
fi

# -------------------------
# Aliases (optional)
# -------------------------
read -rp "Install common aliases? [y/N]: " install_aliases </dev/tty
if [[ "$install_aliases" =~ ^[Yy]$ ]]; then
  cat >"$ALIASES_FILE" <<'EOF'
alias reload="exec zsh"
alias config="nvim ~/.zshrc"
alias plugins="nvim ~/.zsh_plugins.txt"
EOF
  success "Aliases installed"
fi

# -------------------------
# Final note (optional recovery)
# -------------------------
echo
warn "If plugins do not load correctly, you can force regeneration with:"
echo "  antidote bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.zsh"
echo

exec zsh

success "Zsh + Antidote setup complete"
echo "Restart your shell or run: exec zsh"
