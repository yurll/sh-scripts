#!/bin/bash

### Usage:
### You can add this script to your .bashrc or .zshrc file.
### Or you can source this script in your .bashrc or .zshrc file:
### > source /path/to/awsssh.sh
###
### You have to be logged in to the AWS console to run this script.
### > aws sso login
### > awsssh <instance_id>

function get_ip_by_instance_id() {
    if [[ -z "$1" ]]; then
        echo "Usage: get_ip_by_instance_id <instance_id>"
        return 1
    fi
    aws ec2 describe-instances --instance-ids "$1" --query "Reservations[*].Instances[*].PrivateIpAddress" --output text
}

function ssh_to_aws_instance() {
    if [[ -z "$1" ]]; then
        echo "Usage: ssh_to_instance <instance_id>"
        return 1
    fi
    if [[ ! "$1" =~ ^i-.*$ ]]; then
        echo "Wrong instance_id: $1. Instance ID should start with 'i-' and be followed by 8-17 alphanumeric characters."
        return 1
    fi
    ip=$(get_ip_by_instance_id "$1")
    if [[ -z "$ip" ]]; then
        echo "Failed to get the IP address of the instance $1."
        return 1
    fi
    ssh -i ~/aws_algosec.pem ec2-user@"$ip"
}
alias getip='get_ip_by_instance_id'
alias awsssh='ssh_to_aws_instance'
