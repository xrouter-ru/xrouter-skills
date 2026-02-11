#!/bin/bash
set -euo pipefail

# Config (can be overridden by env vars)
JIRA_BASE_URL="${JIRA_BASE_URL:-https://jira.sberbank.ru}"
JIRA_PAT_FILE="${JIRA_PAT_FILE:-secrets/jira-pat}"
JIRA_CACERT="${JIRA_CACERT:-secrets/SberCARootExt.crt}"

if [[ ! -f "$JIRA_PAT_FILE" ]]; then
  echo "PAT file not found: $JIRA_PAT_FILE" >&2
  exit 1
fi

PAT="$(head -n 1 "$JIRA_PAT_FILE")"

if [[ -z "$PAT" ]]; then
  echo "PAT is empty in: $JIRA_PAT_FILE" >&2
  exit 1
fi

curl_common_args=(
  -sS
  -H "Accept: application/json"
  -H "Authorization: Bearer $PAT"
)

if [[ -f "$JIRA_CACERT" ]]; then
  curl_common_args+=(--cacert "$JIRA_CACERT")
fi

usage() {
  cat <<'EOF'
Usage:
  ./jira_issue.sh get ISSUE_KEY
  ./jira_issue.sh create PAYLOAD_JSON_FILE
  ./jira_issue.sh update ISSUE_KEY PAYLOAD_JSON_FILE
  ./jira_issue.sh transitions ISSUE_KEY
  ./jira_issue.sh transition ISSUE_KEY TRANSITION_ID [FIELDS_JSON_FILE]
  ./jira_issue.sh comment ISSUE_KEY "comment text"
  ./jira_issue.sh assign ISSUE_KEY ASSIGNEE_NAME
  ./jira_issue.sh search 'project = ABC ORDER BY created DESC' [max_results]
  ./jira_issue.sh delete ISSUE_KEY
  ./jira_issue.sh raw METHOD API_PATH [PAYLOAD_JSON_FILE]

Examples:
  ./jira_issue.sh get ABC-123
  ./jira_issue.sh create payloads/create_issue.json
  ./jira_issue.sh update ABC-123 payloads/update_issue.json
  ./jira_issue.sh transitions ABC-123
  ./jira_issue.sh transition ABC-123 31
  ./jira_issue.sh transition ABC-123 31 payloads/transition_fields.json
  ./jira_issue.sh comment ABC-123 "Проверено, можно в релиз"
  ./jira_issue.sh assign ABC-123 ivanovii
  ./jira_issue.sh search 'assignee = currentUser() AND statusCategory != Done' 20
EOF
}

pretty_print() {
  if command -v jq >/dev/null 2>&1; then
    jq .
  else
    cat
  fi
}

api_call() {
  local method="$1"
  local path="$2"
  local payload_file="${3:-}"
  local url="${JIRA_BASE_URL}${path}"

  local response
  local http_code
  local body

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

  http_code="${response##*$'\n'}"
  body="${response%$'\n'*}"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" | pretty_print
    else
      echo "OK ($http_code)"
    fi
  else
    echo "HTTP $http_code for $method $path" >&2
    if [[ -n "$body" ]]; then
      printf '%s\n' "$body" | pretty_print >&2
    fi
    exit 1
  fi
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift

case "$cmd" in
  get)
    issue_key="${1:-}"
    [[ -n "$issue_key" ]] || { usage; exit 1; }
    api_call GET "/rest/api/2/issue/$issue_key"
    ;;

  create)
    payload_file="${1:-}"
    [[ -n "$payload_file" ]] || { usage; exit 1; }
    api_call POST "/rest/api/2/issue" "$payload_file"
    ;;

  update)
    issue_key="${1:-}"
    payload_file="${2:-}"
    [[ -n "$issue_key" && -n "$payload_file" ]] || { usage; exit 1; }
    api_call PUT "/rest/api/2/issue/$issue_key" "$payload_file"
    ;;

  transitions)
    issue_key="${1:-}"
    [[ -n "$issue_key" ]] || { usage; exit 1; }
    api_call GET "/rest/api/2/issue/$issue_key/transitions"
    ;;

  transition)
    issue_key="${1:-}"
    transition_id="${2:-}"
    fields_file="${3:-}"
    [[ -n "$issue_key" && -n "$transition_id" ]] || { usage; exit 1; }

    tmp_payload="$(mktemp)"
    if [[ -n "$fields_file" ]]; then
      if [[ ! -f "$fields_file" ]]; then
        echo "Payload file not found: $fields_file" >&2
        exit 1
      fi
      if command -v jq >/dev/null 2>&1; then
        jq --arg id "$transition_id" '. + {transition: {id: $id}}' "$fields_file" > "$tmp_payload"
      else
        echo "jq is required for transition with extra fields" >&2
        rm -f "$tmp_payload"
        exit 1
      fi
    else
      cat > "$tmp_payload" <<EOF
{"transition":{"id":"$transition_id"}}
EOF
    fi

    api_call POST "/rest/api/2/issue/$issue_key/transitions" "$tmp_payload"
    rm -f "$tmp_payload"
    ;;

  comment)
    issue_key="${1:-}"
    comment_text="${2:-}"
    [[ -n "$issue_key" && -n "$comment_text" ]] || { usage; exit 1; }
    tmp_payload="$(mktemp)"

    if command -v jq >/dev/null 2>&1; then
      jq -n --arg body "$comment_text" '{body: $body}' > "$tmp_payload"
    else
      escaped="${comment_text//\"/\\\"}"
      printf '{"body":"%s"}\n' "$escaped" > "$tmp_payload"
    fi

    api_call POST "/rest/api/2/issue/$issue_key/comment" "$tmp_payload"
    rm -f "$tmp_payload"
    ;;

  assign)
    issue_key="${1:-}"
    assignee="${2:-}"
    [[ -n "$issue_key" && -n "$assignee" ]] || { usage; exit 1; }
    tmp_payload="$(mktemp)"
    printf '{"name":"%s"}\n' "$assignee" > "$tmp_payload"
    api_call PUT "/rest/api/2/issue/$issue_key/assignee" "$tmp_payload"
    rm -f "$tmp_payload"
    ;;

  search)
    jql="${1:-}"
    max_results="${2:-50}"
    [[ -n "$jql" ]] || { usage; exit 1; }
    tmp_payload="$(mktemp)"

    if command -v jq >/dev/null 2>&1; then
      jq -n --arg jql "$jql" --argjson max "$max_results" '{jql: $jql, maxResults: $max}' > "$tmp_payload"
    else
      escaped="${jql//\"/\\\"}"
      printf '{"jql":"%s","maxResults":%s}\n' "$escaped" "$max_results" > "$tmp_payload"
    fi

    api_call POST "/rest/api/2/search" "$tmp_payload"
    rm -f "$tmp_payload"
    ;;

  delete)
    issue_key="${1:-}"
    [[ -n "$issue_key" ]] || { usage; exit 1; }
    api_call DELETE "/rest/api/2/issue/$issue_key"
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

