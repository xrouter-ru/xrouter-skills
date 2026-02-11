#!/bin/bash
set -euo pipefail

# Config (can be overridden by env vars)
CONF_BASE_URL="${CONF_BASE_URL:-https://confluence.sberbank.ru}"
CONF_PAT_FILE="${CONF_PAT_FILE:-secrets/confluence-pat}"
CONF_CACERT="${CONF_CACERT:-secrets/SberCARootExt.crt}"

if [[ ! -f "$CONF_PAT_FILE" ]]; then
  echo "PAT file not found: $CONF_PAT_FILE" >&2
  exit 1
fi

PAT="$(head -n 1 "$CONF_PAT_FILE")"

if [[ -z "$PAT" ]]; then
  echo "PAT is empty in: $CONF_PAT_FILE" >&2
  exit 1
fi

curl_common_args=(
  -sS
  -H "Accept: application/json"
  -H "Authorization: Bearer $PAT"
)

if [[ -f "$CONF_CACERT" ]]; then
  curl_common_args+=(--cacert "$CONF_CACERT")
fi

usage() {
  cat <<'EOF'
Usage:
  ./confluence_content.sh get CONTENT_ID [expand]
  ./confluence_content.sh create PAYLOAD_JSON_FILE
  ./confluence_content.sh update CONTENT_ID PAYLOAD_JSON_FILE
  ./confluence_content.sh delete CONTENT_ID
  ./confluence_content.sh children CONTENT_ID [type]
  ./confluence_content.sh versions CONTENT_ID
  ./confluence_content.sh search 'space = DOC and type = page and title ~ "api"' [limit]
  ./confluence_content.sh raw METHOD API_PATH [PAYLOAD_JSON_FILE]

Examples:
  ./confluence_content.sh get 123456
  ./confluence_content.sh get 123456 'body.storage,version,space'
  ./confluence_content.sh create payloads/create_page.json
  ./confluence_content.sh update 123456 payloads/update_page.json
  ./confluence_content.sh children 123456 page
  ./confluence_content.sh versions 123456
  ./confluence_content.sh search 'space = DOC and type = page' 20
EOF
}

pretty_print() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
  fi
}

print_response_or_fail() {
  local response="$1"
  local context="$2"
  local http_code
  local body

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" | pretty_print
    else
      echo "OK ($http_code)"
    fi
  else
    echo "HTTP $http_code for $context" >&2
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" | pretty_print >&2
    fi
    exit 1
  fi
}

api_call() {
  local method="$1"
  local path="$2"
  local payload_file="${3:-}"
  local url="${CONF_BASE_URL}${path}"
  local response

  if [[ -n "$payload_file" ]]; then
    if [[ ! -f "$payload_file" ]]; then
      echo "Payload file not found: $payload_file" >&2
      exit 1
    fi

    response="$(
      curl "${curl_common_args[@]}" \
        -X "$method" \
        -H "Content-Type: application/json" \
        --data @"$payload_file" \
        -w $'\n%{http_code}' \
        "$url"
    )"
  else
    response="$(
      curl "${curl_common_args[@]}" \
        -X "$method" \
        -w $'\n%{http_code}' \
        "$url"
    )"
  fi

  print_response_or_fail "$response" "$method $path"
}

api_get_query() {
  local path="$1"
  shift
  local url="${CONF_BASE_URL}${path}"
  local response
  local args=("${curl_common_args[@]}" -G -w $'\n%{http_code}' "$url")

  while [[ "$#" -gt 0 ]]; do
    args+=(--data-urlencode "$1")
    shift
  done

  response="$(curl "${args[@]}")"
  print_response_or_fail "$response" "GET $path (query)"
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift

case "$cmd" in
  get)
    content_id="${1:-}"
    expand="${2:-}"
    [[ -n "$content_id" ]] || { usage; exit 1; }
    if [[ -n "$expand" ]]; then
      api_get_query "/rest/api/content/$content_id" "expand=$expand"
    else
      api_call GET "/rest/api/content/$content_id"
    fi
    ;;

  create)
    payload_file="${1:-}"
    [[ -n "$payload_file" ]] || { usage; exit 1; }
    api_call POST "/rest/api/content" "$payload_file"
    ;;

  update)
    content_id="${1:-}"
    payload_file="${2:-}"
    [[ -n "$content_id" && -n "$payload_file" ]] || { usage; exit 1; }
    api_call PUT "/rest/api/content/$content_id" "$payload_file"
    ;;

  delete)
    content_id="${1:-}"
    [[ -n "$content_id" ]] || { usage; exit 1; }
    api_call DELETE "/rest/api/content/$content_id"
    ;;

  children)
    content_id="${1:-}"
    child_type="${2:-page}"
    [[ -n "$content_id" ]] || { usage; exit 1; }
    api_call GET "/rest/api/content/$content_id/child/$child_type"
    ;;

  versions)
    content_id="${1:-}"
    [[ -n "$content_id" ]] || { usage; exit 1; }
    api_call GET "/rest/api/content/$content_id/version"
    ;;

  search)
    cql="${1:-}"
    limit="${2:-50}"
    [[ -n "$cql" ]] || { usage; exit 1; }
    api_get_query "/rest/api/content/search" "cql=$cql" "limit=$limit"
    ;;

  raw)
    method="${1:-}"
    path="${2:-}"
    payload_file="${3:-}"
    [[ -n "$method" && -n "$path" ]] || { usage; exit 1; }
    api_call "$method" "$path" "$payload_file"
    ;;

  *)
    usage
    exit 1
    ;;
esac

