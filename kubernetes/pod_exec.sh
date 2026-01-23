#!/bin/bash


function kubectl_run_command() {
  local pod_name="$1"
  shift
  kubectl exec -it "$pod_name" -- "$@"
}

function kubectl_exec_with_bash() {
  if [ $# -lt 1 ]; then
    echo "Usage: ke <pod-name> [additional-args]"
    return 1
  fi
  if [ ! "$2" ]; then
    echo "No additional arguments provided, defaulting to bash shell."
    kubectl_run_command "$@" /bin/bash
  else
    echo "Additional arguments: ${@:2}"
    kubectl_run_command "$@"
  fi
}

alias ke='kubectl_exec_with_bash'

function kubectl_run_test_pod() {
  local image="${1:-busybox:latest}"
  local command="${2:-sh}"
  local pod_name="test-pod-$(date +%s)"
  kubectl run -it "$pod_name" --rm --image="$image" --privileged --command -- "$command"
}

alias kei='kubectl_run_test_pod'
