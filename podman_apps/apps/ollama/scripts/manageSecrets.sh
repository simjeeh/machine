#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo "📦 jq not found, installing..."
  sudo dnf install -y jq
  echo "✅ jq installed"
fi

create_or_overwrite_secret() {
  local secret_name="$1"
  local prompt="$2"

  if podman secret inspect "${secret_name}" &>/dev/null; then
    if [[ "${CHECK_MODE}" == "true" ]]; then
      echo "  ✅ Secret '${secret_name}' already exists, skipping"
      return
    fi
    read -r -p "Secret '${secret_name}' already exists. Overwrite? (y/N): " choice
    case "$choice" in
      [yY][eE][sS]|[yY]) podman secret rm "${secret_name}" >/dev/null ;;
      *) echo "Skipping ${secret_name}"; return ;;
    esac
  fi

  read -r -s -p "${prompt}: " value
  echo
  echo -n "${value}" | podman secret create "${secret_name}" -
  echo "  ✅ Created secret: ${secret_name}"
}

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
  CHECK_MODE=true
fi

if [[ "${CHECK_MODE}" == "true" ]]; then
  if podman secret inspect ollama-webui-email &>/dev/null && \
     podman secret inspect ollama-webui-password &>/dev/null; then
    echo "  ✅ Secrets already exist, skipping"
    exit 0
  fi
  echo "  ⚠️  Secrets not found, prompting for input..."
fi

create_or_overwrite_secret "ollama-webui-email" "Enter Open WebUI admin email (Ollama in BitWarden)"
create_or_overwrite_secret "ollama-webui-password" "Enter Open WebUI admin password (Ollama in BitWarden)"

echo "✅ All secrets processed."
