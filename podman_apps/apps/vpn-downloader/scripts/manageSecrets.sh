#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "📦 jq not found, installing..."
  sudo apt install -y jq
  echo "✅ jq installed"
fi

SECRETS_DIR="/mnt/podman/vpn-downloader/secrets"
SECRETS_FILE="${SECRETS_DIR}/secrets.yaml"
mkdir -p ${SECRETS_DIR}

# --check mode: skip if secrets file already exists
if [[ "${1:-}" == "--check" ]]; then
  if [[ -f "${SECRETS_FILE}" ]]; then
    echo "  ✅ Secrets already exist, skipping"
    exit 0
  fi
  echo "  ⚠️  Secrets not found, prompting for input..."
fi

read -r -p "Enter VPN username (Private Internet Access in Bitwarden): " vpn_user
read -r -p "Enter VPN password (Private Internet Access in Bitwarden): " vpn_password
read -r -p "Enter Transmission RPC password (Transmission in Bitwarden): " transmission_password

cat > "${SECRETS_FILE}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vpn-downloader-secrets
data:
  OPENVPN_USER: $(echo -n "${vpn_user}" | base64 -w 0)
  OPENVPN_PASSWORD: $(echo -n "${vpn_password}" | base64 -w 0)
  TRANSMISSION_RPC_PASSWORD: $(echo -n "${transmission_password}" | base64 -w 0)
EOF

chmod 600 "${SECRETS_FILE}"
echo "✅ Secrets written to ${SECRETS_FILE}"
