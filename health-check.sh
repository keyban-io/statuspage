# In the original repository we'll just print the result of status checks,
# without committing. This avoids generating several commits that would make
# later upstream merges messy for anyone who forked us.
commit=true
origin=$(git remote get-url origin)
if [[ $origin == *statsig-io/statuspage* ]]
then
  commit=false
fi

KEYSARRAY=()
URLSARRAY=()

urlsConfig="./urls.cfg"
echo "Reading $urlsConfig"
while read -r line
do
  echo "  $line"
  IFS='=' read -ra TOKENS <<< "$line"
  KEYSARRAY+=(${TOKENS[0]})
  URLSARRAY+=(${TOKENS[1]})
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

  # For the api service probe both /health/live and /health/ready (require BOTH to be healthy); otherwise probe the /health endpoint on other services
  if [ "$key" = "api" ]; then
    endpoints=("/health/live" "/health/ready")

    # Require all endpoints to be healthy (AND logic)
    result="success"
    for endpoint in "${endpoints[@]}"
    do
      full_url="$base_url$endpoint"
      endpoint_ok="failed"
      for i in 1 2 3 4;
      do
        response=$(curl --write-out '%{http_code}' --silent --output /dev/null "$full_url")
        if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
          endpoint_ok="success"
          break
        fi
        sleep 5
      done
      # If any endpoint failed after retries, mark overall result failed and stop
      if [ "$endpoint_ok" != "success" ]; then
        result="failed"
        break
      fi
    done
  else
    endpoints=("/health")

    result="failed"
    for endpoint in "${endpoints[@]}"
    do
      full_url="$base_url$endpoint"
      for i in 1 2 3 4;
      do
        response=$(curl --write-out '%{http_code}' --silent --output /dev/null "$full_url")
        if [ "$response" -eq 200 ] || [ "$response" -eq 202 ] || [ "$response" -eq 301 ] || [ "$response" -eq 302 ] || [ "$response" -eq 307 ]; then
          result="success"
        else
          result="failed"
        fi
        if [ "$result" = "success" ]; then
          break
        fi
        sleep 5
      done
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
