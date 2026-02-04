#!/usr/bin/env bash
# shellcheck source=/dev/null

command -v kubectl >/dev/null 2>&1 || {
  echo "[WARNING] 'kubectl' is not installed"
  return
}

autoload -Uz compinit
compinit
source <(kubectl completion zsh)
