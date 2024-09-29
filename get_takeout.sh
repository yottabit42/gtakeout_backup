#!/usr/bin/env bash
#

if [[ ! $(which curl) ]]; then
  echo "Please install 'curl' first, e.g., 'sudo apt install curl'. Exiting."
  exit
fi
if [[ ! $(which cut) ]]; then
  echo "Please install 'cut' first, e.g., 'sudo apt install cut'. Exiting."
  exit
fi
if [[ "${1}" ]]; then
  if [[ ! "${1}" =~ ^[0-9]+$ ]]; then
    echo "<NUM_DL> must be a whole number. Exiting."
    exit
  elif (( "${1}" > 50 )) || (( "${1}" < 1 )); then
    echo "<NUM_DL> must be between 1 and 50. Exiting."
    exit
  fi
  for (( i=0; i<=$(("${1}"-1)); i++ )); do
    echo -n "Paste cURL, then press Enter twice: "
    while IFS='' read -r; do
      if [[ -z "${REPLY}" ]]; then
        break
      fi
      cURL[i]+="${REPLY}"
    done
    cURL[i]="${cURL[i]//curl /}"
    cURL[i]="${cURL[i]//[$'\t\r\n\\']}"
    if [[ -z "${cURL[i]}" ]]; then
      break
    fi
  done
  if [[ -z "${cURL[0]}" ]]; then
    exit
  fi
  for (( i=1; i<=$(("${1}"-1)); i++ )); do
    if [[ ! -z "${cURL[i]}" ]]; then
      cURL[i]+=" "
      cURL[i]+=$(echo "${cURL[i]}" | cut -d ' ' -f 1)
    fi
  done
  trapCmd="echo -e '\nAn error occurred during download. Check your files:'; "
  trapCmd+="ls -lh; exit 1"
  trap "${trapCmd}" ERR
  eval curl --remote-name-all --parallel-immediate -JLOZf ${cURL[@]}
else
  echo "Usage:"
  echo
  echo "${0} <NUM_DL>"
  echo
  echo "Prompts for cURL(s) to download in parallel, using server-supplied"
  echo "filenames, overwriting if necessary. An empty cURL entry ends the"
  echo "series early (safely)."
  echo
  echo "<NUM_DL>  Number of parallel downloads, from 1 to 50"
fi
