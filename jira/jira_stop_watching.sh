#!/bin/bash
# shellcheck source=/dev/null

if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

JQL='watcher = currentUser()' # AND status != Resolved'
MAX_RESULTS=100

ENCODED_JQL=$(jq -rn --arg v "$JQL" '$v|@uri')

function jira_get_issues() {
  echo "Fetching watched issues matching JQL..." >&2
  response=$(mktemp)
  http_code=$(curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -X POST \
    --data '{"jql":"'"${JQL}"'","fields":["key"],"maxResults":'"${MAX_RESULTS}"'}' \
    "https://${JIRA_DOMAIN}/rest/api/3/search/jql" \
    -o "$response" -w "%{http_code}")
  body=$(cat "$response")
  if [[ "$http_code" -ne 200 ]]; then
    echo "ERROR: Failed to fetch issues from JIRA." >&2
    echo "ERROR: Full response: $body" >&2
    return 1
  fi
  echo "$body" | jq -r '.issues[].key'
}

function jira_get_my_account_id() {
  echo "Fetching my account ID..." >&2
  response=$(curl -s -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
    -H "Accept: application/json" \
    "https://${JIRA_DOMAIN}/rest/api/3/myself")

  account_id=$(echo "$response" | jq -r '.accountId')
  if [ -z "$account_id" ]; then
    echo "ERROR: Could not fetch account ID." >&2
    return 1
  fi
  echo "$account_id"
}

function jira_unwatch_issue() {
  local account_id="$1"
  local issue_key="$2"
  echo "  Unwatching issue: $issue_key"
  response=$(mktemp)
  result=$(curl -s -o "$response" -w "%{http_code}" -X DELETE \
  --url "https://${JIRA_DOMAIN}/rest/api/3/issue/${issue_key}/watchers?accountId=${account_id}" \
  --user "${JIRA_EMAIL}:${JIRA_API_TOKEN}")

  if [[ "$result" == "204" ]]; then
    echo "   Success"
  else
    echo "   ERROR: Failed ($result)"
    cat "$response"
    rm -f "$response"
  fi
}

function jira_unwatch_issues() {
  local issues_list=("$@")
  local account_id
  if [ "${#issues_list[@]}" -eq 0 ]; then
    echo "No issues to unwatch." >&2
    return 0
  fi
  account_id=$(jira_get_my_account_id)
  for issue in "${issues_list[@]}"; do
    jira_unwatch_issue "$account_id" "$issue"
  done
}

function jira_stop_watching() {
  local issues_list
  issues_list=$(jira_get_issues)
  array=()
  while IFS='' read -r line; do array+=("$line"); done < <(echo "$issues_list")

  if [ -z "${array[*]}" ]; then
    echo "No issues found to unwatch."
    return 0
  fi

  echo "Found the following issues to unwatch:"
  for issue in "${array[@]}"; do
    echo " - $issue"
  done

  jira_unwatch_issues "${array[@]}"
}
