#!/bin/bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "❌ Do not run this as root. Run as your regular user."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLETS_DIR="${HOME}/.config/containers/systemd"

mkdir -p "${QUADLETS_DIR}"
sudo mkdir -p /mnt/podman
sudo chown -R "${USER}:${USER}" /mnt/podman
loginctl enable-linger "${USER}"

installed_apps=()

for app_dir in "${SCRIPT_DIR}"/apps/*; do
  [[ -d "${app_dir}" ]] || continue
  app_name="$(basename "${app_dir}")"
  echo "📦 Installing app: ${app_name}"

  containers_src="${app_dir}/containers"
  if [[ -d "${containers_src}" ]]; then
    target_dir="/mnt/podman/${app_name}/containers"
    mkdir -p "${target_dir}"
    for file in "${containers_src}"/*; do
      [[ -f "${file}" ]] || continue
      file_name="$(basename "${file}")"
      file_abs="$(readlink -f "${file}")"
      ln -sf "${file_abs}" "${target_dir}/${file_name}"
      echo "  🔗 Linked container def: ${file_name} → ${target_dir}"
    done
  fi

  quadlets_src="${app_dir}/quadlets"
  if [[ -d "${quadlets_src}" ]]; then
    for file in "${quadlets_src}"/*; do
      [[ -f "${file}" ]] || continue
      file_name="$(basename "${file}")"
      file_abs="$(readlink -f "${file}")"
      ln -sf "${file_abs}" "${QUADLETS_DIR}/${file_name}"
      echo "  🔗 Linked quadlet: ${file_name} → ${QUADLETS_DIR}"
    done
  fi

  installed_apps+=("${app_name}")
done

echo ""
echo "🔄 Reloading systemd daemon..."
systemctl --user daemon-reload

echo ""
for app_name in "${installed_apps[@]}"; do
  echo "🚀 Deploying ${app_name}..."
  systemctl --user enable --now "${app_name}" 2>/dev/null || systemctl --user restart "${app_name}"
done

echo ""
echo "✅ All apps installed and deployed."
