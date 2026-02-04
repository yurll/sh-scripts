#!/usr/bin/env bash

function delete_stale_local_branches() {
  # This function deletes local branches that have been removed from the remote repository.
  # It will not delete branches that are currently checked out or have unmerged changes.

  echo "Fetching latest remote state..."
  git fetch --prune origin

  echo "Finding stale local branches..."
  stale_branches=$(git branch -vv | awk '/ \[.*: gone\]/ {print $1}')

  if [ -z "$stale_branches" ]; then
    echo "No stale branches to delete."
  else
    echo "Removing stale local branches:"
    echo "$stale_branches"
    echo "$stale_branches" | xargs -r git branch -D
  fi
}

function git_delete_branch() {
    git pull origin
    for branch in "$@"; do
        echo "Deleting branch '$branch' locally and remotely..."
        git branch -d "$branch" 2>/dev/null || git branch -D "$branch"
        git push origin --delete "$branch"
    done
}

function git_get_master_branch_name() {
    git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
}

function git_push_with_pull() {
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ $current_branch == "master" || $current_branch == "main" ]]; then
        echo "You are on the '$current_branch' branch. Are you sure you want to continue? (type 'yes' to continue)"
        read -r confirmation
        if [[ $confirmation != "yes" ]]; then
            echo "Aborting git push with pull."
            return
        fi
    fi
    echo "Pulling latest changes for branch '$current_branch'..."
    git pull origin "$current_branch"
    git push origin "$current_branch"
}

function git_set_master_and_pull() {
    local master_branch
    master_branch=$(git_get_master_branch_name)
    git checkout "$master_branch"
    git pull origin "$master_branch"
}

function get_delete_local_branches_which_are_not_remote() {
    git fetch --prune origin
    git branch -vv | awk '/: gone]/{print $1}'
    
}

alias gclean='delete_stale_local_branches'
alias ga="git add"
alias gb="git branch"
alias gc="git commit -m"
alias gco="git checkout"
alias gs="git status"
alias grmb="git_delete_branch"
alias gp="git_push_with_pull"
alias master="git_set_master_and_pull"
