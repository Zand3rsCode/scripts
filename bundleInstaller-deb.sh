#!/usr/bin/env bash
set -Eeuo pipefail

# Interactive bootstrap installer for Debian 12/13
# Installs selected tools:
# - Oh My Bash
# - Docker Engine
# - Docker Compose plugin
# - Tailscale
# - btop

if [[ "${EUID}" -eq 0 ]]; then
  echo "Please run this script as a normal sudo-capable user, not root."
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "Cannot detect operating system."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

major_version="${VERSION_ID%%.*}"
codename="${VERSION_CODENAME:-}"

if [[ "${ID:-}" != "debian" ]]; then
  echo "This script is intended for Debian."
  echo "Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

if [[ ! "$major_version" =~ ^[0-9]+$ ]]; then
  echo "Unable to parse Debian version."
  echo "Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

if [[ "$major_version" -ne 12 && "$major_version" -ne 13 ]]; then
  echo "This script supports Debian 12 (bookworm) and Debian 13 (trixie) only."
  echo "Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

if [[ "$codename" != "bookworm" && "$codename" != "trixie" ]]; then
  echo "Unsupported Debian codename: ${codename:-unknown}"
  echo "Expected: bookworm or trixie"
  exit 1
fi

SUDO=""
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo "sudo is required."
  exit 1
fi

ask_yes_no() {
  local prompt="$1"
  local reply
  while true; do
    read -r -p "$prompt [y/N]: " reply < /dev/tty
    case "$reply" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]|"") return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_updated=0
apt_update_once() {
  if [[ "$apt_updated" -eq 0 ]]; then
    echo "Updating APT package index..."
    $SUDO apt-get update
    apt_updated=1
  fi
}

install_apt_packages() {
  local packages=("$@")
  apt_update_once
  echo "Installing: ${packages[*]}"
  $SUDO apt-get install -y "${packages[@]}"
}

docker_repo_configured=0
configure_docker_repo() {
  if [[ "$docker_repo_configured" -eq 1 ]]; then
    return 0
  fi

  echo "Configuring official Docker repository..."
  install_apt_packages ca-certificates curl gnupg

  $SUDO install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
      $SUDO tee /etc/apt/keyrings/docker.asc >/dev/null
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc
  fi

  cat <<EOF | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${codename} stable
EOF

  apt_updated=0
  docker_repo_configured=1
}

tailscale_repo_configured=0
configure_tailscale_repo() {
  if [[ "$tailscale_repo_configured" -eq 1 ]]; then
    return 0
  fi

  echo "Configuring official Tailscale repository..."
  install_apt_packages ca-certificates curl

  $SUDO mkdir -p --mode=0755 /usr/share/keyrings

  if [[ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]]; then
    curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" | \
      $SUDO tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  fi

  curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" | \
    $SUDO tee /etc/apt/sources.list.d/tailscale.list >/dev/null

  apt_updated=0
  tailscale_repo_configured=1
}

docker_installed() {
  dpkg -s docker-ce >/dev/null 2>&1
}

compose_installed() {
  dpkg -s docker-compose-plugin >/dev/null 2>&1
}

tailscale_installed() {
  dpkg -s tailscale >/dev/null 2>&1
}

btop_installed() {
  dpkg -s btop >/dev/null 2>&1
}

omb_user_installed() {
  [[ -d "$HOME/.oh-my-bash" ]]
}

omb_root_installed() {
  $SUDO test -d /root/.oh-my-bash
}

echo "Debian ${major_version} interactive bootstrap (${codename})"
echo

install_omb=0
install_docker=0
install_compose=0
install_tailscale=0
install_btop=0

if ask_yes_no "Install Oh My Bash?"; then
  install_omb=1
fi
if ask_yes_no "Install Docker Engine?"; then
  install_docker=1
fi
if ask_yes_no "Install Docker Compose plugin?"; then
  install_compose=1
fi
if ask_yes_no "Install Tailscale?"; then
  install_tailscale=1
fi
if ask_yes_no "Install btop?"; then
  install_btop=1
fi

echo
echo "Selections:"
[[ "$install_omb" -eq 1 ]] && echo "- Oh My Bash"
[[ "$install_docker" -eq 1 ]] && echo "- Docker Engine"
[[ "$install_compose" -eq 1 ]] && echo "- Docker Compose plugin"
[[ "$install_tailscale" -eq 1 ]] && echo "- Tailscale"
[[ "$install_btop" -eq 1 ]] && echo "- btop"

if [[ "$install_omb" -eq 0 && "$install_docker" -eq 0 && "$install_compose" -eq 0 && "$install_tailscale" -eq 0 && "$install_btop" -eq 0 ]]; then
  echo "Nothing selected. Exiting."
  exit 0
fi

echo

if [[ "$install_omb" -eq 1 ]]; then
  echo "Preparing Oh My Bash..."
  missing=()
  need_cmd curl || missing+=("curl")
  need_cmd git || missing+=("git")

  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Oh My Bash requires: ${missing[*]}"
    if ask_yes_no "Install missing requirements for Oh My Bash now?"; then
      install_apt_packages "${missing[@]}"
    else
      echo "Skipping Oh My Bash because requirements were not installed."
      install_omb=0
    fi
  fi
fi

if [[ "$install_docker" -eq 1 || "$install_compose" -eq 1 ]]; then
  configure_docker_repo
fi

if [[ "$install_docker" -eq 1 ]]; then
  if docker_installed; then
    echo "Docker Engine already installed. Skipping."
  else
    echo "Installing Docker Engine..."
    apt_update_once
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    $SUDO systemctl enable --now docker

    if getent group docker >/dev/null 2>&1; then
      $SUDO /usr/sbin/usermod -aG docker "$USER" || true
    fi
  fi
fi

if [[ "$install_compose" -eq 1 ]]; then
  if compose_installed; then
    echo "Docker Compose plugin already installed. Skipping."
  else
    echo "Installing Docker Compose plugin..."
    apt_update_once
    $SUDO apt-get install -y docker-compose-plugin
  fi
fi

if [[ "$install_tailscale" -eq 1 ]]; then
  if tailscale_installed; then
    echo "Tailscale already installed. Skipping."
  else
    configure_tailscale_repo
    echo "Installing Tailscale..."
    apt_update_once
    $SUDO apt-get install -y tailscale
    $SUDO systemctl enable --now tailscaled
  fi
fi

if [[ "$install_btop" -eq 1 ]]; then
  if btop_installed; then
    echo "btop already installed. Skipping."
  else
    echo "Installing btop..."
    install_apt_packages btop
  fi
fi

if [[ "$install_omb" -eq 1 ]]; then
  if omb_user_installed; then
    echo "Oh My Bash already installed for user. Skipping."
  else
    echo "Installing Oh My Bash for user..."
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended
  fi

  if ask_yes_no "Install Oh My Bash for root as well?"; then
    if omb_root_installed; then
      echo "Oh My Bash already installed for root. Skipping."
    else
      echo "Installing Oh My Bash for root..."
      $SUDO env HOME=/root bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" --unattended
    fi
  fi
fi

echo
echo "Done."
echo

if [[ "$install_docker" -eq 1 || "$install_compose" -eq 1 ]]; then
  echo "Docker note: log out and back in before using Docker without sudo."
fi

if [[ "$install_tailscale" -eq 1 ]]; then
  echo "Tailscale note: sign in with: sudo tailscale up"
fi

if [[ "$install_omb" -eq 1 ]]; then
  echo "Oh My Bash note: restart your shell or run: source ~/.bashrc"
fi
