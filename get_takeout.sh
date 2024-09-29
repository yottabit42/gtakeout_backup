#!/usr/bin/env bash
# get_takeout.sh by @yottabit42 (Jacob McDonald), rev. 2024-09-29 #1.

echo "Usage:"
echo
echo "${0}"
echo
echo "Prompts for cURL(s) to download in parallel, using server-supplied"
echo "filenames, overwriting existing files with the same name. Up to 50 cURL"
echo "entries are allowed. An empty entry ends the series."
echo
echo "Note: you probably should not use 50 cURLs without really knowing what"
echo "      you are doing. Typical home and business networks and machines can"
echo "      handle between 3 and 10 simultaneous downloads in parallel."
echo

if [[ ! $(which curl) ]]; then
  echo "Please install 'curl' first, e.g., 'sudo apt install curl'. Exiting."
  exit
fi
if [[ ! $(which cut) ]]; then
  echo "Please install 'cut' first, e.g., 'sudo apt install cut'. Exiting."
  exit
fi
for (( i=0; i<=49; i++ )); do
  echo -n "Paste cURL, then press Enter, or Enter alone to end: "
  while IFS='' read -r; do
    if [[ "${REPLY: -1}" != '\' || -z "${REPLY}" ]]; then
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
eval curl --remote-name-all --parallel-immediate -CJLOZf ${cURL[@]}
