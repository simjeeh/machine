#!/bin/bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "❌ Do not run this as root. Run as your regular user."
  exit 1
fi

cleanup() {
  echo ""
  echo "  🛑 Interrupted, cleaning up..."
  jobs -p | xargs -r kill 2>/dev/null || true
  rm -f /tmp/podman-pull-*.log /tmp/podman-exit-*
  [[ -n "${PULL_REGISTRY_DIR:-}" ]] && rm -rf "${PULL_REGISTRY_DIR}"
  # Leave PULL_LOG intact so you can review it after interruption
  echo "  📋 Pull log preserved at: ${PULL_LOG:-<none>}"
  exit 1
}

trap cleanup SIGINT SIGTERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUADLETS_DIR="${HOME}/.config/containers/systemd"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"

# Shared pull tracking — written by install_app, read by the central reporter
PULL_LOG="/tmp/podman-install-pull-$$.log"
PULL_REGISTRY_DIR="$(mktemp -d /tmp/podman-pulls-XXXXXX)"

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

# Configuring NVIDIA CDI
mkdir -p "${HOME}/.config/cdi"
echo "🔧 Configuring NVIDIA CDI..."
if nvidia-ctk cdi generate --output="${HOME}/.config/cdi/nvidia.yaml" >/dev/null 2>&1; then
  echo "  ✅ NVIDIA CDI config generated successfully"
else
  echo "  ❌ Failed to generate NVIDIA CDI config"
fi

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
echo "📋 Pull progress log: tail -f ${PULL_LOG}"
echo ""

# ── Central reporter ──────────────────────────────────────────────────────────
# Runs in the background for the lifetime of the app loop.
# Every 30s it scans PULL_REGISTRY_DIR for active pulls and appends a status
# snapshot to PULL_LOG.  Each pull registers a file at:
#   ${PULL_REGISTRY_DIR}/<pid>  containing  "APP=<n>\nIMAGE=<image>\nLOG=<logfile>"
# and removes it when the pull completes.
(
  while true; do
    sleep 30
    entries=("${PULL_REGISTRY_DIR}"/*)
    # glob expands to the literal pattern string when the dir is empty
    [[ -e "${entries[0]}" ]] || continue

    echo "⏳ Still pulling ($(date '+%H:%M:%S')):" >>"${PULL_LOG}"
    for entry in "${entries[@]}"; do
      [[ -f "${entry}" ]] || continue
      local_pid="$(basename "${entry}")"
      # Skip if the pull process is no longer alive (race: not yet deregistered)
      kill -0 "${local_pid}" 2>/dev/null || continue

      app_name="$(grep '^APP='   "${entry}" | cut -d= -f2-)"
      image="$(grep    '^IMAGE=' "${entry}" | cut -d= -f2-)"
      log="$(grep      '^LOG='   "${entry}" | cut -d= -f2-)"

      clean="$(tr '\r' '\n' <"${log}" 2>/dev/null || true)"
      blobs_done="$(echo "${clean}" | grep 'Copying blob' | grep -v '|.*/s' \
        | grep -oP '[a-f0-9]{12}' | sort -u | wc -l | xargs || true)"
      latest_progress="$(echo "${clean}" \
        | grep -oP 'Copying blob [a-f0-9]+\s+\[.*?\]\s+[\d.]+\S+\s*/\s*[\d.]+\S+(\s*\|\s*[\d.]+\s*\S+)?' \
        | tail -1 || true)"

      if [[ -n "${latest_progress}" ]]; then
        bytes="$(echo "${latest_progress}" \
          | grep -oP '[\d.]+\S+\s*/\s*[\d.]+\S+(\s*\|\s*[\d.]+\s*\S+)?' || true)"
        echo "  [${app_name}] ${image}: ${blobs_done} blobs copied, current: ${bytes}" >>"${PULL_LOG}"
      else
        echo "  [${app_name}] ${image}: ${blobs_done} blobs copied" >>"${PULL_LOG}"
      fi
    done
  done
) &
reporter_pid=$!

# ── Per-app worker ────────────────────────────────────────────────────────────
install_app() {
  local app_name="$1"
  local app_dir="${SCRIPT_DIR}/apps/${app_name}"

  # Pull all images for this app in parallel, registering each with the
  # central reporter so it shows up in the shared PULL_LOG.
  local pull_pids=()
  declare -A pid_log pid_exit

  for quadlet in "${app_dir}/quadlets"/*; do
    [[ -f "${quadlet}" ]] || continue
    [[ "${quadlet##*.}" == "container" ]] || continue

    local image
    image="$(grep -i '^Image=' "${quadlet}" | cut -d'=' -f2- | tr -d '[:space:]')"
    [[ -z "${image}" ]] && continue

    local log exit_file
    log="$(mktemp /tmp/podman-pull-XXXXXX.log)"
    exit_file="$(mktemp /tmp/podman-exit-XXXXXX)"

    echo "  [${app_name}] ⬇️  Pulling ${image}..."
    (unbuffer podman pull "${image}" >"${log}" 2>&1; echo $? >"${exit_file}") &
    local pid=$!

    # Register with the central reporter
    printf 'APP=%s\nIMAGE=%s\nLOG=%s\n' "${app_name}" "${image}" "${log}" \
      >"${PULL_REGISTRY_DIR}/${pid}"

    pull_pids+=("${pid}")
    pid_log["${pid}"]="${log}"
    pid_exit["${pid}"]="${exit_file}"
  done

  # Wait for all pulls, deregistering each as it finishes
  local pull_failed=0
  for pid in "${pull_pids[@]+"${pull_pids[@]}"}"; do
    wait "${pid}" || true
    rm -f "${PULL_REGISTRY_DIR}/${pid}"   # deregister from central reporter

    local exit_code
    exit_code="$(cat "${pid_exit[${pid}]}" 2>/dev/null | tr -d '[:space:]')"
    [[ "${exit_code}" == "0" ]] || pull_failed=1
    rm -f "${pid_exit[${pid}]}" "${pid_log[${pid}]}"
  done

  if [[ ${#pull_pids[@]} -gt 0 ]]; then
    if [[ "${pull_failed}" -ne 0 ]]; then
      echo "  [${app_name}] ⚠️  One or more image pulls failed. Continuing anyway..."
    else
      echo "  [${app_name}] ✅ All images pulled."
    fi
  fi

  # ── Secrets ───────────────────────────────────────────────────────────────
  local manage_secrets="/mnt/podman/${app_name}/scripts/manageSecrets.sh"
  if [[ -f "${manage_secrets}" ]]; then
    echo "🔑 [${app_name}] Checking secrets..."
    "${manage_secrets}" --check
  fi

  # ── Deploy ────────────────────────────────────────────────────────────────
  echo "🚀 [${app_name}] Deploying..."
  for quadlet in "${SCRIPT_DIR}/apps/${app_name}/quadlets"/*; do
    [[ -f "${quadlet}" ]] || continue
    local unit_name ext service
    unit_name="$(basename "${quadlet}")"
    unit_name="${unit_name%.*}"
    ext="${quadlet##*.}"
    case "${ext}" in
      pod)       service="${unit_name}-pod.service" ;;
      container) service="${unit_name}.service" ;;
      kube)      service="${unit_name}.service" ;;
      *)         continue ;;
    esac
    echo "  [${app_name}] ▶️  Enabling ${service}..."
    systemctl --user enable --now "${service}" 2>/dev/null \
      || systemctl --user restart "${service}" 2>/dev/null || true
  done

  local init_service="${SYSTEMD_USER_DIR}/${app_name}-init.service"
  if [[ -f "${init_service}" ]]; then
    echo "⚙️  [${app_name}] Starting init service..."
    systemctl --user enable "${app_name}-init"
    systemctl --user start "${app_name}-init" &
  fi

  local prune_timer="${SYSTEMD_USER_DIR}/${app_name}-prune.timer"
  if [[ -f "${prune_timer}" ]]; then
    echo "🗑️  [${app_name}] Enabling prune timer..."
    systemctl --user enable --now "${app_name}-prune.timer" 2>/dev/null || true
  fi

  echo "✅ [${app_name}] Done."
}

# ── Run all apps in parallel ──────────────────────────────────────────────────
app_pids=()
for app_name in "${installed_apps[@]}"; do
  install_app "${app_name}" &
  app_pids+=($!)
done

for pid in "${app_pids[@]+"${app_pids[@]}"}"; do
  wait "${pid}" || true
done

# All pulls are done — stop the reporter and clean up the registry
kill "${reporter_pid}" 2>/dev/null || true
rm -rf "${PULL_REGISTRY_DIR}"

echo ""
echo "✅ All apps installed and deployed."
