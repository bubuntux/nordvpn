#!/usr/bin/with-contenv bash

echo "`date` Check VPN Internet connection"

function httpreq
{
    case "$(curl -s --max-time 2 -I $1 | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
        [23]) return 0;;
        5) return 1;;
        *) return 1;;
    esac
}

counter=1
while [ $counter -le $CHECK_CONNECTION_ATTEMPTS ]; do
    IFS=';'
    read -ra urls <<< "$CHECK_CONNECTION_URL"
    for url in "${urls[@]}"; do
        httpreq $urls
        if [ $? -eq 0 ]; then
            echo "Connection via VPN is up"
            exit 0
        else
            echo "Iteration $counter($CHECK_CONNECTION_ATTEMPTS), url=$url, Connection via VPN is down"
        fi
    done

    echo "Sleep between iteration for $CHECK_CONNECTION_ATTEMPT_INTERVAL"
    sleep $CHECK_CONNECTION_ATTEMPT_INTERVAL
    ((counter++))
done

echo "Connection via VPN is down, recreate VPN"
reconnect.sh

exit 1
