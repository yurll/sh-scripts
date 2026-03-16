vpn_bypass() {
  local host="$1"
  local state_file="/tmp/vpn_bypass_routes.txt"
  local gateway
  local ip
  local ips

  if [[ -z "$host" ]]; then
    echo "Usage: vpn_bypass [hostname|--reset]"
    return 1
  fi

  if [[ "$host" == "--reset" ]]; then
      if [[ -f "$state_file" ]]; then
      while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        _log "Removing old route $ip"
        sudo route -n delete "$ip" >/dev/null 2>&1 || true
      done < "$state_file"
    fi

    : > "$state_file"
  fi

  _log() {
    echo "[$(date '+%H:%M:%S')] $*"
  }

  _get_gateway() {
    netstat -rn -f inet | awk '
      $1 == "default" && $NF ~ /^en[0-9]+$/ { print $2; exit }
    '
  }

  _resolve_ips() {
    dig +short "$host" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u
  }

  gateway="$(_get_gateway)"
  if [[ -z "$gateway" ]]; then
    echo "Could not detect local gateway"
    return 1
  fi

  ips="$(_resolve_ips)"
  if [[ -z "$ips" ]]; then
    echo "No IPv4 addresses found for $host"
    return 1
  fi

  _log "Gateway: $gateway"
  _log "Resolved IPs:"
  printf '%s\n' "$ips"

  _log "Refreshing sudo credentials..."
  sudo -v || return 1

  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue

    _log "Adding route $ip via $gateway"
    sudo route -n add "$ip" "$gateway"

    echo "$ip" >> "$state_file"
  done <<< "$ips"

  _log "Route check:"
  while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    echo
    route -n get "$ip" | grep -E 'route to:|gateway:|interface:'
  done <<< "$ips"
}
