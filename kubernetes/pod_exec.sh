#!/bin/bash


function kubectl_run_command() {
  local pod_name="$1"
  shift
  kubectl exec -it "$pod_name" -- "$@"
}

function kubectl_exec_with_bash() {
  kubectl_run_command "$@" /bin/bash
}

alias ke='kubectl_exec_with_bash'
