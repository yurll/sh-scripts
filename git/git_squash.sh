#!/usr/bin/env bash

# Squash last N commits into 1, using the Nth commit's subject as the final message.
# Usage:
#   gsquashn 5
# Optional:
#   KEEP_BODY=1 gsquashn 5     # keep Nth commit body as well
gsquashn() (
  set -euo pipefail

  # If caller has xtrace on, disable it inside this function to avoid polluting rebase todo.
  local _xtrace_was_on=0
  case "$-" in
    *x*) _xtrace_was_on=1; set +x ;;
  esac
  # Also ensure xtrace doesn't ever go to stdout in here
  export BASH_XTRACEFD=2

  local N="${1:-}"
  if [[ -z "${N}" || ! "${N}" =~ ^[0-9]+$ || "${N}" -lt 2 ]]; then
    echo "Usage: gsquashn <N>   (N must be an integer >= 2)" >&2
    return 2
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not inside a git repository." >&2
    return 2
  }

  local COUNT
  COUNT="$(git rev-list --count HEAD)"
  if (( COUNT < N )); then
    echo "Error: HEAD has only ${COUNT} commits; cannot squash last ${N}." >&2
    return 2
  fi

  local IGNORED_PATHS_REGEX=".vscode|.idea"
  if [[ -n "$(git status --porcelain | grep -vE ${IGNORED_PATHS_REGEX})" ]]; then
    echo "Error: working tree is not clean. Commit/stash changes first." >&2
    return 2
  fi

  local BASE_COMMIT SUBJECT BODY
  BASE_COMMIT="$(git rev-parse "HEAD~$((N-1))")"
  SUBJECT="$(git log -1 --format=%s "${BASE_COMMIT}")"
  BODY="$(git log -1 --format=%b "${BASE_COMMIT}")"

  local TODO_FILE
  TODO_FILE="$(mktemp)"
  trap 'rm -f "${TODO_FILE}"' EXIT

  # Build the todo file (omit subjects for the squash lines to avoid any weird parsing)
  {
    echo "pick ${BASE_COMMIT} ${SUBJECT}"
    while read -r c; do
      echo "fixup ${c}"
    done < <(git rev-list --reverse "${BASE_COMMIT}..HEAD")
  } > "${TODO_FILE}"

  local OLD_GIT_SEQUENCE_EDITOR="${GIT_SEQUENCE_EDITOR:-}"
  export GIT_SEQUENCE_EDITOR="sh -c 'cat \"${TODO_FILE}\" > \"\$1\"' --"

  if ! git rebase -i "HEAD~${N}"; then
    echo "Rebase stopped (likely conflicts). Resolve them, then run: git rebase --continue" >&2
    return 1
  fi

  # Restore editor setting
  if [[ -n "${OLD_GIT_SEQUENCE_EDITOR}" ]]; then
    export GIT_SEQUENCE_EDITOR="${OLD_GIT_SEQUENCE_EDITOR}"
  else
    unset GIT_SEQUENCE_EDITOR
  fi

  # Final message: Nth commit subject (optionally keep its body)
  if [[ "${KEEP_BODY:-0}" == "1" && -n "${BODY}" ]]; then
    git commit --amend -m "${SUBJECT}" -m "${BODY}" --no-edit >/dev/null
  else
    git commit --amend -m "${SUBJECT}" --no-edit >/dev/null
  fi

  echo "Done: squashed last ${N} commits into 1 with message:"
  echo "  ${SUBJECT}"
  echo "  You can now run: git push --force-with-lease"

  # Re-enable xtrace if it was on (mostly cosmetic; subshell ends anyway)
  if (( _xtrace_was_on )); then set -x; fi
)
