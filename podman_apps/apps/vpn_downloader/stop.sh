#!/bin/bash

systemctl --user stop vpn-downloader-transmission
systemctl --user stop vpn-downloader-vpn
podman pod rm vpn-downloader
