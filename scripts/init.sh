#!/bin/zsh

SCRIPT_PATH="$( cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P )"

# install sublime
curl -O https://download.sublimetext.com/sublimehq-pub.gpg && pacman-key --add sublimehq-pub.gpg && pacman-key --lsign-key 8A8F901A && rm sublimehq-pub.gpg
echo -e "\n[sublime-text]\nServer = https://download.sublimetext.com/arch/stable/x86_64" | tee -a /etc/pacman.conf
yes | pacman -Syu sublime-text

# install yay
yes | pacman -S yay

chmod +x ${SCRIPT_PATH}/manjaro/manjaroSource.sh
sudo -u ${SUDO_USER} zsh -c "echo \"source ${SCRIPT_PATH}/manjaro/manjaroSource.sh\" >> \${HOME}/.zshrc"

