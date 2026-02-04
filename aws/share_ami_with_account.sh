#!/usr/bin/env bash

# This script shares an AWS AMI with a specific AWS account.
# Usage:
#   share_ami_with_account <ami_id> <account_id>
# Ensure AWS CLI is installed and configured with the necessary permissions.

function share_ami_with_account() {
    local ami_id="$1"
    local account_id="$2"

    # Check if the AMI ID is provided
    if [ -z "$ami_id" ]; then
        echo "Error: AMI ID is required."
        return 1
    fi

    # Check if the account ID is provided
    if [ -z "$account_id" ]; then
        echo "Error: Account ID is required."
        return 1
    fi

    # Share the AMI with the specified account ID
    aws ec2 modify-image-attribute --image-id "$ami_id" --launch-permission "Add=[{UserId=$account_id}]"
}
