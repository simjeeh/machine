#!/bin/zsh

SCRIPT_PATH="$(cd -- "$(dirname "${0}")" >/dev/null 2>&1 ; pwd -P)"
SCRIPT_NAME=$(realpath "${0}")
for script in "${SCRIPT_PATH}"/*
do
  if [[ "${script}" != "${SCRIPT_NAME}" ]]
  then
    source "${script}"
  fi
done

