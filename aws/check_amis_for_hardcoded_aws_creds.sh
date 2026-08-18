#!/usr/bin/env bash

# =============================================================================
# Source-able AMI hardcoded AWS credentials checker
#
# Usage:
#   source ./ami_creds_check.sh
#
#   check_amis_for_hardcoded_aws_creds
#   check_amis_for_hardcoded_aws_creds -f amis.txt
#   check_amis_for_hardcoded_aws_creds -a ami-0123456789abcdef0
#   check_amis_for_hardcoded_aws_creds -f amis.txt -o report.tsv
#
# Required tools:
#   aws
#   jq
#   ssh
#
# Required AWS permissions:
#   ec2:DescribeImages
#   ec2:DescribeInstances
#   ec2:RunInstances
#   ec2:TerminateInstances
#   ec2:CreateTags
# =============================================================================

ami_creds_escape_tsv() {
  local value="${1:-}"
  value="${value//$'\t'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  echo "$value"
}

ami_creds_cleanup_instance() {
  local instance_id="${1:-}"

  if [[ -n "$instance_id" && "$instance_id" != "null" && "$instance_id" != "None" ]]; then
    echo "Cleaning up instance: $instance_id" >&2
    aws ec2 terminate-instances \
      --instance-ids "$instance_id" \
      >/dev/null || true
  fi
}

ami_creds_get_ami_metadata() {
  local ami="$1"

  aws ec2 describe-images \
    --image-ids "$ami" \
    --query 'Images[0].{Name:Name,Description:Description}' \
    --output json 2>/dev/null || echo '{}'
}

ami_creds_get_last_ami_usage() {
  local ami="$1"

  local last_usage

  last_usage="$(
    aws ec2 describe-instances \
      --filters "Name=image-id,Values=${ami}" \
      --query 'Reservations[].Instances[].LaunchTime' \
      --output text 2>/dev/null \
    | tr '\t' '\n' \
    | grep -v '^None$' \
    | grep -v '^$' \
    | sort \
    | tail -n 1 || true
  )"

  if [[ -z "$last_usage" ]]; then
    echo "not found"
  else
    echo "$last_usage"
  fi
}

ami_creds_launch_instance() {
  local ami="$1"

  local subnet_id="${SUBNET_ID:-subnet-12345678903abcdef}"
  local security_group_ids="${SECURITY_GROUP_IDS:-sg-12345678903abcdef}"
  local key_name="${AWS_DEFAULT_SSH_KEY_NAME:-keyname}"
  local instance_type="${INSTANCE_TYPE:-t3.micro}"
  local tag_name="${AMI_CHECK_TAG_NAME:-ami-hardcoded-creds-check}"
  local date_now

  date_now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  aws ec2 run-instances \
    --image-id "$ami" \
    --instance-type "$instance_type" \
    --subnet-id "$subnet_id" \
    --security-group-ids $security_group_ids \
    --key-name "$key_name" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${tag_name}},{Key=CreatedBy,Value=ami-hardcoded-creds-check},{Key=CreatedAt,Value=${date_now}},{Key=SourceAmi,Value=${ami}}]" \
    --query 'Instances[0].InstanceId' \
    --output text
}

ami_creds_get_instance_ip() {
  local instance_id="$1"
  local use_public_ip="${USE_PUBLIC_IP:-false}"

  if [[ "$use_public_ip" == "true" ]]; then
    aws ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text
  else
    aws ec2 describe-instances \
      --instance-ids "$instance_id" \
      --query 'Reservations[0].Instances[0].PrivateIpAddress' \
      --output text
  fi
}

ami_creds_try_ssh_user() {
  local ip="$1"
  local user="$2"

  local key_name="${AWS_DEFAULT_SSH_KEY_NAME:-keyname}"
  local ssh_key_path="${AWS_DEFAULT_SSH_KEY_PATH:-$HOME/.ssh/${key_name}.pem}"
  local ssh_timeout_seconds="${SSH_TIMEOUT_SECONDS:-8}"

  echo "Trying SSH: user=${user}, ip=${ip}, key=${ssh_key_path}" >&2

  ssh \
    -n \
    -i "$ssh_key_path" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout="$ssh_timeout_seconds" \
    -o BatchMode=yes \
    "${user}@${ip}" \
    "echo ok"
}

ami_creds_wait_for_ssh() {
  local ip="$1"

  local ssh_retries="${SSH_RETRIES:-30}"
  local ssh_retry_sleep_seconds="${SSH_RETRY_SLEEP_SECONDS:-10}"

  local attempt
  local user

  # zsh-safe split of space-delimited users into an array
  local -a ssh_users_array
  read -r -a ssh_users_array <<< "${AWS_DEFAULT_SSH_USERS:-ec2-user ubuntu root}"

  for attempt in $(seq 1 "$ssh_retries"); do
    echo "SSH attempt ${attempt}/${ssh_retries} to ${ip}" >&2

    for user in "${ssh_users_array[@]}"; do
      if ami_creds_try_ssh_user "$ip" "$user" >/dev/null; then
        echo "$user"
        return 0
      fi
    done

    sleep "$ssh_retry_sleep_seconds"
  done

  return 1
}

ami_creds_scan_credentials() {
  local ip="$1"
  local user="$2"

  local key_name="${AWS_DEFAULT_SSH_KEY_NAME:-keyname}"
  local ssh_key_path="${AWS_DEFAULT_SSH_KEY_PATH:-$HOME/.ssh/${key_name}.pem}"
  local ssh_timeout_seconds="${SSH_TIMEOUT_SECONDS:-8}"

  ssh \
    -i "$ssh_key_path" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout="$ssh_timeout_seconds" \
    -o BatchMode=yes \
    "${user}@${ip}" \
    'bash -s' <<'REMOTE_SCRIPT'
set +e

echo "Remote scan started on $(hostname)" >&2

RESULTS=""

add_result() {
  local item="$1"

  if [[ -z "$RESULTS" ]]; then
    RESULTS="$item"
  else
    RESULTS="${RESULTS}; ${item}"
  fi
}

# ---------------------------------------------------------------------------
# 1. Check standard AWS credential files first. This is very fast.
# ---------------------------------------------------------------------------

echo "Checking standard AWS credential files..." >&2

STANDARD_FILES=""

for f in \
  /root/.aws/credentials \
  /root/.aws/config \
  /home/*/.aws/credentials \
  /home/*/.aws/config
do
  if sudo test -f "$f"; then
    STANDARD_FILES="${STANDARD_FILES}${f},"
  fi
done

STANDARD_FILES="${STANDARD_FILES%,}"

if [[ -n "$STANDARD_FILES" ]]; then
  add_result "AWS_STANDARD_CREDENTIAL_FILES files=${STANDARD_FILES}"
fi

# ---------------------------------------------------------------------------
# 2. Build a targeted file list instead of grep -R over everything.
# ---------------------------------------------------------------------------

echo "Building candidate file list..." >&2

CANDIDATE_FILE_LIST="/tmp/ami_aws_credential_scan_files.$$"

sudo find /home /root /etc /opt /var/www /var/lib/jenkins /usr/local \
  -xdev \
  \( \
    -path '*/.git' -o \
    -path '*/.svn' -o \
    -path '*/.hg' -o \
    -path '*/node_modules' -o \
    -path '*/vendor' -o \
    -path '*/target' -o \
    -path '*/build' -o \
    -path '*/dist' -o \
    -path '*/coverage' -o \
    -path '*/.cache' -o \
    -path '*/cache' -o \
    -path '*/logs' -o \
    -path '*/log' -o \
    -path '*/tmp' -o \
    -path '*/.m2/repository' -o \
    -path '*/.gradle/caches' -o \
    -path '*/.npm' -o \
    -path '*/.yarn' -o \
    -path '*/docker' -o \
    -path '*/containerd' -o \
    -path '*/overlay2' -o \
    -path '/var/lib/jenkins/jobs/*/builds' -o \
    -path '/var/lib/jenkins/workspace' -o \
    -path '/var/lib/jenkins/workspace/*' -o \
    -path '/var/lib/jenkins/caches' -o \
    -path '/var/lib/jenkins/tools' \
  \) -prune -o \
  -type f \
  -size -5M \
  \( \
    -name '.env' -o \
    -name '.env.*' -o \
    -name 'credentials' -o \
    -name 'config' -o \
    -name '*.conf' -o \
    -name '*.config' -o \
    -name '*.cfg' -o \
    -name '*.ini' -o \
    -name '*.properties' -o \
    -name '*.json' -o \
    -name '*.yaml' -o \
    -name '*.yml' -o \
    -name '*.xml' -o \
    -name '*.txt' -o \
    -name '*.sh' -o \
    -name '*.bash' -o \
    -name '*.bashrc' -o \
    -name '*.profile' -o \
    -name '*.service' -o \
    -name '*.tf' -o \
    -name '*.tfvars' \
  \) \
  -print 2>/dev/null > "$CANDIDATE_FILE_LIST"

CANDIDATE_COUNT="$(wc -l < "$CANDIDATE_FILE_LIST" | tr -d ' ')"
echo "Candidate files: ${CANDIDATE_COUNT}" >&2

# ---------------------------------------------------------------------------
# 3. Search access key ID patterns only in candidate files.
# ---------------------------------------------------------------------------

echo "Scanning for AWS access key ID patterns..." >&2

ACCESS_KEY_MATCHES="$(
  sudo grep -IEon \
    --binary-files=without-match \
    '(^|[^A-Z0-9])(AKIA|ASIA)[A-Z0-9]{16}([^A-Z0-9]|$)' \
    $(cat "$CANDIDATE_FILE_LIST") 2>/dev/null \
  | head -n 50
)"

if [[ -n "$ACCESS_KEY_MATCHES" ]]; then
  COUNT="$(echo "$ACCESS_KEY_MATCHES" | wc -l | tr -d " ")"
  FILES="$(echo "$ACCESS_KEY_MATCHES" | cut -d: -f1 | sort -u | paste -sd "," -)"
  add_result "AWS_ACCESS_KEY_ID_PATTERN count=${COUNT} files=${FILES}"
fi

# ---------------------------------------------------------------------------
# 4. Search AWS credential variable names only in candidate files.
# ---------------------------------------------------------------------------

echo "Scanning for AWS credential variable names..." >&2

SECRET_NAME_MATCHES="$(
  sudo grep -IEon \
    --binary-files=without-match \
    '(aws_secret_access_key|AWS_SECRET_ACCESS_KEY|aws_access_key_id|AWS_ACCESS_KEY_ID|AWS_SESSION_TOKEN|aws_session_token)' \
    $(cat "$CANDIDATE_FILE_LIST") 2>/dev/null \
  | head -n 50
)"

if [[ -n "$SECRET_NAME_MATCHES" ]]; then
  COUNT="$(echo "$SECRET_NAME_MATCHES" | wc -l | tr -d " ")"
  FILES="$(echo "$SECRET_NAME_MATCHES" | cut -d: -f1 | sort -u | paste -sd "," -)"
  add_result "AWS_CREDENTIAL_VARIABLE_NAMES count=${COUNT} files=${FILES}"
fi

rm -f "$CANDIDATE_FILE_LIST"

echo "Remote scan finished" >&2

if [[ -z "$RESULTS" ]]; then
  echo "none"
else
  echo "$RESULTS"
fi
REMOTE_SCRIPT
}

ami_creds_check_one_ami() {
  local ami="$1"
  local output_file="$2"

  local key_name="${AWS_DEFAULT_SSH_KEY_NAME:-keyname}"
  local ssh_key_path="${AWS_DEFAULT_SSH_KEY_PATH:-$HOME/.ssh/${key_name}.pem}"
  local ssh_users="${AWS_DEFAULT_SSH_USERS:-ec2-user ubuntu root}"

  local instance_id=""
  local selected_user="n/a"
  local found_vulnerabilities=""
  local ami_metadata
  local ami_name
  local ami_description
  local last_ami_usage
  local ip

  local old_int_trap
  old_int_trap="$(trap -p INT || true)"

  trap '
    echo "Interrupted. Cleaning up test instance..." >&2
    ami_creds_cleanup_instance "$instance_id"
    trap - INT
    return 130 2>/dev/null || exit 130
  ' INT

  echo "Processing AMI: $ami" >&2

  ami_metadata="$(ami_creds_get_ami_metadata "$ami")"
  ami_name="$(echo "$ami_metadata" | jq -r '.Name // "unknown"')"
  ami_description="$(echo "$ami_metadata" | jq -r '.Description // "unknown"')"
  last_ami_usage="$(ami_creds_get_last_ami_usage "$ami")"

  if ! instance_id="$(ami_creds_launch_instance "$ami")"; then
    found_vulnerabilities="ERROR: failed to launch instance"

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$(ami_creds_escape_tsv "$ami")" \
      "n/a" \
      "$(ami_creds_escape_tsv "$last_ami_usage")" \
      "$(ami_creds_escape_tsv "$ami_name")" \
      "$(ami_creds_escape_tsv "$ami_description")" \
      "$(ami_creds_escape_tsv "$found_vulnerabilities")" \
      | tee -a "$output_file"

    eval "$old_int_trap"
    return 1
  fi

  echo "Launched instance: $instance_id" >&2

  if ! aws ec2 wait instance-running --instance-ids "$instance_id"; then
    found_vulnerabilities="ERROR: instance did not enter running state"

    ami_creds_cleanup_instance "$instance_id"

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$(ami_creds_escape_tsv "$ami")" \
      "n/a" \
      "$(ami_creds_escape_tsv "$last_ami_usage")" \
      "$(ami_creds_escape_tsv "$ami_name")" \
      "$(ami_creds_escape_tsv "$ami_description")" \
      "$(ami_creds_escape_tsv "$found_vulnerabilities")" \
      | tee -a "$output_file"

    eval "$old_int_trap"
    return 1
  fi

  ip="$(ami_creds_get_instance_ip "$instance_id")"

  if [[ -z "$ip" || "$ip" == "None" ]]; then
    found_vulnerabilities="ERROR: could not get instance IP"

    ami_creds_cleanup_instance "$instance_id"

    printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$(ami_creds_escape_tsv "$ami")" \
      "n/a" \
      "$(ami_creds_escape_tsv "$last_ami_usage")" \
      "$(ami_creds_escape_tsv "$ami_name")" \
      "$(ami_creds_escape_tsv "$ami_description")" \
      "$(ami_creds_escape_tsv "$found_vulnerabilities")" \
      | tee -a "$output_file"

    eval "$old_int_trap"
    return 1
  fi

  echo "Instance IP: $ip" >&2

  if selected_user="$(ami_creds_wait_for_ssh "$ip")"; then
    echo "SSH user detected: $selected_user" >&2
    found_vulnerabilities="$(ami_creds_scan_credentials "$ip" "$selected_user" || echo "ERROR: scan failed")"
  else
    selected_user="n/a"
    found_vulnerabilities="ERROR: SSH failed for users: $ssh_users"
  fi

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$(ami_creds_escape_tsv "$ami")" \
    "$(ami_creds_escape_tsv "$selected_user")" \
    "$(ami_creds_escape_tsv "$last_ami_usage")" \
    "$(ami_creds_escape_tsv "$ami_name")" \
    "$(ami_creds_escape_tsv "$ami_description")" \
    "$(ami_creds_escape_tsv "$found_vulnerabilities")" \
    | tee -a "$output_file"

  ami_creds_cleanup_instance "$instance_id"
  instance_id=""

  eval "$old_int_trap"

  return 0
}

check_amis_for_hardcoded_aws_creds() {
  local ami_file="amis.txt"
  local single_ami=""
  local output_file="ami_credentials_report.tsv"
  local append_output="false"

  local key_name="${AWS_DEFAULT_SSH_KEY_NAME:-keyname}"
  local ssh_key_path="${AWS_DEFAULT_SSH_KEY_PATH:-$HOME/.ssh/${key_name}.pem}"

  local opt

  OPTIND=1

  while getopts ":f:a:o:Ah" opt; do
    case "$opt" in
      f)
        ami_file="$OPTARG"
        ;;
      a)
        single_ami="$OPTARG"
        ;;
      o)
        output_file="$OPTARG"
        ;;
      A)
        append_output="true"
        ;;
      h)
        cat <<'USAGE'
Usage:
  check_amis_for_hardcoded_aws_creds [options]

Options:
  -f FILE       File with AMI IDs, one AMI per line. Default: amis.txt
  -a AMI_ID     Check a single AMI instead of a file
  -o FILE       Output TSV file. Default: ami_credentials_report.tsv
  -A            Append to output file instead of overwriting it
  -h            Show this help

Environment overrides:
  SUBNET_ID
  SECURITY_GROUP_IDS
  AWS_DEFAULT_SSH_KEY_NAME
  AWS_DEFAULT_SSH_KEY_PATH
  AWS_DEFAULT_SSH_USERS
  INSTANCE_TYPE
  USE_PUBLIC_IP
  SSH_TIMEOUT_SECONDS
  SSH_RETRIES
  SSH_RETRY_SLEEP_SECONDS

Examples:
  check_amis_for_hardcoded_aws_creds
  check_amis_for_hardcoded_aws_creds -f amis.txt
  check_amis_for_hardcoded_aws_creds -a ami-0123456789abcdef0
  check_amis_for_hardcoded_aws_creds -f amis.txt -o report.tsv
USAGE
        return 0
        ;;
      :)
        echo "ERROR: option -$OPTARG requires an argument" >&2
        return 2
        ;;
      \?)
        echo "ERROR: unknown option -$OPTARG" >&2
        return 2
        ;;
    esac
  done

  if [[ -n "$single_ami" && "$ami_file" != "amis.txt" ]]; then
    echo "ERROR: use either -a AMI_ID or -f FILE, not both" >&2
    return 2
  fi

  if [[ -z "$single_ami" && ! -f "$ami_file" ]]; then
    echo "ERROR: AMI file not found: $ami_file" >&2
    return 1
  fi

  if [[ ! -f "$ssh_key_path" ]]; then
    echo "ERROR: SSH key not found: $ssh_key_path" >&2
    return 1
  fi

  chmod 600 "$ssh_key_path" >/dev/null 2>&1 || true

  command -v aws >/dev/null || {
    echo "ERROR: aws CLI is required" >&2
    return 1
  }

  command -v jq >/dev/null || {
    echo "ERROR: jq is required" >&2
    return 1
  }

  if [[ "$append_output" != "true" || ! -f "$output_file" ]]; then
    printf "AMI\tuser\tlast ami usage\tAMI name\tAMI description\tfound vulnerabilities\n" | tee "$output_file"
  fi

  if [[ -n "$single_ami" ]]; then
    ami_creds_check_one_ami "$single_ami" "$output_file"
    echo "Done. Report saved to: $output_file" >&2
    return $?
  fi

  local ami
  local exit_code=0

  while IFS= read -r ami <&3 || [[ -n "$ami" ]]; do
    ami="$(echo "$ami" | xargs)"

    [[ -z "$ami" ]] && continue
    [[ "$ami" =~ ^# ]] && continue

    if ! ami_creds_check_one_ami "$ami" "$output_file"; then
      exit_code=1
    fi
  done 3< "$ami_file"

  echo "Done. Report saved to: $output_file" >&2

  return "$exit_code"
}
