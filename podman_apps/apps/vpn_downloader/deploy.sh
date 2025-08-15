#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

POD_NAME="vpn-downloader"
POD_DATA_DIR="${HOME}/.podman/${POD_NAME}"
if [ ! -d "${POD_DATA_DIR}" ]; then
  mkdir -p "${POD_DATA_DIR}"
fi

podman pod exists ${POD_NAME} || podman pod create --name ${POD_NAME} -p 9091:9091

systemctl --user start vpn-downloader-vpn
systemctl --user enable vpn-downloader-vpn

systemctl --user start vpn-downloader-transmission
systemctl --user enable vpn-downloader-transmission
