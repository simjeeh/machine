#!/bin/bash

podman run --pod vpn-downloader --name vpn-downloader-vpn \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  --secret=vpn_downloader_vpn_user,type=env,target=OPENVPN_USER \
  --secret=vpn_downloader_vpn_password,type=env,target=OPENVPN_PASSWORD \
  -e "VPN_SERVICE_PROVIDER=private internet access" \
  -e "SERVER_REGIONS=Netherlands" \
  --restart unless-stopped \
  ghcr.io/qdm12/gluetun
