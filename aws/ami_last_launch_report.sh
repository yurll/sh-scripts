ami_last_launch_report() {
    local region=""
    local parallel_jobs=10
    local output_dir="ami-report"
    local page_size=100
    local force=false
    local -a exclude_name_prefixes=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--region)
                region="${2:?Missing value for $1}"
                shift 2
                ;;
            -p|--parallel)
                parallel_jobs="${2:?Missing value for $1}"
                shift 2
                ;;
            -o|--output-dir)
                output_dir="${2:?Missing value for $1}"
                shift 2
                ;;
            --page-size)
                page_size="${2:?Missing value for $1}"
                shift 2
                ;;
            --exclude-name-prefix)
                exclude_name_prefixes+=("${2:?Missing value for $1}")
                shift 2
                ;;
            --exclude-name)
                exclude_names+=("${2:?Missing value for $1}")
                shift 2
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage:
  ami_last_launch_report [options]

Options:
  -r, --region REGION
      AWS region.

  -p, --parallel NUMBER
      Concurrent AWS calls. Default: 10.

  -o, --output-dir DIR
      Output directory. Default: ami-report.

      --page-size NUMBER
      AWS CLI page size. Default: 100.

      --exclude-name-prefix PREFIX
      Exclude AMIs whose names start with PREFIX.
      Can be specified multiple times.

      --exclude-name NAME
      Exclude AMI with the specified name.
      Can be specified multiple times.

  -f, --force
      Recheck AMIs that already have cached results.

  -h, --help
      Show this help.

Examples:
  ami_last_launch_report

  ami_last_launch_report \
      --exclude-name-prefix "AlgoSec-AMI-app"

  ami_last_launch_report \
      --exclude-name-prefix "AlgoSec-AMI-app" \
      --exclude-name-prefix "temporary-"

  ami_last_launch_report \
      --region eu-west-1 \
      --parallel 15 \
      --output-dir ami-report-eu-west-1
EOF
                return 0
                ;;
            *)
                printf 'ERROR: Unknown argument: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    region="$(
        printf '%s' \
            "${region:-${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}}"
    )"

    if [[ -z "$region" ]]; then
        echo "ERROR: No AWS region configured." >&2
        return 1
    fi

    if ! [[ "$parallel_jobs" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: --parallel must be a positive integer." >&2
        return 2
    fi

    if ! [[ "$page_size" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: --page-size must be a positive integer." >&2
        return 2
    fi

    if ! command -v aws >/dev/null 2>&1; then
        echo "ERROR: aws CLI is not installed or not in PATH." >&2
        return 127
    fi

    local images_json="$output_dir/all-amis.json"
    local ami_data_file="$output_dir/all-amis.tsv"
    local ami_ids_file="$output_dir/filtered-ami-ids.txt"
    local excluded_file="$output_dir/excluded-amis.tsv"
    local no_launch_file="$output_dir/no-last-launch.txt"
    local error_file="$output_dir/errors.txt"
    local report_file="$output_dir/ami-last-launch.tsv"
    local results_dir="$output_dir/results"

    mkdir -p "$results_dir" || return 1

    echo "Region:        $region"
    echo "Parallel jobs: $parallel_jobs"
    echo "Output:        $output_dir"

    if [[ ${#exclude_name_prefixes[@]} -gt 0 ]]; then
        echo "Excluded name prefixes:"

        local prefix
        for prefix in "${exclude_name_prefixes[@]}"; do
            printf '  %s\n' "$prefix"
        done
    fi

    if [[ ${#exclude_names[@]} -gt 0 ]]; then
        echo "Excluded names:"

        local name
        for name in "${exclude_names[@]}"; do
            printf '  %s\n' "$name"
        done
    fi

    echo
    echo "Retrieving all owned AMIs..."

    if ! AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}" \
         AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}" \
         aws ec2 describe-images \
             --owners self \
             --region "$region" \
             --page-size "$page_size" \
             --output json \
             --no-cli-pager \
             > "$images_json"; then
        echo "ERROR: Failed to retrieve AMIs." >&2
        return 1
    fi

    if ! aws ec2 describe-images \
            --owners self \
            --region "$region" \
            --page-size "$page_size" \
            --query 'Images[].[ImageId, Tags[?Key==`Name`].Value | [0], CreationDate]' \
            --output text \
            --no-cli-pager \
            > "$ami_data_file"; then
        echo "ERROR: Failed to retrieve AMI metadata." >&2
        return 1
    fi

    : > "$ami_ids_file"
    : > "$excluded_file"

    while IFS=$'\t' read -r ami_id name_tag creation_date; do
        [[ -n "$ami_id" ]] || continue

        # AWS CLI may print None when the Name tag is missing.
        [[ "$name_tag" == "None" ]] && name_tag=""

        local excluded=false
        local prefix

        for prefix in "${exclude_name_prefixes[@]}"; do
            if [[ "$name_tag" == "$prefix"* ]]; then
                excluded=true
                break
            fi
        done

        local name
        for name in "${exclude_names[@]}"; do
            if [[ "$name_tag" == *"$name"* ]]; then
                excluded=true
                break
            fi
        done

        if [[ "$excluded" == true ]]; then
            printf '%s\t%s\t%s\n' \
                "$ami_id" "$name_tag" "$creation_date" \
                >> "$excluded_file"
        else
            printf '%s\n' "$ami_id" >> "$ami_ids_file"
        fi
    done < "$ami_data_file"

    local total_count
    local filtered_count
    local excluded_count

    total_count="$(wc -l < "$ami_data_file" | tr -d ' ')"
    filtered_count="$(wc -l < "$ami_ids_file" | tr -d ' ')"
    excluded_count="$(wc -l < "$excluded_file" | tr -d ' ')"

    echo "Total AMIs:    $total_count"
    echo "Excluded AMIs: $excluded_count"
    echo "AMIs to check: $filtered_count"

    if [[ "$filtered_count" -eq 0 ]]; then
        printf 'AMI_ID\tLAST_LAUNCHED\n' > "$report_file"
        : > "$no_launch_file"
        : > "$error_file"

        echo
        echo "No AMIs remain after filtering."
        return 0
    fi

    echo "Checking last launch dates..."

    (
        export AMI_REPORT_REGION="$region"
        export AMI_REPORT_RESULTS_DIR="$results_dir"
        export AMI_REPORT_FORCE="$force"
        export AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}"
        export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}"

        xargs -r -n 1 -P "$parallel_jobs" bash -c '
            ami_id="$1"
            result_file="$AMI_REPORT_RESULTS_DIR/$ami_id.tsv"
            error_file="$AMI_REPORT_RESULTS_DIR/$ami_id.error"

            if [[ "$AMI_REPORT_FORCE" != "true" && -s "$result_file" ]]; then
                exit 0
            fi

            if last_launch="$(
                aws ec2 describe-image-attribute \
                    --region "$AMI_REPORT_REGION" \
                    --image-id "$ami_id" \
                    --attribute lastLaunchedTime \
                    --query "LastLaunchedTime.Value" \
                    --output text \
                    --no-cli-pager \
                    2>"$error_file"
            )"; then
                case "$last_launch" in
                    ""|"None"|"null")
                        status="NO_LAST_LAUNCH"
                        ;;
                    *)
                        status="$last_launch"
                        ;;
                esac

                printf "%s\t%s\n" "$ami_id" "$status" > "$result_file"
                rm -f "$error_file"
            else
                printf "%s\tERROR\n" "$ami_id" > "$result_file"
            fi
        ' _ < "$ami_ids_file"
    )

    {
        printf 'AMI_ID\tLAST_LAUNCHED\n'

        while IFS= read -r ami_id; do
            local result_file="$results_dir/$ami_id.tsv"

            if [[ -s "$result_file" ]]; then
                cat "$result_file"
            else
                printf '%s\tERROR\n' "$ami_id"
                printf 'No result was produced\n' > "$results_dir/$ami_id.error"
            fi
        done < "$ami_ids_file"
    } > "$report_file"

    awk -F '\t' '
        NR > 1 && $2 == "NO_LAST_LAUNCH" {
            print $1
        }
    ' "$report_file" > "$no_launch_file"

    : > "$error_file"

    while IFS= read -r ami_id; do
        local ami_error_file="$results_dir/$ami_id.error"

        if [[ -s "$ami_error_file" ]]; then
            {
                printf '%s: ' "$ami_id"
                tr '\n' ' ' < "$ami_error_file"
                printf '\n'
            } >> "$error_file"
        fi
    done < "$ami_ids_file"

    local no_launch_count
    local error_count

    no_launch_count="$(wc -l < "$no_launch_file" | tr -d ' ')"
    error_count="$(wc -l < "$error_file" | tr -d ' ')"

    echo
    echo "=================================================="
    echo "AMI IDs with no last launch date"
    echo "=================================================="

    if [[ "$no_launch_count" -eq 0 ]]; then
        echo "None"
    else
        cat "$no_launch_file"
    fi

    echo
    echo "Summary:"
    echo "  Total AMIs:          $total_count"
    echo "  Excluded AMIs:       $excluded_count"
    echo "  Checked AMIs:        $filtered_count"
    echo "  No last launch date: $no_launch_count"
    echo "  API errors:          $error_count"
    echo
    echo "Files:"
    echo "  Full AMI descriptions: $images_json"
    echo "  All AMI metadata:       $ami_data_file"
    echo "  Excluded AMIs:          $excluded_file"
    echo "  Checked AMI IDs:        $ami_ids_file"
    echo "  Last-launch report:     $report_file"
    echo "  No-launch AMI IDs:      $no_launch_file"
    echo "  Errors:                 $error_file"

    [[ "$error_count" -eq 0 ]]
}
