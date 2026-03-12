#!/bin/bash
set -euo pipefail

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

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ ${EUID} -ne 0 ]] && die "Run this script with sudo:  sudo bash ${0}"

FEDORA_VER=$(rpm -E %fedora)
ok "Detected Fedora ${FEDORA_VER}"

# =============================================================================
# 1. Maximise DNF5 Speed
# =============================================================================
step "Configuring DNF5 for maximum parallel downloads"

modifyDnfConfParameter() {
    local dnf_conf="/etc/dnf/dnf.conf"
    local key="$1"
    local value="$2"
    if grep -q "^${key}" "${dnf_conf}"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "${dnf_conf}"
        ok "Updated ${key}=${value} in ${dnf_conf}"
    else
        sed -i "/^\[main\]/a ${key}=${value}" "${dnf_conf}"
        ok "Added ${key}=${value} to ${dnf_conf}"
    fi
}
modifyDnfConfParameter max_parallel_downloads 10

# =============================================================================
# 2. System Update
# =============================================================================
step "Performing full system upgrade"
dnf upgrade --refresh -y
ok "System is up to date"

# =============================================================================
# 3. RPM Fusion Repositories
# =============================================================================
step "Enabling RPM Fusion (free + nonfree)"
dnf check-update || true   # non-zero exit is normal when updates exist
dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
ok "RPM Fusion repositories enabled"

# =============================================================================
# 4. Flatpak & Flathub
# =============================================================================
step "Enabling Flatpak and adding Flathub remote"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
ok "Flathub remote ready"

# =============================================================================
# 5. Essential Multimedia Codecs
# =============================================================================
step "Installing multimedia codecs"

dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf group install -y multimedia
dnf upgrade -y @multimedia \
    --setopt="install_weak_deps=False" \
    --exclude=PackageKit-gstreamer-plugin
dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
ok "Multimedia codecs installed"

# =============================================================================
# 6. Firmware Updates
# =============================================================================
step "Checking and applying firmware updates"
fwupdmgr get-updates -y || warn "No firmware updates found (or fwupd unavailable)"
fwupdmgr update -y || warn "Firmware update step skipped"
ok "Firmware check complete"

# =============================================================================
# 7. Software Installation
# =============================================================================

# ── DNF packages ──────────────────────────────────────────────────────────────
step "Installing DNF packages (NVIDIA drivers + Podman)"
dnf install -y \
    akmod-nvidia \
    xorg-x11-drv-nvidia-cuda \
    podman
ok "DNF packages installed"

# ── Flatpak apps ─────────────────────────────────────────────────────────────
step "Installing Flatpak applications from Flathub"
flatpak install -y \
    flathub \
    com.brave.Browser \
    com.spotify.Client \
    com.sublimehq.SublimeText \
    com.visualstudio.code \
    io.ente.photos \
    org.darktable.Darktable \
    org.signal.Signal \
    org.videolan.VLC
ok "Flatpak applications installed"

# =============================================================================
# 8. Tailscale
# =============================================================================
step "Installing and configuring Tailscale"

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# Optimise NIC for Tailscale subnet routing (persists via networkd-dispatcher)
NETDEV=$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")
ethtool -K "${NETDEV}" rx-udp-gro-forwarding on rx-gro-list off
 
mkdir -p /etc/networkd-dispatcher/routable.d/
printf '#!/bin/sh\n\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off\n' "${NETDEV}" \
    | tee /etc/networkd-dispatcher/routable.d/50-tailscale
chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale

# Bring Tailscale up and advertise this machine's IP.
# This config persists across reboots — no need for a separate systemd unit.
LOCAL_IP=$(hostname -I | awk '{print $1}')
tailscale up --advertise-routes="${LOCAL_IP}/32"

ok "Tailscale configured (route ${LOCAL_IP}/32 advertised)"
warn "Remember to approve the subnet route at login.tailscale.com/admin/machines"

# =============================================================================
# 10. Podman Apps (run as original user)
# =============================================================================
step "Installing Podman apps"
 
# SUDO_USER is set automatically when the script is invoked with sudo
if [[ -z "${SUDO_USER:-}" ]]; then
    warn "Could not determine original user — skipping Podman apps"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    USER_ID=$(id -u "${SUDO_USER}")
    sudo -u "${SUDO_USER}" \
        XDG_RUNTIME_DIR="/run/user/${USER_ID}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus" \
        bash "${SCRIPT_DIR}/podman_apps/installApps.sh"
    ok "Podman apps installed"
fi

# =============================================================================
# 8. Cleanup — remove unwanted KDE/bloat packages
# =============================================================================
step "Removing bloatware"

BLOAT=(
    dragon
    elisa-player
    kaddressbook
    kaddressbook-libs
    kamoso
    kcalc
    kcalutils
    kdeconnectd
    kmahjongg
    kmailtransport
    kmines
    kmouth
    kpat
    krdc
    krdc-libs
    krdp
    krdp-libs
    krfb
    krfb-libs
    kwalletmanager5
    kwrite
    neochat
    xwaylandvideobridge
    gnome-abrt
    filelight
)

# Only attempt removal for packages that are actually installed
TO_REMOVE=()
for pkg in "${BLOAT[@]}"; do
    rpm -q "$pkg" &>/dev/null && TO_REMOVE+=("$pkg")
done

if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
    dnf remove -y "${TO_REMOVE[@]}"
    ok "Removed ${#TO_REMOVE[@]} bloat package(s)"
else
    ok "No bloat packages found — nothing to remove"
fi

dnf autoremove -y
dnf clean all
ok "System cleaned up"

# =============================================================================
# Done
# =============================================================================
echo -e "\n${GREEN}${BOLD}╔══════════════════════════════════════════╗"
echo -e "║   Fedora setup complete!  Reboot now.   ║"
echo -e "╚══════════════════════════════════════════╝${RESET}\n"
warn "A reboot is recommended so the NVIDIA kmod and any firmware updates take effect."
