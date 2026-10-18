#!/usr/bin/env bash
# One-shot setup: zsh + Oh My Zsh (default theme) + history autosuggestions
# + syntax highlighting + bat/eza + safety and DevOps aliases. Safe to re-run.
set -euo pipefail

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# Use sudo only if needed and available
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && SUDO="sudo" || { echo "Need root or sudo"; exit 1; }
fi

# 1. Install prerequisites (zsh, git, curl)
log "Installing zsh, git, curl..."
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y zsh git curl
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y zsh git curl util-linux-user
elif command -v yum >/dev/null 2>&1; then
  $SUDO yum install -y zsh git curl util-linux-user
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --noconfirm zsh git curl
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add --no-cache zsh git curl
elif command -v zypper >/dev/null 2>&1; then
  $SUDO zypper install -y zsh git curl
else
  echo "Unsupported package manager. Install zsh, git and curl manually." >&2
  exit 1
fi

# 2. Install Oh My Zsh (unattended, keeps existing .zshrc if present)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
  log "Oh My Zsh already installed, skipping."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# 3. Install plugins
clone_plugin() {
  local name="$1" url="$2"
  if [ ! -d "$ZSH_CUSTOM/plugins/$name" ]; then
    log "Installing plugin: $name"
    git clone --depth=1 "$url" "$ZSH_CUSTOM/plugins/$name"
  else
    log "Plugin $name already present, skipping."
  fi
}
clone_plugin zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting

# 3b. Install bat and eza (best effort; the zsh config only uses them if present)
log "Installing bat and eza..."
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get install -y bat || true      # installs as "batcat" on Debian/Ubuntu
  $SUDO apt-get install -y eza || true
elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
  PM="$(command -v dnf || command -v yum)"
  $SUDO "$PM" install -y epel-release || true   # bat/eza live in EPEL on Rocky/RHEL
  $SUDO "$PM" install -y bat || true
  $SUDO "$PM" install -y eza || true
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -S --noconfirm --needed bat eza || true
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add --no-cache bat eza || true
elif command -v zypper >/dev/null 2>&1; then
  $SUDO zypper install -y bat eza || true
fi

# eza fallback: grab the official release binary if the repos didn't have it
if ! command -v eza >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)        EZA_T="x86_64-unknown-linux-gnu" ;;
    aarch64|arm64) EZA_T="aarch64-unknown-linux-gnu" ;;
    *)             EZA_T="" ;;
  esac
  if [ -n "$EZA_T" ]; then
    log "eza not in repos, downloading release binary..."
    TMP="$(mktemp -d)"
    if curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_T}.tar.gz" -o "$TMP/eza.tgz" \
       && tar -xzf "$TMP/eza.tgz" -C "$TMP" \
       && $SUDO install -m 0755 "$TMP/eza" /usr/local/bin/eza; then
      log "eza installed."
    else
      log "Could not install eza; falling back to plain ls."
    fi
    rm -rf "$TMP"
  fi
fi

# 4. Configure ~/.zshrc
ZSHRC="$HOME/.zshrc"
[ -f "$ZSHRC" ] || cp "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$ZSHRC"

log "Enabling plugins in ~/.zshrc..."
if grep -q '^plugins=(' "$ZSHRC"; then
  for p in zsh-autosuggestions zsh-syntax-highlighting; do
    grep -E '^plugins=\(.*\b'"$p"'\b' "$ZSHRC" >/dev/null || \
      sed -i.bak -E "s/^plugins=\((.*)\)/plugins=(\1 $p)/" "$ZSHRC"
  done
else
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"
fi

# 5. Colours + history tweaks (added once, inside a marked block)

# Remove any previous version of our block so re-runs pick up changes
sed -i.bak '/# >>> custom-shell-setup >>>/,/# <<< custom-shell-setup <<</d' "$ZSHRC"

log "Adding colour, history and prompt settings..."
{
  cat <<'EOF'

# >>> custom-shell-setup >>>
# --- Coloured listings: eza if installed, otherwise plain ls ---
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -lah --group-directories-first --git'
  alias lt='eza --tree --level=2 --group-directories-first'
else
  if ls --color=auto >/dev/null 2>&1; then
    alias ls='ls --color=auto'
  else
    export CLICOLOR=1
  fi
  alias ll='ls -lah'
fi
alias grep='grep --color=auto'
[ -x "$(command -v dircolors)" ] && eval "$(dircolors -b)"
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# --- bat: syntax-highlighted cat (Debian/Ubuntu call the binary "batcat") ---
if command -v bat >/dev/null 2>&1; then
  _bat=bat
elif command -v batcat >/dev/null 2>&1; then
  _bat=batcat
  alias bat='batcat'
fi
if [ -n "${_bat:-}" ]; then
  alias cat="$_bat --paging=never --style=plain"   # behaves like cat, but coloured
fi

# --- Safety: confirm before overwriting or deleting (bypass with: \rm, \cp, \mv) ---
alias rm='rm -I'      # asks once when deleting 3+ files or recursively
alias cp='cp -i'
alias mv='mv -i'

# --- Navigation and system ---
alias ..='cd ..'
alias ...='cd ../..'
alias c='clear'
alias h='history'
alias s='sudo'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ports='ss -tulpn'
alias psg='ps aux | grep -v grep | grep -i'
alias reload='source ~/.zshrc'

# --- DevOps shortcuts ---
alias ap='ansible-playbook'
alias apc='ansible-playbook --check --diff'
alias ans='ansible'
alias av='ansible-vault'
alias ag='ansible-galaxy'
alias ainv='ansible-inventory --graph'
alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias k='kubectl'
alias tf='terraform'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias s='ssh'

# History: large, shared, de-duplicated (feeds the autosuggestions)
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_REDUCE_BLANKS

# Autosuggestion look: grey text, accept with Right arrow or End
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Prompt: robbyrussell style + hostname, e.g.  ➜ ansible-vm1 ~
PROMPT='%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ ) %{$fg_bold[yellow]%}%m%{$reset_color%} %{$fg[cyan]%}%c%{$reset_color%} $(git_prompt_info)'
# <<< custom-shell-setup <<<
EOF
} >> "$ZSHRC"

# 6. Make zsh the default shell
ZSH_PATH="$(command -v zsh)"
USER_NAME="$(id -un)"
log "Setting zsh as default login shell..."
grep -qx "$ZSH_PATH" /etc/shells 2>/dev/null || echo "$ZSH_PATH" | $SUDO tee -a /etc/shells >/dev/null
if ! $SUDO chsh -s "$ZSH_PATH" "$USER_NAME" 2>/dev/null; then
  $SUDO usermod -s "$ZSH_PATH" "$USER_NAME" 2>/dev/null || echo "Could not change login shell; using .bashrc hand-off only."
fi

# Fallback: if the VM still starts bash, hand over to zsh for interactive sessions only.
touch "$HOME/.bashrc"
for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$rc" ] || continue
  sed -i '/# >>> auto-zsh >>>/,/# <<< auto-zsh <<</d' "$rc"
  cat >> "$rc" <<'EOF'

# >>> auto-zsh >>>
case $- in
  *i*) if [ -z "$ZSH_VERSION" ] && command -v zsh >/dev/null 2>&1; then exec zsh -l; fi ;;
esac
# <<< auto-zsh <<<
EOF
done

log "Login shell now: $(getent passwd "$USER_NAME" | cut -d: -f7)"
log "Config markers in ~/.zshrc: $(grep -c 'custom-shell-setup' "$ZSHRC")"

log "Done! Log out and back in, or run: exec zsh"
