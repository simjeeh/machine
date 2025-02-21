#!/bin/zsh

reboot_to_windows()
{
    MENU_ENTRY_ID=$(sudo grep -i windows /boot/grub/grub.cfg | awk -F'menuentry_id_option' '{print $2}' | awk -F"'" '{print $2}')
    sudo grub-reboot "$MENU_ENTRY_ID" && sudo reboot
}
export reboot_to_windows
alias windows='reboot_to_windows'
echo "windows"

