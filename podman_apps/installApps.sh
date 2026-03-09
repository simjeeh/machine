#!/bin/bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "❌ Do not run this as root. Run as your regular user."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLETS_DIR="${HOME}/.config/containers/systemd"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

link_files() {
  local src_dir="$1"
  local target_dir="$2"
  local label="$3"

  [[ -d "${src_dir}" ]] || return 0

  mkdir -p "${target_dir}"
  for file in "${src_dir}"/*; do
    [[ -f "${file}" ]] || continue
    file_name="$(basename "${file}")"
    file_abs="$(readlink -f "${file}")"
    ln -sf "${file_abs}" "${target_dir}/${file_name}"
    echo "  🔗 Linked ${label}: ${file_name} → ${target_dir}"
  done
}

mkdir -p "${QUADLETS_DIR}"
mkdir -p "${SYSTEMD_USER_DIR}"
sudo mkdir -p /mnt/podman
sudo chown -R "${USER}:${USER}" /mnt/podman
loginctl enable-linger "${USER}"

installed_apps=()

for app_dir in "${SCRIPT_DIR}"/apps/*; do
  [[ -d "${app_dir}" ]] || continue
  app_name="$(basename "${app_dir}")"
  echo "📦 Installing app: ${app_name}"

  link_files "${app_dir}/containers" "/mnt/podman/${app_name}/containers" "container def"
  link_files "${app_dir}/quadlets"   "${QUADLETS_DIR}"                    "quadlet"
  link_files "${app_dir}/systemd"    "${SYSTEMD_USER_DIR}"                "systemd unit"
  link_files "${app_dir}/scripts"    "/mnt/podman/${app_name}"            "script"
  link_files "${app_dir}/config"     "/mnt/podman/${app_name}/config"     "config file"

  installed_apps+=("${app_name}")
done

echo ""
echo "🔄 Reloading systemd daemon..."
systemctl --user daemon-reload

echo ""
for app_name in "${installed_apps[@]}"; do
  manage_secrets="/mnt/podman/${app_name}/manageSecrets.sh"
  if [[ -f "${manage_secrets}" ]]; then
    echo "🔑 Checking secrets for ${app_name}..."
    "${manage_secrets}" --check
  fi

  echo "🚀 Deploying ${app_name}..."
  systemctl --user enable --now "${app_name}" 2>/dev/null || systemctl --user restart "${app_name}"

  init_service="${SYSTEMD_USER_DIR}/${app_name}-init.service"
  if [[ -f "${init_service}" ]]; then
    echo "⚙️  Starting init service for ${app_name}..."
    systemctl --user enable "${app_name}-init"
    systemctl --user start "${app_name}-init" &
  fi

  prune_timer="${SYSTEMD_USER_DIR}/${app_name}-prune.timer"
  if [[ -f "${prune_timer}" ]]; then
    echo "🗑️  Enabling prune timer for ${app_name}..."
    systemctl --user enable --now "${app_name}-prune.timer" 2>/dev/null || true
  fi
done

echo ""
echo "✅ All apps installed and deployed."
