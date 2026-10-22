#!/bin/bash
# Sets up orca (Fedora KDE). Safe to re-run: each step checks what's already done.
# Run as yourself with sudo, since several steps need to know your user: sudo bash fedora-setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

step()  { echo -e "\n${CYAN}${BOLD}▶ $*${RESET}"; }
ok()    { echo -e "${GREEN}✔ $*${RESET}"; }
warn()  { echo -e "${YELLOW}⚠ $*${RESET}"; }
die()   { echo -e "${RED}✘ $*${RESET}" >&2; exit 1; }

# Runs a command as you rather than root, with your home directory.
as_user() { sudo -u "${SUDO_USER}" -H "$@"; }

# Swaps package $1 for $2, but only while $1 is still installed, so re-runs don't fail.
swap_if_installed() {
  if rpm -q "$1" &>/dev/null; then
    dnf swap -y "$1" "$2" --allowerasing
  else
    ok "$2 already in place"
  fi
}

# set_ini <file> <section> <key> <value>: sets the key in place, leaving the rest of
# the file alone. Returns 1 if unchanged, so call it from an `if` or set -e kills us.
set_ini() {
  local file=$1 section=$2 key=$3 value=$4 tmp
  [[ -f ${file} ]] || : > "${file}"
  tmp=$(mktemp)
  awk -v sec="[${section}]" -v key="${key}" -v value="${value}" '
    BEGIN { in_sec = 0; seen_sec = 0; done = 0 }
    # Leaving our section without having written the key means it was missing,
    # so emit it here before moving on.
    /^[[:space:]]*\[/ {
      if (in_sec && !done) { print key " = " value; done = 1 }
      in_sec = ($0 ~ "^[[:space:]]*\\" sec "[[:space:]]*$")
      if (in_sec) seen_sec = 1
      print; next
    }
    {
      if (in_sec && !done && $0 ~ "^[[:space:]]*#?[[:space:]]*" key "[[:space:]]*=") {
        print key " = " value; done = 1; next
      }
      print
    }
    END {
      if (!done) {
        if (!seen_sec) { print ""; print sec }
        print key " = " value
      }
    }
  ' "${file}" > "${tmp}"

  if cmp -s "${file}" "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  cat "${tmp}" > "${file}"   # cat, not mv, so ownership and SELinux context survive
  rm -f "${tmp}"
  return 0
}

# ── Preflight ─────────────────────────────────────────────────────────────────
(( EUID == 0 )) || die "Run this script with sudo:  sudo bash ${0}"
[[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]] || die "Run it with sudo from your own account, not as root"
USER_HOME="/home/${SUDO_USER}"

FEDORA_VER=$(rpm -E %fedora)
ok "Detected Fedora ${FEDORA_VER}, setting up for ${SUDO_USER}"

# =============================================================================
# 1. DNF speed
# =============================================================================
step "Configuring DNF for parallel downloads"
if grep -q '^max_parallel_downloads=' /etc/dnf/dnf.conf; then
  sed -i 's/^max_parallel_downloads=.*/max_parallel_downloads=10/' /etc/dnf/dnf.conf
else
  sed -i '/^\[main\]/a max_parallel_downloads=10' /etc/dnf/dnf.conf
fi
ok "max_parallel_downloads=10"

# =============================================================================
# 2. Repositories (before the upgrade, so it covers their packages too)
# =============================================================================
step "Enabling RPM Fusion (free + nonfree)"
if rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null; then
  ok "RPM Fusion already enabled"
else
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
  ok "RPM Fusion enabled"
fi

step "Adding the VSCodium repository"
# Written whole each run (not appended), so re-runs don't duplicate it.
cat > /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF
ok "VSCodium repository ready"

step "Adding Flathub"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flathub ready"

# =============================================================================
# 3. System upgrade
# =============================================================================
step "Upgrading the system"
dnf upgrade --refresh -y
ok "System is up to date"

# =============================================================================
# 4. Multimedia codecs
# =============================================================================
step "Installing multimedia codecs"
swap_if_installed ffmpeg-free ffmpeg
dnf group install -y multimedia
dnf upgrade -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
swap_if_installed mesa-va-drivers mesa-va-drivers-freeworld
swap_if_installed mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
ok "Multimedia codecs installed"

# =============================================================================
# 5. Firmware
# =============================================================================
step "Checking for firmware updates"
fwupdmgr refresh --force &>/dev/null || true
fwupdmgr update -y || warn "No firmware updates applied (none available, or fwupd unavailable)"
ok "Firmware check complete"

# =============================================================================
# 6. Software
# =============================================================================
step "Installing DNF packages"
# rsync is for upload-media; ethtool is for the Tailscale NIC tweak below.
dnf install -y \
  akmod-nvidia \
  xorg-x11-drv-nvidia-cuda \
  podman \
  codium \
  awscli2 \
  expect \
  rsync \
  ethtool
ok "DNF packages installed"

step "Installing Flatpak applications"
flatpak install -y --noninteractive flathub \
  com.brave.Browser \
  com.spotify.Client \
  com.sublimehq.SublimeText \
  io.ente.photos \
  org.darktable.Darktable \
  org.signal.Signal \
  org.videolan.VLC \
  org.localsend.localsend_app
ok "Flatpak applications installed"

step "Adding the scripts folder to your PATH"
# \$PATH stays literal, so your shell expands it at login instead of baking in root's PATH now.
path_line="export PATH=\"${SCRIPT_DIR}/scripts:\$PATH\""
if grep -qxF "${path_line}" "${USER_HOME}/.bashrc"; then
  ok "Already in ${USER_HOME}/.bashrc"
else
  echo "${path_line}" >> "${USER_HOME}/.bashrc"
  ok "Added to ${USER_HOME}/.bashrc (open a new terminal to use it)"
fi

step "Configuring AWS CLI profiles"
for profile in default simjeez; do
  if grep -qs "^\[${profile}\]" "${USER_HOME}/.aws/credentials"; then
    ok "AWS profile '${profile}' already configured"
  else
    as_user aws configure --profile "${profile}"
    ok "AWS profile '${profile}' configured"
  fi
done

# =============================================================================
# 7. Hostname
# =============================================================================
step "Setting the hostname to orca"
hostnamectl set-hostname orca
ok "Hostname is orca"

# =============================================================================
# 8. Bluetooth (fast keyboard reconnects)
# =============================================================================
# AutoEnable powers the adapter at boot instead of waiting for Plasma; without it the
# Keychron sits unconnected for ~25s. FastConnectable speeds up waking it from idle.
step "Tuning Bluetooth for fast keyboard reconnects"
BT_CONF=/etc/bluetooth/main.conf
if ! rpm -q bluez &>/dev/null; then
  warn "bluez isn't installed, skipping Bluetooth tuning"
else
  bt_changed=0
  if set_ini "${BT_CONF}" General FastConnectable true; then bt_changed=1; fi
  if set_ini "${BT_CONF}" Policy  AutoEnable      true; then bt_changed=1; fi

  systemctl enable bluetooth.service &>/dev/null || true

  if (( bt_changed )); then
    warn "Restarting bluetooth, your keyboard will drop for a second"
    systemctl restart bluetooth.service
    ok "FastConnectable and AutoEnable set in ${BT_CONF}"
  else
    ok "Bluetooth already tuned"
  fi
fi

# =============================================================================
# 9. Tailscale
# =============================================================================
step "Installing and configuring Tailscale"
if command -v tailscale &>/dev/null; then
  ok "Tailscale already installed"
else
  curl -fsSL https://tailscale.com/install.sh | sh
fi
systemctl enable --now tailscaled

# Forwarding is needed to advertise a route. Written whole, so re-runs don't add duplicate lines.
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' > /etc/sysctl.d/99-tailscale.conf
sysctl -q -p /etc/sysctl.d/99-tailscale.conf

# Tailscale's recommended UDP tweak for forwarding. Fedora uses NetworkManager, so a
# dispatcher script reapplies it whenever the interface comes up.
NETDEV=$(ip -o route get 8.8.8.8 | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}')
ethtool -K "${NETDEV}" rx-udp-gro-forwarding on rx-gro-list off
cat > /etc/NetworkManager/dispatcher.d/50-tailscale-gro << EOF
#!/bin/sh
[ "\$1" = "${NETDEV}" ] && [ "\$2" = "up" ] && ethtool -K "${NETDEV}" rx-udp-gro-forwarding on rx-gro-list off
exit 0
EOF
chmod 755 /etc/NetworkManager/dispatcher.d/50-tailscale-gro
rm -f /etc/networkd-dispatcher/routable.d/50-tailscale

# "tailscale up" logs in if needed; "set" changes the route on a machine that's already logged in.
LOCAL_IP=$(hostname -I | awk '{print $1}')
if tailscale status &>/dev/null; then
  tailscale set --advertise-routes="${LOCAL_IP}/32"
else
  tailscale up --advertise-routes="${LOCAL_IP}/32"
fi
ok "Tailscale configured (route ${LOCAL_IP}/32 advertised)"
warn "Approve the route at login.tailscale.com/admin/machines if it's new"

# =============================================================================
# 10. Podman apps (as you, in your own user session)
# =============================================================================
step "Installing Podman apps"
USER_ID=$(id -u "${SUDO_USER}")
as_user env XDG_RUNTIME_DIR="/run/user/${USER_ID}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
  bash "${SCRIPT_DIR}/podman/installApps.sh"
ok "Podman apps installed"

# =============================================================================
# 11. Cleanup
# =============================================================================
step "Removing unwanted KDE packages"
BLOAT=(
  dragon elisa-player kaddressbook kaddressbook-libs kamoso kcalc kcalutils kdeconnectd
  kmahjongg kmailtransport kmines kmouth kpat krdc krdc-libs krdp krdp-libs krfb krfb-libs
  kwalletmanager5 kwrite neochat xwaylandvideobridge gnome-abrt filelight
)
TO_REMOVE=()
for pkg in "${BLOAT[@]}"; do
  rpm -q "${pkg}" &>/dev/null && TO_REMOVE+=("${pkg}")
done
if (( ${#TO_REMOVE[@]} )); then
  dnf remove -y "${TO_REMOVE[@]}"
  ok "Removed ${#TO_REMOVE[@]} package(s)"
else
  ok "Nothing to remove"
fi
dnf autoremove -y
dnf clean all
ok "System cleaned up"

# =============================================================================
# Done
# =============================================================================
echo -e "\n${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   Fedora setup complete!  Reboot now.    ║"
echo -e "╚══════════════════════════════════════════╝${RESET}\n"
warn "Reboot so the NVIDIA driver and any firmware updates take effect."
