#!/usr/bin/env bash

ami_describe() {
  local region=""
  local input="${1:-amis.txt}"

  local is_file=false
  if [[ -f "$input" ]]; then
    is_file=true
  fi

  usage() {
    cat <<EOF
Usage:
  ami_describe [AMI_ID|AMI_FILE]
  ami_describe -r REGION [AMI_ID|AMI_FILE]
Examples:
  ami_describe ami-1234567890abcdef0
  ami_describe amis.txt
  ami_describe -r eu-west-1 ami-1234567890abcdef0
  ami_describe -r eu-west-1 amis.txt
Notes:
  If region is not provided, aws cli will use its configured/default region.
  If input is not provided, function uses ./amis.txt.
  This reads AMI lastLaunchedTime, matching the EC2 AMI console.
EOF
  }

    OPTIND=1
    while getopts ":r:h" opt; do
        case "$opt" in
            r) region="$OPTARG" ;;
            h)
                usage
                return 0
                ;;
            \?)
                echo "Unknown option: -$OPTARG" >&2
                usage
                return 1
                ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                usage
                return 1
                ;;
        esac
    done

    printf "%-22s %-50s %-50s\n" "AMI ID" "TAG: Name" "AMI Name"

    if [[ "$is_file" == true ]]; then
        xargs -n 100 aws ec2 describe-images \
            --image-ids \
            --query 'Images[].[ImageId, Tags[?Key==`Name`].Value | [0], Name]' \
            --output text \
            < "$input" |
        while IFS=$'\t' read -r ami_id tag_name ami_name; do
            [[ "$tag_name" == "None" ]] && tag_name="-"
            [[ "$ami_name" == "None" ]] && ami_name="-"

            printf "%-22s %-50.50s %-50.50s\n" \
                "$ami_id" "$tag_name" "$ami_name"
        done
    else
        local ami="$input"

        aws ec2 describe-images \
            --image-ids "$ami" \
            --query 'Images[].[ImageId, Tags[?Key==`Name`].Value | [0], Name]' \
            --output text |
        while IFS=$'\t' read -r ami_id tag_name ami_name; do
            [[ "$tag_name" == "None" ]] && tag_name="-"
            [[ "$ami_name" == "None" ]] && ami_name="-"

            printf "%-22s %-50.50s %-50.50s\n" \
                "$ami_id" "$tag_name" "$ami_name"
        done
    fi
}

