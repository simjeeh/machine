#!/bin/bash

# --- Require root ---
if [[ ${EUID} -ne 0 ]]; then
  echo "❌ This script must be run as root."
  echo "💡 Try: sudo $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER_DIR="$(getent passwd "${SUDO_USER}" | cut -d: -f6)/.config/systemd/user"
sudo -u "${SUDO_USER}" mkdir -p ${SYSTEMD_USER_DIR}

for app_dir in "${SCRIPT_DIR}"/apps/*; do
  app_name="$(basename "${app_dir}")"
  echo "Installing app: ${app_name}"
  
  containers_dir="${app_dir}/containers"
  if [[ -d "${containers_dir}" ]]; then
    target_opt="/opt/${app_name}"
    sudo mkdir -p "${target_opt}"
    for script in "${containers_dir}"/*; do
      if [[ -f "${script}" ]]; then
        script_name=$(basename "${script}")
	      script_abs="$(readlink -f "${script}")"
        sudo ln -sf "${script_abs}" "${target_opt}/${script_name}"
        chmod +x "${target_opt}/${script_name}"
        echo "  Linked container script: ${script_name} -> ${target_opt}"
      fi
    done
  fi

  systemd_dir="${app_dir}/systemd"
  if [[ -d "${systemd_dir}" ]]; then
    for service in "${systemd_dir}"/*; do
      if [[ -f "${service}" ]]; then
        service_name=$(basename "${service}")
        service_abs="$(readlink -f "${service}")"
        sudo ln -sf "${service_abs}" ${SYSTEMD_USER_DIR}/${service_name}
        echo "  Linked systemd unit: ${service_name} -> ${SYSTEMD_USER_DIR}"
      fi
    done
  fi
done

echo "To reload systemd daemon, run:"
echo "  systemctl --user daemon-reload"
