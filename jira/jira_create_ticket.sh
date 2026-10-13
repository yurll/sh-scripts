#!/usr/bin/env bash
# shellcheck source=/dev/null

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _JIRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  _JIRA_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  _JIRA_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

jira_create_ticket() {
  unset AIT ALGOSEC
  if [[ -f "$_JIRA_DIR/.env" ]]; then
    set -a
    source "$_JIRA_DIR/.env"
    set +a
  fi

  local json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -j|--json) json=1 ;;
      -h|--help)
        echo "usage: jira_create_ticket [--json] <summary> [description]" >&2
        return 0
        ;;
      -*) echo "unknown option: $1" >&2; return 1 ;;
      *) break ;;
    esac
    shift
  done

  [[ $# -ge 1 ]] || {
    echo "usage: jira_create_ticket [--json] <summary> [description]" >&2
    return 1
  }

  local summary="$1" description="${2:-}"
  local project="${JIRA_PROJECT:-DEVOPS}"
  local issuetype="${JIRA_ISSUE_TYPE:-Task}"
  local team="${JIRA_TEAM:-}"
  local team_field="${JIRA_TEAM_FIELD:-}"
  local tmp http_code body key url

  command -v jq >/dev/null || { echo "error: jq is required" >&2; return 1; }
  [[ -n "${JIRA_DOMAIN:-}" && -n "${JIRA_API_TOKEN:-}" ]] || {
    echo "error: set JIRA_DOMAIN and JIRA_API_TOKEN in $_JIRA_DIR/.env" >&2
    return 1
  }

  # Cloud ATATT token → basic auth + REST v3; Jira DC PAT → Bearer + REST v2
  local api myself_json account_id assignee_name payload
  if [[ "${JIRA_API_TOKEN}" == ATATT* ]]; then
    [[ -n "${JIRA_EMAIL:-}" ]] || { echo "error: JIRA_EMAIL required for Cloud API token" >&2; return 1; }
    api="https://${JIRA_DOMAIN}/rest/api/3"
    tmp="$(mktemp)"
    http_code="$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
      -H 'Accept: application/json' -o "$tmp" -w '%{http_code}' "${api}/myself")"
    myself_json="$(<"$tmp")"
    rm -f "$tmp"
    account_id="$(jq -r '.accountId // empty' <<<"$myself_json")"
    [[ -n "$account_id" ]] || {
      echo "error: Jira /myself failed (HTTP $http_code)" >&2
      echo "$myself_json" >&2
      return 1
    }
    payload="$(jq -n \
      --arg project "$project" --arg summary "$summary" --arg description "$description" \
      --arg issuetype "$issuetype" --arg accountId "$account_id" \
      --arg teamField "$team_field" --arg team "$team" \
      '{fields:{project:{key:$project},summary:$summary,issuetype:{name:$issuetype},
        assignee:{accountId:$accountId},
        description:{type:"doc",version:1,content:[{type:"paragraph",content:[{type:"text",text:$description}]}]}}}
      | if $team != "" and $teamField != "" then .fields[$teamField]={value:$team} else . end')"
    tmp="$(mktemp)"
    http_code="$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
      -H 'Accept: application/json' -H 'Content-Type: application/json' \
      -X POST --data "$payload" -o "$tmp" -w '%{http_code}' "${api}/issue")"
  else
    api="https://${JIRA_DOMAIN}/rest/api/2"
    tmp="$(mktemp)"
    http_code="$(curl -s -H "Authorization: Bearer ${JIRA_API_TOKEN}" \
      -H 'Accept: application/json' -o "$tmp" -w '%{http_code}' "${api}/myself")"
    myself_json="$(<"$tmp")"
    rm -f "$tmp"
    account_id="$(jq -r '.accountId // empty' <<<"$myself_json")"
    assignee_name="$(jq -r '.name // empty' <<<"$myself_json")"
    [[ -n "$account_id" || -n "$assignee_name" ]] || {
      echo "error: Jira /myself failed (HTTP $http_code)" >&2
      echo "$myself_json" >&2
      return 1
    }
    payload="$(jq -n \
      --arg project "$project" --arg summary "$summary" --arg description "$description" \
      --arg issuetype "$issuetype" --arg accountId "$account_id" --arg assigneeName "$assignee_name" \
      --arg teamField "$team_field" --arg team "$team" \
      '{fields:{project:{key:$project},summary:$summary,issuetype:{name:$issuetype},description:$description}}
      | if $accountId != "" then .fields.assignee={accountId:$accountId}
        elif $assigneeName != "" then .fields.assignee={name:$assigneeName} else . end
      | if $team != "" and $teamField != "" then .fields[$teamField]={value:$team} else . end')"
    tmp="$(mktemp)"
    http_code="$(curl -s -H "Authorization: Bearer ${JIRA_API_TOKEN}" \
      -H 'Accept: application/json' -H 'Content-Type: application/json' \
      -X POST --data "$payload" -o "$tmp" -w '%{http_code}' "${api}/issue")"
  fi

  body="$(<"$tmp")"
  rm -f "$tmp"

  if [[ "$http_code" != "201" ]]; then
    echo "error: Jira returned HTTP $http_code" >&2
    echo "$body" >&2
    return 1
  fi

  key="$(jq -r '.key // empty' <<<"$body")"
  [[ -n "$key" ]] || { echo "error: no issue key in response" >&2; echo "$body" >&2; return 1; }

  url="https://${JIRA_DOMAIN}/browse/${key}"
  if [[ "$json" -eq 1 ]]; then
    jq -n --arg key "$key" --arg summary "$summary" --arg url "$url" \
      '{key:$key,summary:$summary,url:$url}'
  else
    printf '%s  %s\n%s\n' "$key" "$summary" "$url"
  fi
}

if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  jira_create_ticket "$@"
fi
