#!/usr/bin/env bash
# get_takeout.sh by @yottabit42 (Jacob McDonald), rev. 2026-11-19 #2.

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

for cmd in curl pv tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Please install '${cmd}' first, e.g., 'sudo apt install ${cmd}'. Exiting."
    exit 1
  fi
done

# Tokenize a shell-quoted cURL command (or bare URL) into PARSED_ARGS without eval.
# Supports single quotes ('...'), ANSI-C quotes ($'...'), double quotes ("..."),
# and backslash escapes. Returns 1 on unterminated quotes.
parse_curl_args() {
  local s="$1"
  local len=${#s}
  local pos=0
  local ch next hex rest chunk closed
  local token=""
  local in_token=0
  PARSED_ARGS=()

  while (( pos < len )); do
    ch="${s:pos:1}"

    if [[ "${ch}" == [[:space:]] ]]; then
      if (( in_token )); then
        PARSED_ARGS+=("${token}")
        token=""
        in_token=0
      fi
      (( pos++ ))
      continue
    fi

    in_token=1

    # ANSI-C quoting: $'...'
    if [[ "${ch}" == '$' && $(( pos + 1 )) -lt len && "${s:pos+1:1}" == "'" ]]; then
      (( pos += 2 ))
      closed=0
      while (( pos < len )); do
        rest="${s:pos}"
        chunk="${rest%%[\'\\]*}"
        if [[ -n "${chunk}" ]]; then
          token+="${chunk}"
          (( pos += ${#chunk} ))
          continue
        fi
        ch="${s:pos:1}"
        if [[ "${ch}" == "'" ]]; then
          (( pos++ ))
          closed=1
          break
        fi
        (( pos++ ))
        if (( pos >= len )); then
          return 1
        fi
        next="${s:pos:1}"
        case "${next}" in
          a) token+=$'\a' ;;
          b) token+=$'\b' ;;
          e|E) token+=$'\e' ;;
          f) token+=$'\f' ;;
          n) token+=$'\n' ;;
          r) token+=$'\r' ;;
          t) token+=$'\t' ;;
          v) token+=$'\v' ;;
          \\|\'|\"|\?) token+="${next}" ;;
          x)
            hex="${s:pos+1:2}"
            if [[ "${hex}" =~ ^[0-9a-fA-F]{1,2} ]]; then
              hex="${BASH_REMATCH[0]}"
              printf -v ch "\\x${hex}"
              token+="${ch}"
              (( pos += ${#hex} ))
            else
              token+='\x'
            fi
            ;;
          *)
            token+='\'
            token+="${next}"
            ;;
        esac
        (( pos++ ))
      done
      if (( ! closed )); then
        return 1
      fi
      continue
    fi

    # Single-quoted string: '...'
    if [[ "${ch}" == "'" ]]; then
      (( pos++ ))
      rest="${s:pos}"
      if [[ "${rest}" != *"'"* ]]; then
        return 1
      fi
      chunk="${rest%%\'*}"
      token+="${chunk}"
      (( pos += ${#chunk} + 1 ))
      continue
    fi

    # Double-quoted string: "..."
    if [[ "${ch}" == '"' ]]; then
      (( pos++ ))
      closed=0
      while (( pos < len )); do
        rest="${s:pos}"
        chunk="${rest%%[\"\\]*}"
        if [[ -n "${chunk}" ]]; then
          token+="${chunk}"
          (( pos += ${#chunk} ))
          continue
        fi
        ch="${s:pos:1}"
        if [[ "${ch}" == '"' ]]; then
          (( pos++ ))
          closed=1
          break
        fi
        if (( pos + 1 < len )); then
          next="${s:pos+1:1}"
          if [[ "${next}" == '"' || "${next}" == '\' || "${next}" == '$' || "${next}" == '`' ]]; then
            token+="${next}"
            (( pos += 2 ))
            continue
          fi
        fi
        token+='\'
        (( pos++ ))
      done
      if (( ! closed )); then
        return 1
      fi
      continue
    fi

    # Backslash escape outside quotes
    if [[ "${ch}" == '\' && $(( pos + 1 )) -lt len ]]; then
      token+="${s:pos+1:1}"
      (( pos += 2 ))
      continue
    fi

    # Ordinary unquoted span (shell metacharacters like &, ;, | stay literal)
    rest="${s:pos}"
    chunk="${rest%%[[:space:]\'\"\\$]*}"
    if [[ -n "${chunk}" ]]; then
      token+="${chunk}"
      (( pos += ${#chunk} ))
    else
      token+="${ch}"
      (( pos++ ))
    fi
  done

  if (( in_token )); then
    PARSED_ARGS+=("${token}")
  fi
  return 0
}

extract_url_from_args() {
  local k arg
  EXTRACTED_URL=""
  for (( k=0; k<${#PARSED_ARGS[@]}; k++ )); do
    arg="${PARSED_ARGS[k]}"
    case "${arg}" in
      --url)
        if (( k + 1 < ${#PARSED_ARGS[@]} )) && [[ "${PARSED_ARGS[k+1]}" =~ ^https?:// ]]; then
          EXTRACTED_URL="${PARSED_ARGS[k+1]}"
          return 0
        fi
        ;;
      -H|--header|-b|--cookie|-e|--referer|-A|--user-agent|-X|--request|-d|--data|--data-raw|--data-binary|--data-urlencode|-u|--user|-x|--proxy)
        (( k++ ))
        ;;
      *)
        if [[ "${arg}" =~ ^https?:// ]]; then
          EXTRACTED_URL="${arg}"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

eof=0
total_urls=0
curl_args=()
for (( i=0; i<=49; i++ )); do
  echo -n "Paste cURL, then press Enter, or Enter alone to end: "
  raw_entry=""
  while true; do
    if ! IFS='' read -r; then
      eof=1
    fi
    REPLY="${REPLY%$'\r'}"
    if [[ "${eof}" -eq 1 || "${REPLY: -1}" != '\' || -z "${REPLY}" ]]; then
      raw_entry+="${REPLY%\\}"
      break
    fi
    raw_entry+="${REPLY%\\}"
  done
  raw_entry="${raw_entry//[$'\t\r\n']/}"
  raw_entry="${raw_entry#"${raw_entry%%[![:space:]]*}"}"
  if [[ -z "${raw_entry}" ]]; then
    break
  fi

  if ! parse_curl_args "${raw_entry}"; then
    echo "Invalid entry (unterminated quote). Ignoring entry; paste again or press Enter alone to end."
    if [[ "${eof}" -eq 1 ]]; then
      break
    fi
    (( i-- ))
    continue
  fi

  if (( ${#PARSED_ARGS[@]} > 0 )) && [[ "${PARSED_ARGS[0]}" == "curl" ]]; then
    PARSED_ARGS=("${PARSED_ARGS[@]:1}")
  fi

  if ! extract_url_from_args; then
    echo "Invalid entry (no http:// or https:// URL found). Ignoring entry; paste again or press Enter alone to end."
    if [[ "${eof}" -eq 1 ]]; then
      break
    fi
    (( i-- ))
    continue
  fi

  if (( total_urls == 0 )); then
    curl_args=("${PARSED_ARGS[@]}")
  else
    curl_args+=("${EXTRACTED_URL}")
  fi
  (( total_urls++ ))

  if [[ "${eof}" -eq 1 ]]; then
    break
  fi
done

if (( total_urls == 0 )); then
  exit
fi

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
curl_cmd=(curl --remote-name-all --parallel-immediate)
if [[ -n "${no_clobber_flag}" ]]; then
  curl_cmd+=("${no_clobber_flag}")
fi
curl_cmd+=(-JLOZ -w "${write_out_fmt}" "${curl_args[@]}")
"${curl_cmd[@]}" > "${curl_report}"
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
