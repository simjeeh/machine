#!/usr/bin/env bash
set -euo pipefail

# Function to check for existing secret and optionally overwrite
create_or_overwrite_secret() {
  local secret_name="$1"
  local prompt="$2"

  if podman secret inspect "${secret_name}" &>/dev/null; then
    read -r -p "Secret '${secret_name}' already exists. Overwrite? (y/N): " choice
    case "$choice" in
      [yY][eE][sS]|[yY])
        podman secret rm "${secret_name}" >/dev/null
        ;;
      *)
        echo "Skipping ${secret_name}"
        return
        ;;
    esac
  fi

  read -r -p "${prompt}: " value
  echo -n "${value}" | podman secret create "${secret_name}" -
  echo "Created secret: ${secret_name}"
}

create_or_overwrite_secret "vpn_downloader_vpn_user" "Enter VPN username"
create_or_overwrite_secret "vpn_downloader_vpn_password" "Enter VPN password"
create_or_overwrite_secret "vpn_downloader_transmission_rpc_username" "Enter Transmission RPC username"
create_or_overwrite_secret "vpn_downloader_transmission_rpc_password" "Enter Transmission RPC password"

echo "✅ All secrets processed."
