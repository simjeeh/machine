# My Desktop
This repository contains scripts and configuration files for setting up and managing the software and containerized applications I use on my desktop
## init.sh
This script installs all the software dependencies required for the tools and applications in this repository.
It should be run once after cloning the repository to ensure your environment is ready
## podman_apps
This directory contains configuration, deployment, and management scripts for containerized applications running via Podman
### installApps.sh
This script registers all Podman-based applications with systemd, enabling you to manage them as systemd services
It performs the following actions:
1. **Systemd Integration** – Creates symlinks for all `.service` files found in `podman_apps/apps/*/systemd` into the user’s systemd directory `~/.config/systemd/user`
1. **Container Deployment Scripts** – Creates symlinks for all container deployment scripts found in `podman_apps/apps/*/containers` into `/opt`
### apps
This directory contains all application-specific files and folders
#### containers
Holds all Podman container deployment scripts for the application.
Each script in this folder is used to start a container (e.g., image, ports, environment variables)
These files are linked into the user’s opt directory by `installApps.sh`
#### systemd
Contains all systemd unit files (`.service`) for managing the application.
These files are linked into the user’s systemd configuration directory by `installApps.sh`
#### scripts
Utility scripts for managing the secrets of the application:
1. `createSecrets.sh` – Creates/overwrites Podman secrets required for this application
1. `deploy.sh` – Creates a Pod for this application and deploys all its containers
1. `stop.sh` – Stops all containers for the application and removes the associated Pod
1. `restart.sh` – Performs a hard restart by running stop.sh followed by deploy.sh
