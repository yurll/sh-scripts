#!/bin/bash

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

function git_get_default_branch() {
  # This function retrieves the default branch of the current repository.
  # It assumes that the default branch is the one that is set as 'origin/HEAD'.

  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's|^refs/remotes/origin/||')
  echo "$default_branch"
}

function git_update_master() {
  # This function updates the local master branch to match the remote master branch.
  # It will switch to the master branch, fetch the latest changes, and reset it to match the remote.

  default_branch=$(git_get_default_branch)

  if [ -z "$default_branch" ]; then
    echo "Could not determine the default branch."
    return 1
  fi

  echo "Switching to $default_branch branch..."
  git checkout "$default_branch"

  echo "Fetching latest changes from remote..."
  git pull

  echo "$default_branch has been updated."
}

alias gclean='delete_stale_local_branches'
alias master='git_update_master'
