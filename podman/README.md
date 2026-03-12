# podman

This directory contains configuration, deployment, and management scripts for containerized applications running via Podman with systemd quadlets on Fedora.

---

## Requirements

- Podman 5.0+
- A dedicated disk mounted at `/mnt/podman` owned by your user
- `loginctl enable-linger` enabled (handled automatically by `installApps.sh`)

---

## First-time setup

### 1. Install Podman 5.0+
```bash
sudo dnf install -y podman
podman --version
```

### 2. Set up `/mnt/podman`

Create the directory and mount your dedicated disk:
```bash
sudo mkdir -p /mnt/podman
sudo mount /dev/sdX1 /mnt/podman
sudo chown -R ${USER}:${USER} /mnt/podman
```

Add to `/etc/fstab` for auto-mount on boot.

### 3. NVIDIA GPU (if applicable)

Skip this section if you don't have an NVIDIA GPU.

**Install drivers:**
```bash
sudo dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
sudo akmods --force
sudo reboot
```

**Verify drivers:**
```bash
nvidia-smi
```

**Install NVIDIA Container Toolkit:**
```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
  | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit
```

**Generate CDI spec:**
```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
mkdir -p ~/.config/cdi
cp /etc/cdi/nvidia.yaml ~/.config/cdi/nvidia.yaml
```

**Enable SELinux device access:**
```bash
sudo setsebool -P container_use_devices 1
```

**Verify podman can see the GPU:**
```bash
podman run --rm \
  --device nvidia.com/gpu=all \
  --security-opt=label=disable \
  docker.io/nvidia/cuda:12.3.1-base-ubuntu22.04 \
  nvidia-smi
```

### 4. Install apps
```bash
git clone <your-repo>
cd podman
./installApps.sh
```

`installApps.sh` will:
- Validate `/mnt/podman` exists and is writable
- Create all required `.data` subdirectories
- Symlink all quadlets, scripts, and config files into their target locations
- Reload systemd
- Prompt for any missing secrets
- Start all apps

---

## Updating after a git pull
```bash
git pull
./installApps.sh
```

`installApps.sh` is idempotent — it can be run as many times as needed. It recreates all symlinks, reloads systemd, and restarts all apps to pick up any changes.

---

## Managing applications

Apps are composed of multiple systemd units — a pod unit and one or more container units. Manage them individually with `systemctl --user`.

**Start:**
```bash
systemctl --user start <unit>
```

**Stop:**
```bash
systemctl --user stop <unit>
```

**Restart:**
```bash
systemctl --user restart <unit>
```

**Status:**
```bash
systemctl --user status <unit> --no-pager
```

**Logs:**
```bash
journalctl --user -fu <unit>
```

**List all units:**
```bash
systemctl --user list-unit-files | grep -E "pod|container"
```

---

## Viewing running containers and pods

**List all pods:**
```bash
podman pod ps
```

**List all containers:**
```bash
podman ps
```

---

## App structure

Each app lives under `apps/<app-name>/` and follows this structure:
```
apps/
└── <app-name>/
    ├── .data-dirs        # list of subdirs to create under /mnt/podman/<app>/.data/
    ├── quadlets/         # .pod and .container quadlet files
    ├── scripts/          # manageSecrets.sh and other management scripts
    └── config/           # config files (e.g. nginx.conf, models.txt)
```

### `quadlets/`
Contains quadlet unit files (`.pod`, `.container`) that tell systemd how to manage the application. Systemd generates `.service` units from these automatically after `daemon-reload`. Symlinked into `~/.config/containers/systemd/` by `installApps.sh`.

Each app typically has:
- **`<app>.pod`** — defines the pod and port bindings. Generates `<app>-pod.service`
- **`<app>-<container>.container`** — defines each container in the pod. Generates `<app>-<container>.service`

### `scripts/`
Contains management scripts. Symlinked into `/mnt/podman/<app>/scripts/` by `installApps.sh`.

- **`manageSecrets.sh`** — creates podman secrets for the app. Run with `--check` to only create if missing, or with no flags to prompt for all values

### `config/`
Contains config files mounted into containers. Symlinked into `/mnt/podman/<app>/config/` by `installApps.sh`.

### `.data-dirs`
A plain text file listing subdirectories to create under `/mnt/podman/<app>/.data/`. One directory per line. Comments start with `#`. Created automatically by `installApps.sh` on every run.

Example:
```
# .data-dirs
downloads
config
```

---

## installApps.sh

Performs the following actions:

1. **Validates `/mnt/podman`** — exits with a clear error if the directory doesn't exist or isn't writable
2. **Enables linger** — runs `loginctl enable-linger` so rootless containers survive logout
3. **Creates `.data` directories** — reads `.data-dirs` per app and creates all required subdirs under `/mnt/podman/<app>/.data/`
4. **Symlinks quadlets** — links all files in `apps/*/quadlets/` into `~/.config/containers/systemd/`
5. **Symlinks scripts** — links all files in `apps/*/scripts/` into `/mnt/podman/<app>/scripts/`
6. **Symlinks config** — links all files in `apps/*/config/` into `/mnt/podman/<app>/config/`
7. **Reloads systemd** — runs `systemctl --user daemon-reload` once after all symlinks are created
8. **Checks secrets** — runs `manageSecrets.sh --check` for any app that has one, prompting for input if secrets are missing
9. **Deploys all units** — starts all `.pod`, `.container`, and `.kube` units found in each app's `quadlets/` directory

---

## Application data

Runtime data for all applications lives under `/mnt/podman/<app>/.data/` on the dedicated Podman disk mounted at `/mnt/podman`. Subdirectories are declared in `.data-dirs` and created automatically by `installApps.sh` on every run.

---

## Secrets

Secrets are stored as rootless podman secrets managed by `manageSecrets.sh`. They are stored locally by podman and are never committed to the repo. To re-create secrets for an app:
```bash
/mnt/podman/<app>/scripts/manageSecrets.sh
```

---

## SELinux

All volume mounts use the `:Z` suffix to allow containers to access host-mounted directories on Fedora:
```ini
Volume=/mnt/podman/<app>/.data/foo:/foo:Z
```

This tells podman to automatically relabel the directory with the correct SELinux context (`container_file_t`).
