#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

POD_DATA_DIR="${HOME}/.podman/vpn-downloader"
if [ ! -d "${POD_DATA_DIR}" ]; then
  mkdir -p "${POD_DATA_DIR}"
fi

podman pod exists vpn-downloader || podman pod create --name vpn-downloader -p 9091:9091

systemctl --user start vpn-downloader-vpn
systemctl --user enable vpn-downloader-vpn

systemctl --user start vpn-downloader-transmission
systemctl --user enable vpn-downloader-transmission
