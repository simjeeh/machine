#!/bin/bash

mkdir -p ${HOME}/.podman/vpn_downloader/downloads
mkdir -p ${HOME}/.podman/vpn_downloader/config

podman run -d \
  --name vpn-downloader-transmission \
  --pod vpn-downloader \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -e "TRANSMISSION_DOWNLOAD_DIR=/downloads" \
  -e "TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true" \
  -e "TRANSMISSION_RPC_USERNAME=*****" \
  -e "TRANSMISSION_RPC_PASSWORD=*****" \
  -e "TZ=America/Los_Angeles" \
  -v ${HOME}/.podman/vpn_downloader/downloads:/downloads \
  -v ${HOME}/.podman/vpn_downloader/config:/config \
  --restart unless-stopped \
  lscr.io/linuxserver/transmission

