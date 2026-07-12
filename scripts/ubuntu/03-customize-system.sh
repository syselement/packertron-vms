#!/usr/bin/env bash
#
# Customize Ubuntu Desktop or Server
#
# Notes:
# - Run as root.
# - Console output is colorized when interactive.
# - Log output is written to /var/log/customize-system-<run_id>.log without ANSI escapes.
# - GNOME string values passed to run_user_gsettings_try must already be quoted, e.g. "'prefer-dark'".
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"
SCRIPT_NAME="customize-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"
UBUNTU_VARIANT="server"
APT_SOURCES_CHANGED=false

APT_BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  gnupg
  lsb-release
)

COMMON_PACKAGES=(
  aptitude
  bash-completion
  bat
  btop
  build-essential
  docker-ctop
  duf
  eza
  fastfetch
  fontconfig
  gdu
  git
  gping
  htop
  iftop
  imagemagick
  ipcalc
  iperf3
  jq
  lm-sensors
  nano
  net-tools
  nload
  nmap
  npm
  openjdk-21-jre-headless
  pipx
  plocate
  s-tui
  speedtest-cli
  sshpass
  stress
  sysstat
  tmux
  tor
  tree
  ugrep
  unzip
  vim
  wget
  zsh
)

DESKTOP_PACKAGES=(
  brave-browser
  dbeaver-ce
  filezilla
  flameshot
  flatpak
  fonts-noto-color-emoji
  gnome-shell-extension-manager
  gnome-shell-extensions
  gnome-tweaks
  sublime-text
  terminator
  vlc
  xclip
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[${SCRIPT_NAME}] ERROR must run as root (use: sudo bash $0)" >&2
    exit 1
  fi
}

# --- must be root ---
require_root

# --- Logging setup ---
# --- ANSI Colors for console output ---
if [[ -t 1 ]]; then
  t_bold=$'\e[1m'; t_dim=$'\e[2m'
  t_green=$'\e[32m'; t_yellow=$'\e[33m'; t_red=$'\e[31m'
  t_reset=$'\e[0m'
else
  t_bold=""; t_dim=""; t_green=""; t_yellow=""; t_red=""; t_reset=""
fi

# Console keeps ANSI colors, log file stores ANSI-stripped output.
exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[[:alpha:]]//g' > "$LOG_FILE")) 2>&1

_ts() { date +'%F %T'; }
log() {
  local msg="$*"
  local ts
  ts="$(_ts)"
  printf '%s %s %b\n' "[$ts]" "$LOG_PREFIX" "$msg"
}
info()  { log "${t_dim}INFO${t_reset}  $*"; }
ok()    { log "${t_green}${t_bold}OK${t_reset}    $*"; }
warn()  { log "${t_yellow}${t_bold}WARN${t_reset}  $*"; }
error() { log "${t_red}${t_bold}ERROR${t_reset} $*"; }
die()   { error "$*"; exit 1; }

# --- Helpers ---
user_home() {
  local account="$1"
  getent passwd "$account" | cut -d: -f6
}

detect_ubuntu_variant() {
  local default_target=""

  if dpkg-query -W -f='${Status}' ubuntu-desktop 2>/dev/null | grep -q "install ok installed"; then
    UBUNTU_VARIANT="desktop"
    return
  fi

  default_target="$(systemctl get-default 2>/dev/null || true)"
  if [[ "$default_target" == "graphical.target" ]] &&
    { compgen -G '/usr/share/xsessions/*.desktop' >/dev/null ||
      compgen -G '/usr/share/wayland-sessions/*.desktop' >/dev/null; }; then
    UBUNTU_VARIANT="desktop"
  else
    UBUNTU_VARIANT="server"
  fi
}

install_package_array() {
  local description="$1"
  shift
  local packages=("$@")

  if (( ${#packages[@]} == 0 )); then
    info "${description}: no packages requested, skipping"
    return
  fi

  info "installing ${#packages[@]} ${description} packages"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
  ok "${description} package installation completed"
}

write_file_if_changed() {
  local source_file="$1"
  local destination_file="$2"

  if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
    return 1
  fi

  install -D -m 0644 "$source_file" "$destination_file"
  return 0
}

run_user_gsettings_try() {
  local schema="$1"
  local key="$2"
  local value="$3"
  sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
    "gsettings set ${schema} ${key} ${value}" >/dev/null 2>&1 || true
}

enable_system_monitor_extension() {
  sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc '
    set -euo pipefail
    if ! command -v gnome-extensions >/dev/null 2>&1; then
      exit 0
    fi

    ext_uuid="system-monitor@gnome-shell-extensions.gcampax.github.com"
    gnome-extensions enable "$ext_uuid" >/dev/null 2>&1 || true
  ' >/dev/null 2>&1 || true
}

# --- Repository setup ---
ensure_fastfetch_ppa() {
  local ppa="ppa:zhangsongcui3371/fastfetch"

  case "$VERSION_ID" in
    24.*)
      if grep -Rqs "zhangsongcui3371/fastfetch" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        info "fastfetch PPA already present"
        return
      fi

      if ! command -v add-apt-repository >/dev/null 2>&1; then
        die "add-apt-repository is required for the fastfetch PPA on Ubuntu ${VERSION_ID}"
      fi

      if add-apt-repository --yes --no-update "$ppa" >/dev/null 2>&1; then
        APT_SOURCES_CHANGED=true
        ok "added fastfetch PPA for Ubuntu ${VERSION_ID}"
      else
        warn "failed to add fastfetch PPA; fastfetch may not be available"
      fi
      ;;
    26.*)
      info "Ubuntu ${VERSION_ID} provides fastfetch; skipping fastfetch PPA"
      ;;
    *)
      warn "Ubuntu ${VERSION_ID} is not explicitly handled for the fastfetch PPA; using configured repositories"
      ;;
  esac
}

install_docker_ctop_repository() {
  local key_file="/usr/share/keyrings/azlux-archive-keyring.gpg"
  local source_file="/etc/apt/sources.list.d/azlux.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"

  if ! curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor --yes -o "$tmp_key"; then
    rm -f "$tmp_key" "$tmp_source"
    die "failed to download the AZLux repository signing key"
  fi

  cat > "$tmp_source" <<'EOF'
Types: deb
URIs: http://packages.azlux.fr/debian/
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/azlux-archive-keyring.gpg
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
    ok "installed AZLux repository signing key"
  else
    info "AZLux repository signing key already current"
  fi

  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
    ok "configured AZLux repository"
  else
    info "AZLux repository already configured"
  fi

  rm -f "$tmp_key" "$tmp_source"
}

ensure_sublime_text_repository() {
  local key_file="/usr/share/keyrings/sublimehq-pub.asc"
  local source_file="/etc/apt/sources.list.d/sublime-text.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o "$tmp_key"
  cat > "$tmp_source" <<'EOF'
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /usr/share/keyrings/sublimehq-pub.asc
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
}

ensure_brave_browser_repository() {
  local key_file="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
  local source_file="/etc/apt/sources.list.d/brave-browser-release.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg -o "$tmp_key"
  curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser.sources -o "$tmp_source"

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
  if compgen -G '/etc/apt/sources.list.d/brave-browser-*.list' >/dev/null; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f /etc/apt/sources.list.d/brave-browser-*.list
}

ensure_dbeaver_repository() {
  local key_file="/usr/share/keyrings/dbeaver.gpg.key"
  local source_file="/etc/apt/sources.list.d/dbeaver.list"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  if ! curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor --yes -o "$tmp_key"; then
    rm -f "$tmp_key" "$tmp_source"
    die "failed to download the DBeaver repository signing key"
  fi
  cat > "$tmp_source" <<'EOF'
deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
}

# --- Desktop tools ---
configure_terminator() {
  if sudo -u "$USER_NAME" -H bash -lc '
    [[ -f "$HOME/.config/terminator/config" ]] && \
    grep -q "font = JetBrainsMono Nerd Font Mono 16" "$HOME/.config/terminator/config" && \
    grep -q "scrollback_infinite = True" "$HOME/.config/terminator/config"
  '; then
    info "Terminator already configured, skipping"
    return
  fi

  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    mkdir -p "$HOME/.config/terminator"
    cat > "$HOME/.config/terminator/config" << '"'"'EOF'"'"'
[global_config]
  window_state = maximise
[keybindings]
[profiles]
  [[default]]
    font = JetBrainsMono Nerd Font Mono 16
    foreground_color = "#f6f5f4"
    show_titlebar = False
    scrollback_infinite = True
    disable_mousewheel_zoom = True
    use_system_font = False
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
    [[[child1]]]
      type = Terminal
      parent = window0
[plugins]
EOF
  '
  ok "Terminator configured"
}

install_emote_snap() {
  if command -v snap >/dev/null 2>&1 && snap list emote >/dev/null 2>&1; then
    info "Emote snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Emote"
    return
  fi

  snap install emote
  ok "Emote installed"
}

install_postman_snap() {
  if command -v snap >/dev/null 2>&1 && snap list postman >/dev/null 2>&1; then
    info "Postman snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Postman"
    return
  fi

  snap install postman
  ok "Postman installed"
}

configure_flameshot() {
  if sudo -u "$USER_NAME" -H bash -lc '
    [[ -f "$HOME/.config/flameshot/flameshot.ini" ]] && \
    grep -q "^startupLaunch=true$" "$HOME/.config/flameshot/flameshot.ini" && \
    grep -q "^savePathFixed=true$" "$HOME/.config/flameshot/flameshot.ini"
  '; then
    info "Flameshot already configured, skipping"
    return
  fi

  install -d -o "$USER_NAME" -g "$USER_NAME" "/home/${USER_NAME}/Pictures/flameshot"
  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    mkdir -p "$HOME/.config/flameshot"
    cat > "$HOME/.config/flameshot/flameshot.ini" << '"'"'EOF'"'"'
[General]
contrastOpacity=188
copyOnDoubleClick=true
copyPathAfterSave=false
saveAfterCopy=true
saveAsFileExtension=png
saveLastRegion=true
savePath=/home/'"$USER_NAME"'/Pictures/flameshot
savePathFixed=true
showHelp=false
showMagnifier=true
showStartupLaunchMessage=false
squareMagnifier=true
startupLaunch=true
EOF
  '

  ok "Flameshot configured"
}

install_obsidian_snap() {
  if command -v snap >/dev/null 2>&1 && snap list obsidian >/dev/null 2>&1; then
    info "Obsidian snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Obsidian"
    return
  fi

  snap install obsidian --classic
  ok "Obsidian installed"
}

# --- Common user tools ---
install_tldr_pipx() {
  if sudo -u "$USER_NAME" -H bash -lc 'pipx list 2>/dev/null | grep -q "package tldr"'; then
    info "tldr already installed via pipx, skipping"
    return
  fi

  sudo -u "$USER_NAME" -H bash -lc 'pipx install tldr && pipx ensurepath'
  ok "tldr installed via pipx"
}

install_fzf_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  if [[ -d "$home/.fzf/.git" ]]; then
    info "updating fzf checkout for ${account}"
    sudo -u "$account" -H git -C "$home/.fzf" pull --ff-only
  elif [[ -e "$home/.fzf" ]]; then
    warn "${home}/.fzf exists but is not a Git checkout; skipping fzf for ${account}"
    return
  else
    info "cloning fzf for ${account}"
    sudo -u "$account" -H git clone --depth 1 https://github.com/junegunn/fzf.git "$home/.fzf"
  fi

  sudo -u "$account" -H "$home/.fzf/install" \
    --all --no-update-rc --no-zsh --no-fish --no-nushell
  ok "fzf installed for ${account}"
}

install_starship() {
  info "installing/updating Starship"
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
  command -v starship >/dev/null 2>&1 || die "Starship installation did not provide a starship command"
  ok "Starship installed"
}

install_jetbrainsmono_nerd_font_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  if sudo -u "$account" -H fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    info "JetBrainsMono Nerd Font already installed for ${account}, skipping"
    return
  fi

  sudo -u "$account" -H bash -c '
    set -euo pipefail
    font_dir="$HOME/.local/share/fonts"
    archive="$(mktemp --suffix=.zip)"
    mkdir -p "$font_dir"
    curl -fL -o "$archive" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -q -o "$archive" -d "$font_dir"
    rm -f "$archive"
    fc-cache -f "$font_dir"
  '
  ok "JetBrainsMono Nerd Font installed for ${account}"
}

configure_bash_for_user() {
  local account="$1"
  local home
  local bat_link
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"
  bat_link="$home/.local/bin/bat"

  sudo -u "$account" -H mkdir -p "$home/.local/bin"
  if [[ -L "$bat_link" ]]; then
    sudo -u "$account" -H ln -sfn /usr/bin/batcat "$bat_link"
  elif [[ -e "$bat_link" ]]; then
    warn "${bat_link} is not a symlink; preserving it"
  else
    sudo -u "$account" -H ln -s /usr/bin/batcat "$bat_link"
  fi

  sudo -u "$account" -H python3 - "$home" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

home = Path(sys.argv[1])
bashrc = home / ".bashrc"
aliases_path = home / ".bash_aliases"

aliases = r'''# $HOME/.bash_aliases — centralized interactive aliases

# System update
alias updateos='sudo sh -c "apt update && apt -y upgrade && apt -y autoremove"'

# Core utils
alias cat='batcat --paging=never'
alias df='df -h'
alias diff='diff --color=auto'
alias dir='dir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias vdir='vdir --color=auto'

# Listing
alias ls='ls -lh --color=auto'
alias la='ls -A'
alias l='eza -lah --group-directories-first'
alias ll='l -T'

# History
alias h='history'
alias hl='history | less'
alias hs='history | grep'
alias hsi='history | grep -i'

# Network / ports
alias ipa='ip -br -c a'
alias ports='ss -tunlp'

# Python
alias p3='python3'
alias python='python3'

# Search
alias ugq='ugrep --pretty --hidden -Qria'

# Mask stdin after first 5 chars
alias mask='awk '\''{ printf substr($0, 1, 5); for (i=6; i<=length($0); i++) printf "*"; print "" }'\'''

# Keep sudo credentials warm before sudo commands
alias sudo='sudo -v; sudo '

# Ubuntu default long-running command notification
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
'''

fzf_block = r'''# >>> fzf (managed) >>>
export FZF_DEFAULT_OPTS='-m --height 50% --border'
export FZF_CTRL_R_OPTS="$FZF_DEFAULT_OPTS"
export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS"
export FZF_ALT_C_OPTS="$FZF_DEFAULT_OPTS"

[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"
# <<< fzf (managed) <<<'''

fastfetch_block = r'''# >>> fastfetch (managed) >>>
# Fastfetch - login shells only
if shopt -q login_shell && command -v fastfetch >/dev/null 2>&1; then
    clear
    fastfetch
fi
# <<< fastfetch (managed) <<<'''

starship_block = r'''# >>> starship (managed) >>>
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
else
  PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi
# <<< starship (managed) <<<'''

dotfiles_hook = r'''# >>> future dotfiles hook (disabled) >>>
# DOTFILES_REPO_URL="https://github.com/<owner>/<dotfiles-repository>.git"
# DOTFILES_DIR="$HOME/.local/share/dotfiles"
# if [ -d "$DOTFILES_DIR/.git" ]; then
#   git -C "$DOTFILES_DIR" pull --ff-only
# else
#   git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
# fi
# "$DOTFILES_DIR/install.sh"
# <<< future dotfiles hook (disabled) <<<'''

def backup(path: Path) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}")
    counter = 1
    while destination.exists():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)

def install_if_changed(path: Path, content: str) -> bool:
    content = content.rstrip() + "\n"
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, candidate_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        subprocess.run(["bash", "-n", str(candidate)], check=True)
        if path.exists():
            backup(path)
            candidate.chmod(path.stat().st_mode & 0o777)
        else:
            candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
    return True

def set_line(content: str, pattern: str, replacement: str) -> str:
    if re.search(pattern, content, flags=re.M):
        replaced = False

        def replace_once(match: re.Match[str]) -> str:
            nonlocal replaced
            if not replaced:
                replaced = True
                return replacement
            return ""

        return re.sub(pattern, replace_once, content, flags=re.M)
    return content.rstrip() + "\n" + replacement + "\n"

source = bashrc.read_text(encoding="utf-8") if bashrc.exists() else ""

# Comment active aliases while preserving indentation and commented aliases.
source = re.sub(
    r'^(?![ \t]*#)([ \t]*)(alias[ \t].*)$',
    r'\1# \2',
    source,
    flags=re.M,
)

source = set_line(source, r'^[ \t]*HISTCONTROL=.*$', 'HISTCONTROL=ignoreboth:erasedups')
source = set_line(source, r'^[ \t]*HISTSIZE=.*$', 'HISTSIZE=50000')
source = set_line(source, r'^[ \t]*HISTFILESIZE=.*$', 'HISTFILESIZE=100000')
source = re.sub(r'^[ \t]*HISTTIMEFORMAT=.*\n?', '', source, flags=re.M)
source = re.sub(
    r'(^HISTFILESIZE=.*$)',
    lambda match: match.group(1) + "\nHISTTIMEFORMAT='%F %T '",
    source,
    count=1,
    flags=re.M,
)
source = set_line(source, r'^[ \t]*PROMPT_COMMAND=.*$', "PROMPT_COMMAND='history -a; history -n'")
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s checkwinsize.*$', 'shopt -s checkwinsize')
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s globstar.*$', 'shopt -s globstar 2>/dev/null')
source = re.sub(r'^[ \t]*#?[ \t]*set -o vi[ \t]*\n?', '', source, flags=re.M)

for name in ("fzf", "fastfetch", "starship", "future dotfiles hook"):
    source = re.sub(
        rf'\n?# >>> {re.escape(name)} \((?:managed|disabled)\) >>>.*?# <<< {re.escape(name)} \((?:managed|disabled)\) <<<\n?',
        '\n',
        source,
        flags=re.S,
    )

source = re.sub(
    r'^[ \t]*\[ -[fr] (?:~|"\$HOME)/\.fzf\.bash"? \] && source (?:~|"\$HOME)/\.fzf\.bash"?[ \t]*\n?',
    '',
    source,
    flags=re.M,
)

if not re.search(r'^[^#\n]*\.bash_aliases', source, flags=re.M):
    source = source.rstrip() + r'''

# Load centralized aliases.
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi
'''

source = source.rstrip() + "\n\n" + fzf_block + "\n\n" + fastfetch_block + "\n\n" + starship_block + "\n\n" + dotfiles_hook + "\n"

install_if_changed(aliases_path, aliases)
install_if_changed(bashrc, source)
PY

  sudo -u "$account" -H bash -n "$home/.bashrc"
  sudo -u "$account" -H bash -n "$home/.bash_aliases"
  ok "Bash configuration installed for ${account}"
}

configure_starship_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  sudo -u "$account" -H python3 - "$home" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import shutil
import sys
import tempfile

home = Path(sys.argv[1])
path = home / ".config" / "starship.toml"
content = """format = \"\"\"
${custom.root_marker}\\
$username\\
${custom.directory_icon}\\
$directory\\
$git_branch\\
$git_status\\
$fill\\
$hostname\\
$jobs\\
$cmd_duration\\
$status\\
$time\\
$line_break\\
$character\"\"\"

add_newline = false

[custom.root_marker]
command = "printf ''"
when = 'test "$(id -u)" -eq 0'
format = "[$output]($style) "
style = "bold red"

[username]
show_always = true
format = "[$user]($style) "
style_user = "bold yellow"
style_root = "bold red"

[custom.directory_icon]
command = '''
if [ "$PWD" = "$HOME" ]; then
    printf ''
else
    printf ''
fi
'''
when = true
format = "[$output]($style) "
style = "bold cyan"

[directory]
format = "[$path]($style) "
style = "bold cyan"
home_symbol = "~"
truncation_length = 3
truncation_symbol = "…/"
truncate_to_repo = false
read_only = " "
read_only_style = "bold red"

[git_branch]
symbol = " "
format = "[$symbol$branch]($style) "
style = "bold green"

[git_status]
format = "([$all_status$ahead_behind]($style) )"
style = "bold yellow"

[hostname]
ssh_only = true
format = "[$ssh_symbol$hostname]($style) "
style = "dimmed cyan"
ssh_symbol = "󰣀 "

[jobs]
symbol = " "
format = "[$symbol$number]($style) "
style = "bold red"
number_threshold = 1

[cmd_duration]
min_time = 2000
format = "[$duration]($style) "
style = "dimmed yellow"

[status]
disabled = false
format = "[$symbol$signal_name$maybe_int]($style) "
symbol = "✘ "
sigint_symbol = "✘ "
signal_symbol = "✘ "
not_executable_symbol = "✘ "
not_found_symbol = "✘ "
recognize_signal_code = true
map_symbol = false
style = "bold red"

[time]
disabled = false
format = "[ $time]($style)"
time_format = "%H:%M:%S"
style = "bold cyan"

[character]
format = "$symbol "
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[fill]
symbol = " "
"""

content = content.rstrip() + "\n"
old = path.read_text(encoding="utf-8") if path.exists() else None
if old != content:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        backup = path.with_name(f"{path.name}.bak.{stamp}")
        counter = 1
        while backup.exists():
            backup = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
            counter += 1
        shutil.copy2(path, backup)
    fd, candidate_name = tempfile.mkstemp(prefix=".starship.toml.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
PY
  ok "Starship configuration installed for ${account}"
}

echo "################################"
echo "# Customize System"
echo "################################"

info "================ RUN START ================"
info "run_id: ${RUN_ID}"
info "started_at: $(date -Is)"
START_TS="$(date +%s)"

# shellcheck disable=SC1091
. /etc/os-release
VERSION_ID="${VERSION_ID:-unknown}"
CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
ARCH="$(dpkg --print-architecture)"
info "distro version=${VERSION_ID} codename=${CODENAME} arch=${ARCH}"

detect_ubuntu_variant
ok "detected Ubuntu variant: ${UBUNTU_VARIANT}"

if id "$USER_NAME" >/dev/null 2>&1; then
  ok "running user-scoped commands as: ${USER_NAME} and root"
else
  die "user not found: ${USER_NAME}"
fi

# --- Connectivity checks ---
info "checking internet and DNS"
if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
  ok "Internet connected (ICMP ping)"
else
  warn "Internet not connected (ICMP ping failed)"
fi

if getent hosts ubuntu.com >/dev/null 2>&1; then
  ok "DNS resolution OK (ubuntu.com)"
else
  warn "DNS resolution FAILED (ubuntu.com)"
fi

# --- Update system ---
info "apt update/dist-upgrade"
apt-get update -y -qq
apt-get dist-upgrade -y -qq
ok "apt update/dist-upgrade completed"

# --- Update snaps (Desktop only) ---
if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  if command -v snap >/dev/null 2>&1; then
    info "snap refresh"
    if snap refresh; then
      ok "snap refresh completed"
    else
      warn "snap refresh failed, continuing"
    fi
  else
    warn "snap command not found, skipping snap refresh"
  fi
else
  info "server variant detected; skipping Desktop snap refresh"
fi

# --- APT prerequisites ---
install_package_array "APT bootstrap" "${APT_BOOTSTRAP_PACKAGES[@]}"
if [[ "$VERSION_ID" == 24.* ]]; then
  install_package_array "Ubuntu 24 repository bootstrap" software-properties-common
fi

# --- Configure repositories before one cache refresh ---
info "ensuring common repositories"
ensure_fastfetch_ppa
install_docker_ctop_repository

if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  info "ensuring Desktop application repositories"
  ensure_sublime_text_repository
  ensure_brave_browser_repository
  ensure_dbeaver_repository
else
  info "server variant detected; skipping Desktop application repositories"
fi

if [[ "$APT_SOURCES_CHANGED" == true ]]; then
  info "apt update after repository changes"
  apt-get update -y -qq
else
  info "APT repositories unchanged; existing package cache is current"
fi

# --- Install requested tools ---
install_package_array "common" "${COMMON_PACKAGES[@]}"
if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  install_package_array "Desktop" "${DESKTOP_PACKAGES[@]}"
else
  info "server variant detected; skipping Desktop packages"
fi

# --- Install common user tools and shell configuration ---
info "installing common user tools and shell configuration"
install_starship
for account in "$USER_NAME" root; do
  install_fzf_for_user "$account"
  install_jetbrainsmono_nerd_font_for_user "$account"
  configure_bash_for_user "$account"
  configure_starship_for_user "$account"
done
install_tldr_pipx
ok "common user tools and shell configuration completed"

# --- Install/configure Desktop-specific tools ---
if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  info "installing/configuring Desktop-specific tools"
  configure_terminator
  install_emote_snap
  install_postman_snap
  configure_flameshot
  install_obsidian_snap
  ok "Desktop-specific tools installed/configured"
else
  info "server variant detected; skipping Desktop-specific tools"
fi

# --- Post-install tweaks ---
info "updating locate database (best effort)"
updatedb || true

# --- GNOME and Dock customization (Desktop only) ---
if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  info "applying GNOME preferences (best effort)"

  run_user_gsettings_try org.gnome.desktop.interface color-scheme "'prefer-dark'"
  run_user_gsettings_try org.gnome.desktop.interface gtk-theme "'Yaru-dark'"
  run_user_gsettings_try org.gnome.desktop.interface show-battery-percentage "true"
  run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
  run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock extend-height "true"
  run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "32"
  run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock click-action "'minimize'"
  run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock show-trash "false"

  # --- Power / lockscreen: disable blank + lock ---
  run_user_gsettings_try org.gnome.desktop.session idle-delay "uint32 0"
  run_user_gsettings_try org.gnome.desktop.screensaver lock-enabled "false"
  run_user_gsettings_try org.gnome.desktop.screensaver lock-delay "uint32 0"
  run_user_gsettings_try org.gnome.desktop.notifications show-in-lock-screen "false"
  run_user_gsettings_try org.gnome.desktop.screensaver ubuntu-lock-on-suspend "false"
  run_user_gsettings_try org.gnome.system.location enabled "false"

  # --- GNOME extensions tweaks ---
  enable_system_monitor_extension

  # --- Dock favorites ---
  info "setting GNOME favorites (best effort)"
  sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
    "gsettings set org.gnome.shell favorite-apps \"[
      'org.gnome.Nautilus.desktop',
      'brave-browser.desktop',
      'terminator.desktop',
      'sublime_text.desktop',
      'obsidian_obsidian.desktop',
      'code.desktop'
    ]\"" >/dev/null 2>&1 || true
  ok "GNOME preferences applied"
else
  info "server variant detected; skipping GNOME preferences"
fi

# --- Cleanup and update repositories ---
info "cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*
apt-get -y update >/dev/null 2>&1 || true
ok "cleanup completed"

# --- Manual SSH key setup hint ---
warn "=============================================================="
warn "MANUAL SECTION"
warn "=============================================================="
info "--- SSH private key setup (run as ${USER_NAME}):"
info "mkdir -p \$HOME/.ssh && chmod 700 \$HOME/.ssh"
info "cat > \$HOME/.ssh/id_ed25519"
info "# paste key, then Ctrl-D"
info "chmod 600 \$HOME/.ssh/id_ed25519"
info "eval \"\$(ssh-agent -s)\" && ssh-add \$HOME/.ssh/id_ed25519"
if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
  info "--- Flameshot keyboard shortcut command:"
  info "script --command \"flameshot gui\" /dev/null"
fi
warn "=============================================================="

END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
info "done: $(date -Is)"
info "elapsed: $(printf '%02d:%02d:%02d' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))")"
info "log file: ${LOG_FILE}"
info "run_id: ${RUN_ID}"
info "================= RUN END ================="

echo "################################"
echo "# Customize System Complete"
echo "[customize-system] rebooting in 5 seconds ..."
echo "################################"
sleep 5
sync
shutdown -r now
