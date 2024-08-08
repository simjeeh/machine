#!/bin/zsh

SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
for script in "${SCRIPT_PATH}/manjaro"/*
do
  source "${script}"
done
# source <(cat ${SCRIPT_PATH}/*/*)

