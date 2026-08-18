deregister_amis_from_file() {
    local file="$1"
    local apply="${2:-false}"
    local region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"

    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "Usage: deregister_amis_from_file <file> [true|false]"
        echo "Example dry run: deregister_amis_from_file amis.txt"
        echo "Example apply:   deregister_amis_from_file amis.txt true"
        return 1
    fi

    if [[ -z "$region" ]]; then
        echo "AWS region is not set."
        echo "Set AWS_REGION, for example:"
        echo "  export AWS_REGION=eu-west-1"
        return 1
    fi

    while IFS= read -r ami_id; do
        # Remove comments and surrounding whitespace
        ami_id="${ami_id%%#*}"
        ami_id="$(echo "$ami_id" | xargs)"

        [[ -z "$ami_id" ]] && continue

        if [[ ! "$ami_id" =~ ^ami-[0-9a-fA-F]+$ ]]; then
            echo "SKIP: invalid AMI ID: $ami_id"
            continue
        fi

        if ! aws ec2 describe-images \
            --region "$region" \
            --image-ids "$ami_id" \
            --query 'Images[0].ImageId' \
            --output text >/dev/null 2>&1; then
            echo "SKIP: AMI not found or inaccessible: $ami_id"
            continue
        fi

        if [[ "$apply" == "true" ]]; then
            echo "Deregistering $ami_id..."
            if aws ec2 deregister-image \
                --region "$region" \
                --image-id "$ami_id"; then
                echo "DONE: $ami_id"
            else
                echo "FAILED: $ami_id" >&2
            fi
        else
            echo "DRY RUN: would deregister $ami_id"
        fi
    done < "$file"
}

ami_deregister() {
    deregister_amis_from_file "$@"
}
