#!/usr/bin/env bash

ami_latest_usage() {
  local region=""
  local input="${1:-amis.txt}"

  usage() {
    cat <<EOF
Usage:
  ami_latest_usage [AMI_ID|AMI_FILE]
  ami_latest_usage -r REGION [AMI_ID|AMI_FILE]

Examples:
  ami_latest_usage ami-1234567890abcdef0
  ami_latest_usage amis.txt
  ami_latest_usage -r eu-west-1 ami-1234567890abcdef0
  ami_latest_usage -r eu-west-1 amis.txt

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

  shift $((OPTIND - 1))
  input="${1:-$input}"

  local aws_region_args=()
  if [[ -n "$region" ]]; then
    aws_region_args=(--region "$region")
  fi

  _ami_latest_usage_get_last_launched() {
    local ami="$1"

    aws ec2 describe-image-attribute \
      "${aws_region_args[@]}" \
      --image-id "$ami" \
      --attribute lastLaunchedTime \
      --query 'LastLaunchedTime.Value' \
      --output text 2>/dev/null
  }

  _ami_latest_usage_print() {
    local ami="$1"
    local last_launched
    local formatted_date

    last_launched="$(_ami_latest_usage_get_last_launched "$ami" || true)"

    if [[ -z "$last_launched" || "$last_launched" == "None" ]]; then
      printf "%-25s %s\n" "$ami" "NOT_FOUND"
    else
      formatted_date="$(date -d "$last_launched" '+%Y %m %d %H:%M:%S' 2>/dev/null || echo "$last_launched")"
      printf "%-25s %s\n" "$ami" "$formatted_date"
    fi
  }

  printf "%-25s %s\n" "AMI" "LAST_LAUNCHED"
  printf "%-25s %s\n" "-------------------------" "-------------------"

  if [[ "$input" =~ ^ami-[a-zA-Z0-9]+$ ]]; then
    _ami_latest_usage_print "$input"
  elif [[ -f "$input" ]]; then
    local ami

    while IFS= read -r ami || [[ -n "$ami" ]]; do
      ami="$(echo "$ami" | xargs)"

      [[ -z "$ami" || "$ami" =~ ^# ]] && continue

      _ami_latest_usage_print "$ami"
    done < "$input"
  else
    echo "Input is neither an AMI ID nor an existing file: $input" >&2
    return 1
  fi
}
