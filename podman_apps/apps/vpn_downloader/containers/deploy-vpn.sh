#!/bin/bash

podman run -d \
  --name vpn-downloader-vpn \
  --pod vpn-downloader \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -e "VPN_SERVICE_PROVIDER=private internet access" \
  -e "OPENVPN_USER=*****" \
  -e "OPENVPN_PASSWORD=*****" \
  -e "SERVER_REGIONS=Netherlands" \
  --restart unless-stopped \
  ghcr.io/qdm12/gluetun
