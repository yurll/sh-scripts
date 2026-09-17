#!/usr/bin/env bash
# shellcheck source=/dev/null

BB_RESPONSE_FILE="bb_response.txt"
BRANCH_FILE="bb_create_prs.lock"
PRS_FILE="bb_prs.txt"
CALLER_DIR="$(pwd)"

if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

temp_branch="side/$BB_AUTHOR/temp-branch"


if [ ! -f "$BB_TOKEN_FILE" ]; then
  echo "[WARNING] Script 'bitbucket/branch_update' has no credentials"
  echo "Please create a file $BB_TOKEN_FILE with the following content:"
  echo "export BB_TOKEN=\"<your-bitbucket-token>\""
  return
fi


function bb_create_temp_branch() {
  git checkout -b "$temp_branch"
}

function bb_clone_pr() {
  # example usage: bb_clone_pr v10.10.10,v20.20.0
  # example usage: bb_clone_pr v3300.10.0,v3300.20.0 abcd1234
  local branches="$1"
  local commit_hash="$2"
  if [ -z "$branches" ]; then
    echo "[WARN] No branches provided. Cloning PR for all branches in BB_BRANCH_LIST_SET..."
    echo "[WARN] Branches in BB_BRANCH_LIST_SET: ${BB_BRANCH_LIST_SET[*]}"
  else
    echo "[INFO] Cloning PR for branches: $branches"
    if [ -n "${ZSH_VERSION:-}" ]; then
      IFS=',' read -r -A BB_BRANCH_LIST_SET <<< "$branches"
    else
      IFS=',' read -r -a BB_BRANCH_LIST_SET <<< "$branches"
    fi
  fi
  if [ -z "$commit_hash" ]; then
    commit_hash=$(git rev-parse HEAD)
    echo "[WARN] No commit hash provided. Using current commit hash: $commit_hash"
  else
    echo "[INFO] Cloning PR for commit hash: $commit_hash"
  fi
  git checkout -b "$temp_branch"
  git cherry-pick "$commit_hash"
  bb_create_prs "$commit_hash"
}


function bb_create_prs() {
  local ticket_id title commit_hash commit_message from_cherry_pick
  from_cherry_pick=false


    case $# in
        0)
            # bb_create_prs
            commit_hash=$(git rev-parse HEAD)
            commit_message=$(git log -1 --pretty=%B "$commit_hash")
            IFS=':' read -r ticket_id title <<< "$commit_message"

            echo "[INFO] Creating PRs for ticket ID: '$ticket_id' with title: '$title'"
            ;;

        1)
            # bb_create_prs TASK-32
            if [[ "$1" =~ ^[A-Za-z]+-[0-9]+$ ]]; then
                echo "[ERROR] Ticket ID '$1' provided. Please provide a title."
                echo "Usage: bb_create_prs $1 \"New Title\""
                return 1
            fi

            # bb_create_prs 22c19e2
            commit_hash="$1"

            if ! git cat-file -e "${commit_hash}^{commit}" 2>/dev/null; then
                echo "[ERROR] '$commit_hash' is not a valid commit."
                return 1
            fi

            commit_message=$(git log -1 --pretty=%B "$commit_hash")
            from_cherry_pick=true
            IFS=':' read -r ticket_id title <<< "$commit_message"

            echo "[INFO] Using commit: '$commit_hash'"
            echo "[INFO] Creating PRs for ticket ID: '$ticket_id' with title: '$title'"
            ;;

        2)
            # bb_create_prs TASK-32 "New Title"
            ticket_id="$1"
            title="$2"
            commit_hash=$(git rev-parse HEAD)

            echo "[INFO] Using provided ticket ID: '$ticket_id' and title: '$title'"
            ;;

        3)
            # bb_create_prs TASK-32 "New Title" 22c19e2
            ticket_id="$1"
            title="$2"
            commit_hash="$3"
            from_cherry_pick=true

            if ! git cat-file -e "${commit_hash}^{commit}" 2>/dev/null; then
                echo "[ERROR] '$commit_hash' is not a valid commit."
                return 1
            fi

            echo "[INFO] Using provided ticket ID: '$ticket_id', title: '$title', commit: '$commit_hash'"
            ;;

        *)
            echo "[ERROR] Invalid number of arguments."
            echo 'Usage: bb_create_prs [TICKET_ID "Title"] [commit_hash]'
            return 1
            ;;
    esac

    echo "[INFO] Commit hash: '$commit_hash'"
    echo "[INFO] PR will be created for the following branches [set in BB_BRANCH_LIST_SET]: ${BB_BRANCH_LIST_SET[*]}"

  local IGNORED_PATHS_REGEX=${IGNORED_PATHS_REGEX:-^$}
  IGNORED_PATHS_REGEX="$IGNORED_PATHS_REGEX|$BRANCH_FILE|$PRS_FILE|$BB_RESPONSE_FILE"
  if git status --porcelain | grep -qvE "${IGNORED_PATHS_REGEX:-^$}"; then
    echo "[ERROR]: Working tree is not clean. Are you sure you added all changes?" >&2
    echo "[ERROR]: If these changes are not relevant, you can ignore them by adding their paths to the IGNORED_PATHS_REGEX variable" >&2
    return 1
  fi
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  source "$BB_TOKEN_FILE"
  echo "DEBUG: brach_file: $BRANCH_FILE"
  echo "Current working dir: $(pwd)"
  if [ -f "$BRANCH_FILE" ]; then
    echo "DEBUG: if"
    echo "Lock file exists. Continuing from where it left off..."
    bb_continue=true
    current_branches=()
    while IFS= read -r line; do
        current_branches+=("$line")
    done < "$BRANCH_FILE"
  else
    echo "DEBUG: else"
    if [[ "$current_branch" != "$temp_branch" && "$from_cherry_pick" != true ]]; then
      echo "Please switch to $temp_branch branch"
      return
    fi
    echo "Creating lock file $BRANCH_FILE"
    echo "Creating in: $CALLER_DIR"
    printf "%s\n" "${BB_BRANCH_LIST_SET[@]}" > "$BRANCH_FILE"
    current_branches=("${BB_BRANCH_LIST_SET[@]}")
  fi

  reponame=$(basename "$(git rev-parse --show-toplevel)")
  for branch in "${current_branches[@]}"; do
    side_branch="side/$branch/$BB_AUTHOR/$ticket_id"
    if [ -z "${bb_continue}" ]; then
      echo "[INFO] Switching to branch '$branch' and creating side branch '$side_branch'..."
      if ! git checkout "$branch"; then
        echo "[ERROR] Failed to checkout branch '$branch'. Please ensure it exists."
        echo "[ERROR] Or validate BB_BRANCH_LIST_SET parameter in .env file. Current value: ${BB_BRANCH_LIST_SET[*]}"
        return 1
      fi
      git pull origin "$branch"
      git checkout -b "$side_branch"
      if ! git cherry-pick "$commit_hash"; then
        echo "[WARNING] Cherry-pick failed for branch '$side_branch'. Please resolve conflicts and try again."
        echo "[WARNING]   You have to resolve conflicts and run either:"
        echo "[WARNING]     git cherry-pick --continue"
        echo "[WARNING]     git cherry-pick --abort"
        return
      fi
    fi
    unset bb_continue
    git push origin "$side_branch"
    echo "Creating PR from '$side_branch' to '$branch' with title '$ticket_id: $title'..."
    payload_data=$(cat <<-EOD
    {
      "title": "$ticket_id: $title",
      "description": "",
      "source": {
        "branch": {
          "name": "$side_branch"
        },
        "repository": {
          "full_name": "$BB_WORKSPACE/$reponame"
        }
      },
      "destination": {
        "branch": {
          "name": "$branch"
        }
      },
      "reviewers": [],
      "close_source_branch": true
    }
EOD
    )
    response_code=$(curl -s "https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$reponame/pullrequests" \
                    --user "$BB_EMAIL:$BB_TOKEN" --request POST --header 'Content-Type: application/json' \
                    --data "$payload_data" --output "$BB_RESPONSE_FILE" --write-out '%{http_code}')
    if [ "$response_code" != "201" ]; then
      echo -e "\n\n[ERROR] Failed to create PR: code: $response_code\n\n"
      echo -e "[DEBUG] URL: https://api.bitbucket.org/2.0/repositories/$BB_WORKSPACE/$reponame/pullrequests"
      jq . "$BB_RESPONSE_FILE"
    else
      echo -e "\n\n[INFO] PR created successfully!"
      jq .links.html.href "$BB_RESPONSE_FILE" | tee -a "$PRS_FILE"
    fi
    grep -Fxv "$branch" "$BRANCH_FILE" > "${BRANCH_FILE}.tmp" && mv "${BRANCH_FILE}.tmp" "$BRANCH_FILE"
  done
  unset BB_TOKEN
  git checkout "$temp_branch"
  echo "-----------------------------"
  cat "$PRS_FILE" | while read -r pr_url; do
    echo "PR URL: ${pr_url//\"/}"
  done
  rm -f "$PRS_FILE" "$BRANCH_FILE" "${BRANCH_FILE}.tmp" "$BB_RESPONSE_FILE"
  echo "-----------------------------"
  echo "All PRs created successfully!"
  echo "You can now delete the temporary branch '$temp_branch' if you wish."
  echo "To clean up, run: bb_cleanup"
}

function bb_cleanup() {
  git checkout "$(bb_get_default_branch)"
  git branch -D "$temp_branch"
}

function bb_get_default_branch() {
  git remote show origin | sed -n '/HEAD branch/s/.*: //p'
}

function bb_test() {
  echo "Testing..."
  echo "Author: $BB_AUTHOR"
  echo "Username: $BB_EMAIL"
  echo "Workspace: $BB_WORKSPACE"
  echo "Token file: $BB_TOKEN_FILE"

  for branch in "${BB_BRANCH_LIST_SET[@]}"; do
    side_branch="side/$BB_AUTHOR/$branch/$ticket_id"
    echo "Creating PR from '$side_branch' to '$branch'..."
  done
}
