#!/bin/zsh

function update_system() {
  yay --answerclean All --answerdiff None --save
}
export update_system
echo "update_system"

function update_system_hard(){
  sudo pacman -Syyu
}
export update_system_hard
echo "update_system_hard"

function update_chrome(){
  yay -S google-chrome --answerclean All --answerdiff None
}
export update_chrome
echo "update_chrome"

function clean_system(){
  sudo paccache -rk0
  sudo pacman -Scc
  rm -rf ~/.cache/*
}
export clean_system
echo "clean_system"
