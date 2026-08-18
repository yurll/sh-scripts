#!/usr/bin/env bash

if [ -f "$(dirname "$0")/.env" ]; then
  set -a
  source "$(dirname "$0")/.env"
  set +a
fi

aws_launch_instance_from_ami() {
    local ami_id="$1"
    local instance_type=${2:-t2.micro}
    local key_name=$AWS_DEFAULT_SSH_KEY_NAME
    local security_group_ids=$SECURITY_GROUP_IDS
    local subnet_id=$SUBNET_ID
    local instance_name=$AWS_DEFAULT_INSTANCE_NAME

    echo "Command to execute: aws ec2 run-instances --image-id $ami_id --instance-type $instance_type --key-name $key_name --security-group-ids $security_group_ids --subnet-id $subnet_id --count 1 --tag-specifications ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}] --query Instances[*].{InstanceId: InstanceId, PrivateIp: PrivateIpAddress} --output text"

    instance_data=$(aws ec2 run-instances \
        --image-id "$ami_id" \
        --instance-type "$instance_type" \
        --key-name "$key_name" \
        --security-group-ids "$security_group_ids" \
        --subnet-id "$subnet_id" \
        --count 1 \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance_name}]" \
        --query "Instances[*].{InstanceId: InstanceId, PrivateIp: PrivateIpAddress}" \
        --output text
    )
    echo "Launched instance with ID: $instance_data"
}
