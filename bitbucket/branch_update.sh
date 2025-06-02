#!/bin/bash
# shellcheck source=/dev/null

BRANCH_FILE="bb_create_prs.lock"
CALLER_DIR="$(pwd)"

if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

temp_branch="side/$AUTHOR/temp-branch"


if [ ! -f "$TOKEN_FILE" ]; then
  echo "Please create a file $TOKEN_FILE with the following content:"
  echo "export BB_TOKEN=\"<your-bitbucket-token>\""
  return
fi


function bb_create_temp_branch() {
  git checkout -b "$temp_branch"
}


function bb_create_prs() {
  if [ -z "$1" ]; then
      echo "Please provide a ticket ID"
      return
  fi
  if [ -z "$2" ]; then
      echo "Please provide a title"
      return
  fi
  ticket_id=$1
  title=$2
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  commit_hash=$(git rev-parse HEAD)
  source "$TOKEN_FILE"
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
    if [ "$current_branch" != "$temp_branch" ]; then
      echo "Please switch to $temp_branch branch"
      # return
    fi
    echo "Creating lock file $BRANCH_FILE"
    echo "Creating in: $CALLER_DIR"
    echo "myfile" > "myfile"
    printf "%s\n" "${BRANCH_LIST_SET[@]}" > "$BRANCH_FILE"
    current_branches=("${BRANCH_LIST_SET[@]}")
  fi

  reponame=$(basename "$(git rev-parse --show-toplevel)")
  for branch in "${current_branches[@]}"; do
    side_branch="side/$AUTHOR/$branch/$ticket_id"
    if [ -z "${bb_continue}" ]; then
      git checkout "$branch"
      git pull origin "$branch"
      git checkout -b "$side_branch"
      if ! git cherry-pick "$commit_hash"; then
        echo "Cherry-pick failed for branch '$side_branch'. Please resolve conflicts and try again."
        break
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
          "full_name": "$WORKSPACE/$reponame"
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
    response_code=$(curl -s "https://api.bitbucket.org/2.0/repositories/$WORKSPACE/$reponame/pullrequests" \
                    --user "$USERNAME:$BB_TOKEN" --request POST --header 'Content-Type: application/json' \
                    --data "$payload_data" --output response.txt --write-out '%{http_code}')
    if [ "$response_code" != "201" ]; then
      echo -e "\n\nERROR: Failed to create PR: code: $response_code\n\n"
      jq . response.txt
    else
      echo -e "\n\nPR created successfully\!"
      jq .links.html.href response.txt
    fi
    grep -Fxv "$branch" "$BRANCH_FILE" > "${BRANCH_FILE}.tmp" && mv "${BRANCH_FILE}.tmp" "$BRANCH_FILE"
  done
  unset BB_TOKEN
  rm -f response.txt
  rm -f "$BRANCH_FILE"
  git checkout "$temp_branch"
}

function bb_cleanup() {
  git checkout "$(bb_get_default_branch)"
  git branch -D "$temp_branch"
  git push origin --delete "$temp_branch"
}

function bb_get_default_branch() {
  git remote show origin | sed -n '/HEAD branch/s/.*: //p'
}

function bb_test() {
  echo "Testing..."
  echo "Author: $AUTHOR"
  echo "Username: $USERNAME"
  echo "Workspace: $WORKSPACE"
  echo "Token file: $TOKEN_FILE"

  for branch in "${BRANCH_LIST_SET[@]}"; do
    side_branch="side/$AUTHOR/$branch/$ticket_id"
    echo "Creating PR from '$side_branch' to '$branch'..."
  done
}
