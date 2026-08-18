#!/usr/bin/env bash

bb_set_pr_status() {
  local pr_url="${1:-}"
  local state="${2:-}"

  [[ -n "$pr_url" && -n "$state" ]] || {
    echo "usage: bb_set_pr_status <bitbucket-pr-url> <SUCCESSFUL|FAILED|INPROGRESS|STOPPED>" >&2
    return 1
  }

  [[ -n "$BITBUCKET_USERNAME" && -n "$BITBUCKET_APP_PASSWORD" ]] || {
    echo "BITBUCKET_USERNAME and BITBUCKET_APP_PASSWORD must be set" >&2
    return 1
  }

  case "$state" in
    SUCCESS|SUCCESSFUL) state="SUCCESSFUL" ;;
    FAILED|INPROGRESS|STOPPED) ;;
    *)
      echo "invalid state: $state" >&2
      echo "allowed: SUCCESSFUL, FAILED, INPROGRESS, STOPPED" >&2
      return 1
      ;;
  esac

  command -v jq >/dev/null 2>&1 || {
    echo "jq is required" >&2
    return 1
  }

  local parsed
  parsed="$(printf '%s\n' "$pr_url" \
    | sed -E 's#https://bitbucket\.org/([^/]+)/([^/]+)/pull-requests/([0-9]+).*#\1 \2 \3#')"

  local workspace repo pr_id
  read -r workspace repo pr_id <<<"$parsed"

  [[ -n "$workspace" && -n "$repo" && -n "$pr_id" ]] || {
    echo "failed to parse PR URL: $pr_url" >&2
    return 1
  }

  local auth api pr_json commit refname statuses_json
  auth="${BITBUCKET_USERNAME}:${BITBUCKET_APP_PASSWORD}"
  api="https://api.bitbucket.org/2.0/repositories/${workspace}/${repo}"

  pr_json="$(curl -fsS -u "$auth" \
    -H 'Accept: application/json' \
    "${api}/pullrequests/${pr_id}")" || return 1

  commit="$(jq -r '.source.commit.hash // empty' <<<"$pr_json")"
  refname="$(jq -r '.source.branch.name // empty' <<<"$pr_json")"

  [[ -n "$commit" && -n "$refname" ]] || {
    echo "failed to resolve PR source commit or branch" >&2
    return 1
  }

  statuses_json="$(curl -fsS -u "$auth" \
    -H 'Accept: application/json' \
    "${api}/pullrequests/${pr_id}/statuses?pagelen=100")" || return 1

  jq -r '.values[].key' <<<"$statuses_json" | sort -u | while read -r key; do
    [[ -n "$key" ]] || continue

    curl -fsS -u "$auth" \
      -X PUT \
      -H 'Accept: application/json' \
      -H 'Content-Type: application/json' \
      "${api}/commit/${commit}/statuses/build/${key}" \
      -d "$(jq -nc \
        --arg key "$key" \
        --arg state "$state" \
        --arg refname "$refname" \
        --arg url "$pr_url" \
        '{key:$key,state:$state,refname:$refname,url:$url}')" >/dev/null

    echo "updated: ${key} -> ${state}"
  done
}
