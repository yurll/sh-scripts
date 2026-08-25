#!/usr/bin/env bash

DATE_CMD=$(command -v gdate || command -v date)

function aws_check() {
    # 1. Require AWS_PROFILE to be explicitly set
    if [ -z "$AWS_PROFILE" ]; then
        echo "[Error]: AWS_PROFILE is not set. Please export a profile first (e.g., export AWS_PROFILE=your-profile)."
        return 1
    fi

    # 2. Get the SSO Start URL for the exact profile
    local start_url
    start_url=$(aws configure get sso_start_url --profile "$AWS_PROFILE" 2>/dev/null)

    if [ -z "$start_url" ]; then
        echo "[Error]: Profile [$AWS_PROFILE] does not have an SSO configuration."
        return 1
    fi

    # 3. Find the expiration date of the active token
    local expire_raw
    expire_raw=$(grep -l "$start_url" ~/.aws/sso/cache/*.json 2>/dev/null | xargs jq -r 'select(.accessToken != null) | .expiresAt' 2>/dev/null | head -n 1)

    if [ -z "$expire_raw" ] || [ "$expire_raw" = "null" ]; then
        echo "[Error]: Profile [$AWS_PROFILE]: No active login session found. Run: aws sso login"
        return 1
    fi

    # 4. Compare timestamps to see if it is expired
    local expire_epoch
    expire_epoch=$($DATE_CMD -d "$expire_raw" +%s)
    local now_epoch
    now_epoch=$($DATE_CMD +%s)

    if [ "$now_epoch" -ge "$expire_epoch" ]; then
        echo "[Error]: Profile [$AWS_PROFILE]: Token expired at $($DATE_CMD -d "$expire_raw"). Run: aws sso login"
        return 1
    else
        echo "[OK]: Profile [$AWS_PROFILE]: Valid until $($DATE_CMD -d "$expire_raw")"
        return 0
    fi
}
