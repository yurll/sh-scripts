#!/usr/bin/env bash

# Allow comments at terminal
setopt interactivecomments

# Init McFly
eval "$(mcfly init zsh)"

# Homebrew preferred:
export PATH="/opt/homebrew/bin:$PATH"

function ping_any_url() {
    echo "$1" | sed -E 's/https?:\/\/|\/.*//g' | xargs command ping
}



# HISTORY SETTINGS
export HISTFILE=~/.zsh_history
export HISTSIZE=10000000
export SAVEHIST=10000000
export HISTTIMEFORMAT='[%F %T] '
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY

# GIT SETTINGS
git config --global alias.ll "log --oneline"
git config --global alias.last "log -1 HEAD --stat"
git config --global push.autoSetupRemote true

# ALIASES
alias ls="ls --color=auto"
alias ll="ls -lah"
alias grep="grep --color=auto"
alias mkdir="mkdir -pv"

alias ping="ping_any_url"
