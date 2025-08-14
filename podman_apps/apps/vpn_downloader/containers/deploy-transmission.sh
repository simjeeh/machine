#!/bin/bash

mkdir -p ${HOME}/.podman/vpn_downloader/downloads
mkdir -p ${HOME}/.podman/vpn_downloader/config

podman run --pod vpn-downloader --name vpn-downloader-transmission \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --secret=vpn_downloader_transmission_rpc_username,type=env,target=TRANSMISSION_RPC_USERNAME \
  --secret=vpn_downloader_transmission_rpc_password,type=env,target=TRANSMISSION_RPC_PASSWORD \
  -e "TRANSMISSION_DOWNLOAD_DIR=/downloads" \
  -e "TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true" \
  -e "TZ=America/Los_Angeles" \
  -v ${HOME}/.podman/vpn_downloader/downloads:/downloads \
  -v ${HOME}/.podman/vpn_downloader/config:/config \
  --restart unless-stopped \
  lscr.io/linuxserver/transmission
