#!/usr/bin/env bash
#

if [[ "${1}" && "${2}" && "${3}" ]]; then
  if [[ ! "${1}" =~ ^[0-9]+$ ]]; then
    echo "<NUM_DL> must be a whole number. Exiting."
    exit
  elif [[ ! "${2}" =~ ^[0-9]+$ ]]; then
    echo "<NUM_START> must be a whole number. Exiting."
    exit
  fi
  for (( i=0; i<=$(("${1}"-1)); i++ )); do
    read -p "Enter URL: " URL[i]
    if [ -z "${URL[i]}" ]; then
      break
    fi
  done
  for (( i=0; i<=$(("${1}"-1)); i++ )); do
    if test -f "$((${2}+${i}))${3}"; then
      echo "$((${2}+${i}))${3} exists. Exiting."
      exit
    fi
  done
  for (( i=0; i<=$(("${1}"-1)); i++ )); do
    if [ ! -z "${URL[i]}" ]; then
#      wget -O "$((${2}+${i}))${3}" -c -q --show-progress "${URL[i]}" &
      echo -O "$((${2}+${i}))${3}" -c -q --show-progress "${URL[i]}" &
    fi
  done
  wait
else
  echo "Usage:"
  echo
  echo "${0} <NUM_DL> <NUM_START> <.EXT>"
  echo
  echo "Prompts for URLs to download in parallel, auto-incrementing filenames."
  echo
  echo "<NUM_DL>     Number of parallel downloads"
  echo "<NUM_START>  Filename number to start with"
  echo "<.EXT>       Filename extension to append"
  echo
  echo "An empty URL response ends the series. If a filename conflict occurs,"
  echo "the script exits to prevent overwriting. Correct and try again."
fi
