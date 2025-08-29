# By default do not commit health-check results. To enable committing pass --commit
# on the command-line or set the COMMIT environment variable to "true".
# We still disable commits when the git origin is the upstream statsig-io/statuspage repo.
commit=false
# Enable commit if user passed --commit or COMMIT=true
if [[ "$1" == "--commit" ]] || [[ "${COMMIT}" == "true" ]]
then
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

  # For the api service probe both /health/live and /health/ready (require BOTH to be healthy);
  # for other services probe the /health endpoint.
  if [ "$key" = "api" ]; then
    endpoints=("/health/live" "/health/ready")

    # Require all endpoints to be healthy (AND logic). For robustness try each endpoint
    # both with and without a trailing slash and accept 200/202/204/3xx as success.
    result="success"
    for endpoint in "${endpoints[@]}"
    do
      endpoint_ok="failed"
      for suffix in "" "/"
      do
        full_url="$base_url$endpoint$suffix"
        found="no"
        for i in 1 2 3 4;
        do
          response=$(curl --write-out '%{http_code}' --silent --output /dev/null --max-time 10 "$full_url")
          if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 204 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
            endpoint_ok="success"
            found="yes"
            break
          fi
          sleep 5
        done
        [ "$found" = "yes" ] && break
      done
      # If any endpoint failed after retries, mark overall result failed and stop
      if [ "$endpoint_ok" != "success" ]; then
        result="failed"
        break
      fi
    done

    # If api failed, emit short diagnostics to help identify why (prints HTTP codes)
    if [ "$result" != "success" ]; then
      echo "    [debug] api check failed; diagnostic HTTP status codes:"
      for endpoint in "${endpoints[@]}"
      do
        for suffix in "" "/"
        do
          full_url="$base_url$endpoint$suffix"
          code=$(curl --write-out '%{http_code}' --silent --output /dev/null --max-time 10 "$full_url")
          echo "    [debug] $full_url -> $code"
        done
      done
    fi
  else
    endpoints=("/health")

    result="failed"
    for endpoint in "${endpoints[@]}"
    do
      found="no"
      for suffix in "" "/"
      do
        full_url="$base_url$endpoint$suffix"
        for i in 1 2 3 4;
        do
          response=$(curl --write-out '%{http_code}' --silent --output /dev/null --max-time 10 "$full_url")
          if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 204 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
            result="success"
            found="yes"
            break
          fi
          sleep 5
        done
        [ "$found" = "yes" ] && break
      done
      [ "$result" = "success" ] && break
    done
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

if [[ $commit == true ]]
then
  # Let's make Vijaye the most productive person on GitHub.
  git config --global user.name 'Vijaye Raji'
  git config --global user.email 'vijaye@statsig.com'
  git add -A --force logs/
  git commit -am '[Automated] Update Health Check Logs'
  git push
fi
