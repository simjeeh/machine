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

if [[ ! -d /mnt/podman ]]; then
  echo "❌ /mnt/podman does not exist. Please create it and mount your disk first."
  echo "💡 Run: sudo mkdir -p /mnt/podman && sudo mount /dev/sdX1 /mnt/podman"
  exit 1
fi

if [[ ! -w /mnt/podman ]]; then
  echo "❌ /mnt/podman is not writable by ${USER}."
  echo "💡 Run: sudo chown -R ${USER}:${USER} /mnt/podman"
  exit 1
fi

mkdir -p "${QUADLETS_DIR}"
mkdir -p "${SYSTEMD_USER_DIR}"
loginctl enable-linger "${USER}"

installed_apps=()

for app_dir in "${SCRIPT_DIR}"/apps/*; do
  [[ -d "${app_dir}" ]] || continue
  app_name="$(basename "${app_dir}")"
  echo "📦 Installing app: ${app_name}"

  mkdir -p "/mnt/podman/${app_name}"

  data_dirs_file="${app_dir}/.data-dirs"
  if [[ -f "${data_dirs_file}" ]]; then
    while IFS= read -r subdir || [[ -n "${subdir}" ]]; do
      [[ -z "${subdir}" || "${subdir}" =~ ^# ]] && continue
      mkdir -p "/mnt/podman/${app_name}/.data/${subdir}"
      echo "  📁 Created data dir: /mnt/podman/${app_name}/.data/${subdir}"
    done < "${data_dirs_file}"
  fi

  link_files "${app_dir}/containers" "/mnt/podman/${app_name}/containers" "container def"
  link_files "${app_dir}/quadlets"   "${QUADLETS_DIR}"                    "quadlet"
  link_files "${app_dir}/systemd"    "${SYSTEMD_USER_DIR}"                "systemd unit"
  link_files "${app_dir}/scripts"    "/mnt/podman/${app_name}/scripts"    "script"
  link_files "${app_dir}/config"     "/mnt/podman/${app_name}/config"     "config file"

  installed_apps+=("${app_name}")
done

echo ""
echo "🔄 Reloading systemd daemon..."
systemctl --user daemon-reload

echo ""
for app_name in "${installed_apps[@]}"; do
  manage_secrets="/mnt/podman/${app_name}/scripts/manageSecrets.sh"
  if [[ -f "${manage_secrets}" ]]; then
    echo "🔑 Checking secrets for ${app_name}..."
    "${manage_secrets}" --check
  fi

  echo "🚀 Deploying ${app_name}..."
  for quadlet in "${SCRIPT_DIR}/apps/${app_name}/quadlets"/*; do
    [[ -f "${quadlet}" ]] || continue
    unit_name="$(basename "${quadlet}")"
    unit_name="${unit_name%.*}"
    ext="${quadlet##*.}"
    case "${ext}" in
      pod)       service="${unit_name}-pod.service" ;;
      container) service="${unit_name}.service" ;;
      kube)      service="${unit_name}.service" ;;
      *)         continue ;;
    esac
    echo "  ▶️  Enabling ${service}..."
    systemctl --user enable --now "${service}" 2>/dev/null || systemctl --user restart "${service}" 2>/dev/null || true
  done

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
