#!/usr/bin/env bash

### Usage:
### You can add this script to your .bashrc or .zshrc file.
### Or you can source this script in your .bashrc or .zshrc file:
### > source /path/to/awsssh.sh
###
### You have to be logged in to the AWS console to run this script.
### > aws sso login
### > awsssh <instance_id> [--region <aws_region>] [--user <ssh_user>] [--key <ssh_key>]

script_path="${BASH_SOURCE[0]:-${(%):-%x}}"
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"
env_file="$script_dir/.env"
if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    . "$env_file"
    set +a
fi

function get_ip_by_instance_id() {
    local instance_id=$1
    local region=$2
    local region_args=()
    if [[ -n "$region" ]]; then
        region_args=(--region "$region")
    fi
    if [[ -z "$instance_id" ]]; then
        echo "Usage: get_ip_by_instance_id <instance_id> [region]"
        return 1
    fi
    aws ec2 describe-instances --instance-ids "${instance_id}" "${region_args[@]}" --query "Reservations[*].Instances[*].PrivateIpAddress" --output text
}

function ssh_to_aws_instance() {
    local ssh_key=""
    local ssh_user=""
    local aws_region=""
    local instance_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --region)
                [[ -n "$2" ]] || { echo "Error: --region requires a value"; return 1; }
                aws_region="$2"
                shift 2
                ;;
            --user)
                [[ -n "$2" ]] || { echo "Error: --user requires a value"; return 1; }
                ssh_user="$2"
                shift 2
                ;;
            --key)
                [[ -n "$2" ]] || { echo "Error: --key requires a value"; return 1; }
                ssh_key="$2"
                shift 2
                ;;
            --help)
                echo "Usage: awsssh [--region <aws_region>] [--user <ssh_user>] [--key <ssh_key>] <instance_id>"
                return 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1"
                return 1
                ;;
            *)
                instance_id="$1"
                shift
                ;;
        esac
    done
    SSH_KEY=${ssh_key:-$AWS_DEFAULT_SSH_KEY}
    SSH_USER=${ssh_user:-ec2-user}
    FALLBACK_SSH_USER="root"
    echo "Using SSH Key: $SSH_KEY"
    if [[ -z "$instance_id" ]]; then
        echo "Usage: ssh_to_instance <instance_id> [--region <aws_region>] [--user <ssh_user>] [--key <ssh_key>]"
        return 1
    fi
    if [[ ! "$instance_id" =~ ^i-.*$ ]]; then
        echo "Wrong instance_id: $instance_id. Instance ID should start with 'i-' and be followed by 8-17 alphanumeric characters."
        return 1
    fi
    echo "Fetching IP address for instance ID: $instance_id in region: ${aws_region}"
    ip=$(get_ip_by_instance_id "$instance_id" "$aws_region")
    if [[ -z "$ip" ]]; then
        echo "Failed to get the IP address of the instance $instance_id."
        return 1
    fi
    echo "Connecting to instance $instance_id at IP $ip with user $SSH_USER..."
    ssh -o "StrictHostKeyChecking no" -i "$SSH_KEY" "$SSH_USER"@"$ip" || ssh -i "$SSH_KEY" "$FALLBACK_SSH_USER"@"$ip"
}
alias getip='get_ip_by_instance_id'
alias awsssh='ssh_to_aws_instance'
