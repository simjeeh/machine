#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "📦 jq not found, installing..."
  sudo apt install -y jq
  echo "✅ jq installed"
fi

SECRETS_DIR="/mnt/podman/ollama/secrets"
SECRETS_FILE="${SECRETS_DIR}/secrets.yaml"
mkdir -p "${SECRETS_DIR}"

if [[ "${1:-}" == "--check" ]]; then
  if [[ -f "${SECRETS_FILE}" ]]; then
    echo "  ✅ Secrets already exist, skipping"
    exit 0
  fi
  echo "  ⚠️  Secrets not found, prompting for input..."
fi

read -r -p "Enter Open WebUI admin email (Ollama in Bitwarden): " admin_email
read -r -p "Enter Open WebUI admin password (Ollama in Bitwarden): " admin_password

cat > "${SECRETS_FILE}" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ollama-secrets
data:
  WEBUI_ADMIN_EMAIL: $(echo -n "${admin_email}" | base64 -w 0)
  WEBUI_ADMIN_PASSWORD: $(echo -n "${admin_password}" | base64 -w 0)
EOF

chmod 600 "${SECRETS_FILE}"
echo "✅ Secrets written to ${SECRETS_FILE}"
