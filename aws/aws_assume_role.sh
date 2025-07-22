#!/bin/bash

function aws_assume_role() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    if [[ ! "$1" =~ ^[0-9]{12}$ ]]; then
        echo "Wrong account: $1. Must be exactly 12 digits."
        return 1
    fi
    if [[ -z "$2" ]]; then
        echo "Please provide a role name."
        return 1
    fi
    read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN < <(
        aws sts assume-role \
        --role-arn "arn:aws:iam::${1}:role/${2}" \
        --role-session-name "${2}" \
        --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
        --output text
    )
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    aws sts get-caller-identity
}
