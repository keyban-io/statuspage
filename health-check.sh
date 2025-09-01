#!/bin/bash
set -euo pipefail

# Function to display help
show_help() {
  cat << EOF
Usage: $0 [OPTIONS]

Health check script for monitoring service endpoints.

OPTIONS:
  --help      Show this help message
  --commit    Enable saving results to Git
              (can also be enabled with COMMIT=true)

DESCRIPTION:
  This script checks the health of services listed in urls.cfg.
  By default, results are displayed but not saved.
  
  For 'api' services, checks the /health/ready endpoint
  For other services, checks the /health endpoint
  
  Logs are saved in the logs/ directory with automatic rotation.

EXAMPLES:
  $0                    # Run health checks without saving
  $0 --commit          # Run and save to Git
  COMMIT=true $0       # Alternative way to enable saving

EOF
}

# By default do not commit health-check results. To enable committing pass --commit
# on the command-line or set the COMMIT environment variable to "true".
# We still disable commits when the git origin is the upstream statsig-io/statuspage repo.
commit=false

# Check for help argument first
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

# Enable commit if user passed --commit or COMMIT=true
if [[ "${1:-}" == "--commit" ]] || [[ "${COMMIT:-}" == "true" ]]; then
  commit=true
fi
origin=$(git remote get-url origin 2>/dev/null || true)
if [[ $origin == *statsig-io/statuspage* ]]
then
  commit=false
fi

KEYSARRAY=()
URLSARRAY=()

urlsConfig="./urls.cfg"
echo "Reading $urlsConfig"
while read -r line || [ -n "$line" ]
do
  # Trim leading/trailing whitespace
  trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  # Skip empty lines and comments
  [ -z "$trimmed" ] && continue
  case "$trimmed" in \#*) continue ;; esac
  echo "  $trimmed"
  # Split on the first '=' into key and value (keeps values that contain '=')
  key="${trimmed%%=*}"
  value="${trimmed#*=}"
  KEYSARRAY+=("$key")
  URLSARRAY+=("$value")
done < "$urlsConfig"

echo "***********************"
echo "Starting health checks with ${#KEYSARRAY[@]} configs:"

# Function to check URL health
check_url_health() {
  local base_url="$1"
  local endpoints=("${@:2}")
  local result="failed"
  
  for endpoint in "${endpoints[@]}"; do
    local found="no"
    for suffix in "" "/"; do
      local full_url="$base_url$endpoint$suffix"
      for attempt in 1 2 3 4; do
        local response
        response=$(curl --write-out '%{http_code}' --silent --output /dev/null --max-time 10 "$full_url")
        if [[ "$response" =~ ^(200|202|204|301|302|307)$ ]]; then
          result="success"
          found="yes"
          break
        fi
        # Only sleep between attempts, not after the last one
        [[ "$attempt" -lt 4 ]] && sleep 5
      done
      [[ "$found" == "yes" ]] && break
    done
    [[ "$result" == "success" ]] && break
  done
  
  echo "$result"
}

mkdir -p logs

# Ensure each monitored service has a log file so the frontend can show "No Data" instead of 404.
for key in "${KEYSARRAY[@]}"
do
  file="logs/${key}_report.log"
  if [ ! -f "$file" ]; then
    echo "$(date +'%Y-%m-%d %H:%M'), nodata" > "$file"
  fi
done

for (( index=0; index < ${#KEYSARRAY[@]}; index++))
do
  key="${KEYSARRAY[index]}"
  url="${URLSARRAY[index]}"
  echo "  $key=$url"

  # Normalize base URL (remove trailing slash)
  base_url="${url%/}"

  # Determine endpoints based on service type
  if [[ "$key" == "api" ]]; then
    result=$(check_url_health "$base_url" "/health/ready")
    
    # If api failed, emit diagnostics
    if [[ "$result" != "success" ]]; then
      echo "    [debug] api check failed; diagnostic HTTP status codes:"
      for suffix in "" "/"; do
        full_url="$base_url/health/ready$suffix"
        code=$(curl --write-out '%{http_code}' --silent --output /dev/null --max-time 10 "$full_url")
        echo "    [debug] $full_url -> $code"
      done
    fi
  else
    result=$(check_url_health "$base_url" "/health")
  fi

  dateTime=$(date +'%Y-%m-%d %H:%M')
  if [[ $commit == true ]]
  then
    echo $dateTime, $result >> "logs/${key}_report.log"
    # By default we keep 2000 last log entries.  Feel free to modify this to meet your needs.
    echo "$(tail -2000 logs/${key}_report.log)" > "logs/${key}_report.log"
  else
    echo "    $dateTime, $result"
  fi
done

if [[ $commit == true ]]; then
  # Let's make Vijaye the most productive person on GitHub.
  git config --global user.name 'Vijaye Raji'
  git config --global user.email 'vijaye@statsig.com'
  git add -A --force logs/
  
  # Only commit if there are changes
  if ! git diff --cached --quiet; then
    git commit -m '[Automated] Update Health Check Logs'
    git push
  else
    echo "No changes to commit"
  fi
fi
