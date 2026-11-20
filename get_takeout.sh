#!/usr/bin/env bash
# get_takeout.sh by @yottabit42 (Jacob McDonald), rev. 2026-11-19 #1.

echo "Usage:"
echo
echo "${0}"
echo
echo "Prompts for cURL(s) to download in parallel, using server-supplied"
echo "filenames, modifying if necessary to prevent overwriting existing"
echo "files with the same name. Up to 50 cURL entries are allowed. An empty"
echo "entry ends the series."
echo
echo "Note: you probably should not use 50 cURLs without really knowing what"
echo "      you are doing. Typical home and business networks and machines can"
echo "      handle between 3 and 10 simultaneous downloads in parallel."
echo

for cmd in curl cut pv tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Please install '${cmd}' first, e.g., 'sudo apt install ${cmd}'. Exiting."
    exit 1
  fi
done
eof=0
for (( i=0; i<=49; i++ )); do
  echo -n "Paste cURL, then press Enter, or Enter alone to end: "
  while true; do
    if ! IFS='' read -r; then
      eof=1
    fi
    REPLY="${REPLY%$'\r'}"
    if [[ "${eof}" -eq 1 || "${REPLY: -1}" != '\' || -z "${REPLY}" ]]; then
      cURL[i]+="${REPLY%\\}"
      break
    fi
    cURL[i]+="${REPLY%\\}"
  done
  cURL[i]="${cURL[i]//[$'\t\r\n']/}"
  cURL[i]="${cURL[i]#"${cURL[i]%%[![:space:]]*}"}"
  cURL[i]="${cURL[i]#curl }"
  cURL[i]="${cURL[i]#--url }"
  if [[ -z "${cURL[i]}" || "${eof}" -eq 1 ]]; then
    break
  fi
done
if [[ -z "${cURL[0]}" ]]; then
  exit
fi
total_urls=1
for (( i=1; i<=$(("${#cURL[@]}"-1)); i++ )); do
  if [[ ! -z "${cURL[i]}" ]]; then
    cURL[0]+=" "
    cURL[0]+=$(echo "${cURL[i]}" | cut -d ' ' -f 1)
    (( total_urls++ ))
  fi
done

declare -A pre_existing=()
shopt -s nullglob dotglob
for existing_entry in *; do
  if [[ -f "${existing_entry}" ]]; then
    pre_existing["${existing_entry}"]=1
  fi
done
shopt -u nullglob dotglob

no_clobber_flag=""
curl_help=$(curl --help all 2>&1 || curl --help 2>&1)
if [[ "${curl_help}" == *"--no-clobber"* ]]; then
  no_clobber_flag="--no-clobber"
fi

curl_report=$(mktemp "${TMPDIR:-/tmp}/get_takeout.XXXXXX")
cleanup() {
  rm -f -- "${curl_report}"
}
trap cleanup EXIT

write_out_fmt=$'%{urlnum}\x1f%{exitcode}\x1f%{http_code}\x1f%{size_download}\x1f%{content_type}\x1f%{filename_effective}\n'
eval "curl --remote-name-all --parallel-immediate ${no_clobber_flag} -JLOZ -w \"\${write_out_fmt}\" ${cURL[0]}" > "${curl_report}"
curl_rc=$?

declare -a seen_url=()
declare -a dl_exit=()
declare -a dl_http=()
declare -a dl_size=()
declare -a dl_type=()
declare -a dl_file=()
max_urlnum=-1

while IFS=$'\x1f' read -r urlnum exitcode http_code size_dl content_type filename; do
  [[ -z "${urlnum}" ]] && continue
  seen_url[urlnum]=1
  dl_exit[urlnum]="${exitcode}"
  dl_http[urlnum]="${http_code}"
  dl_size[urlnum]="${size_dl}"
  dl_type[urlnum]="${content_type}"
  dl_file[urlnum]="${filename}"
  if (( urlnum > max_urlnum )); then
    max_urlnum=${urlnum}
  fi
done < "${curl_report}"

failed_seq=()
salvaged_msgs=()

loop_max=$(( total_urls - 1 ))
if (( max_urlnum > loop_max )); then
  loop_max=${max_urlnum}
fi

for (( idx=0; idx<=loop_max; idx++ )); do
  seq_num=$(( idx + 1 ))
  if [[ -z "${seen_url[idx]:-}" ]]; then
    if [[ "${curl_rc}" -ne 0 ]]; then
      echo
      echo "Download ${seq_num} failed before transfer started (curl exit ${curl_rc})."
      failed_seq+=("download ${seq_num}")
    fi
    continue
  fi
  exitcode="${dl_exit[idx]}"
  http_code="${dl_http[idx]}"
  size_dl="${dl_size[idx]}"
  content_type="${dl_type[idx],,}"
  filename="${dl_file[idx]}"
  clean_name="${filename#./}"

  is_suspect=0
  reasons=()
  if [[ "${exitcode}" -ne 0 ]]; then
    is_suspect=1
    reasons+=("curl exit ${exitcode}")
  fi
  if [[ "${http_code}" =~ ^[0-9]+$ ]] && (( 10#${http_code} >= 400 )); then
    is_suspect=1
    reasons+=("HTTP ${http_code}")
  fi
  if [[ "${content_type}" == text/* ]]; then
    is_suspect=1
    reasons+=("Content-Type ${dl_type[idx]}")
  fi

  if (( is_suspect == 0 )); then
    continue
  fi

  printf -v reason_str '%s, ' "${reasons[@]}"
  reason_str="${reason_str%, }"

  if [[ -z "${clean_name}" || ! -f "${clean_name}" ]]; then
    echo
    echo "Download ${seq_num} failed (${reason_str}); no output file written."
    failed_seq+=("download ${seq_num}")
    continue
  fi

  if [[ "${size_dl}" -eq 0 && -n "${pre_existing[${clean_name}]:-}" ]]; then
    echo
    echo "Download ${seq_num} failed (${reason_str}); leaving pre-existing file '${clean_name}' untouched."
    failed_seq+=("download ${seq_num}")
    continue
  fi

  echo
  echo "Testing suspect download ${seq_num} ('${clean_name}', ${reason_str}) with 'pv | tar tvz'..."
  pv -- "${clean_name}" | tar tvz > /dev/null
  pipe_rc=("${PIPESTATUS[@]}")
  if [[ "${pipe_rc[0]}" -eq 0 && "${pipe_rc[1]}" -eq 0 ]]; then
    msg="download ${seq_num} ('${clean_name}'): passed 'tar tvz' integrity check despite ${reason_str} — file kept."
    echo "${msg}"
    salvaged_msgs+=("${msg}")
  else
    echo "Download ${seq_num} ('${clean_name}') failed 'tar tvz' integrity check — deleting '${clean_name}'."
    rm -f -- "${clean_name}"
    failed_seq+=("download ${seq_num}")
  fi
done

if (( ${#salvaged_msgs[@]} > 0 )); then
  echo
  echo "Salvaged downloads (passed tar integrity check and kept):"
  for msg in "${salvaged_msgs[@]}"; do
    echo "  - ${msg}"
  done
fi

if (( ${#failed_seq[@]} > 0 )); then
  printf -v failed_list '%s, ' "${failed_seq[@]}"
  failed_list="${failed_list%, }"
  echo
  echo "Failed downloads (deleted/incomplete): ${failed_list}"
  echo "Check your files:"
  ls -lh
  exit 1
fi

if [[ "${curl_rc}" -ne 0 && "${max_urlnum}" -lt 0 ]]; then
  echo -e "\nAn error occurred during download. Check your files:"
  ls -lh
  exit 1
fi
