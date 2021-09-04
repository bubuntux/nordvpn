#!/usr/bin/with-contenv bash

echo "Select NordVPN server and create config file"

base_dir="/vpn"
ovpn_dir="/ovpn"
auth_file="$base_dir/auth"
config_file="$base_dir/config.ovpn"

### iptablesServer: adds or removes a iptable rule for the remote (server) in the config file
# Arguments:
#    mode) can be 'A' for append a rule or 'D' for delete (default)
# Return: none
iptablesServer() {
    mode=${1-"D"}
    
    if [[ -f "$config_file" ]]; then
        config_remote=`cat $config_file | awk '$1 == "remote" \
            {print $2,$3,$4}'`
        config_ip=`echo $config_remote | awk '{print $1}'`
        config_port=`echo $config_remote | awk '{print $2}'`
        config_proto=`echo $config_remote | awk '{print $3}'`

        if [[ -z "$config_proto" ]]; then
            config_proto=`cat $config_file | awk '$1 == "proto" {print $2}'`
        fi

        #get only the first three letters as the proto can be also be tcp6/udp6
        config_proto="${config_proto:0:3}"

        if [ $mode == "A" ]; then
            echo "Adding iptable rule for: $config_ip $config_port \
                $config_proto"
        else
            echo "Deleting iptable rule for: $config_ip $config_port \
                $config_proto"
        fi
        
        iptables -$mode OUTPUT -p $config_proto -m $config_proto \
            -d $config_ip --dport $config_port -j ACCEPT
        ip6tables -$mode OUTPUT -p $config_proto -m $config_proto \
            -d $config_ip --dport $config_port -j ACCEPT 2> /dev/null
    fi
}

#remove iptables rules for the current config
iptablesServer D

# Use api.nordvpn.com
servers=`curl -s $URL_NORDVPN_API`
servers=`echo $servers | jq -c '.[] | select(.features.openvpn_udp == true)' && \
         echo $servers | jq -c '.[] | select(.features.openvpn_tcp == true)'`
servers=`echo $servers | jq -s -a -c 'unique'`
pool_length=`echo $servers | jq 'length'`
echo "OpenVPN servers in pool: $pool_length"
servers=`echo $servers | jq -c '.[]'`

IFS=';'

if [[ !($pool_length -eq 0) ]]; then
    if [[ -z "${COUNTRY}" ]]; then
        echo "Country not set, skip filtering"
    else
        echo "Filter pool by country: $COUNTRY"
        read -ra countries <<< "$COUNTRY"
        for country in "${countries[@]}"; do
            filtered="$filtered"`echo $servers | jq -c 'select(.country == "'$country'")'`
        done
        filtered=`echo $filtered | jq -s -a -c 'unique'`
        pool_length=`echo $filtered | jq 'length'`
        echo "Servers in filtered pool: $pool_length"
        servers=`echo $filtered | jq -c '.[]'`
    fi
fi

if [[ !($pool_length -eq 0) ]]; then
    if [[ -z "${CATEGORY}" ]]; then
        echo "Category not set, skip filtering"
    else
        echo "Filter pool by category: $CATEGORY"
        read -ra categories <<< "$CATEGORY"
        filtered="$servers"
        for category in "${categories[@]}"; do
            filtered=`echo $filtered | jq -c 'select(.categories[].name == "'$category'")'`
        done
        filtered=`echo $filtered | jq -s -a -c 'unique'`
        pool_length=`echo $filtered | jq 'length'`
        echo "Servers in filtered pool: $pool_length"
        servers=`echo $filtered | jq -c '.[]'`
    fi
fi

if [[ !($pool_length -eq 0) ]]; then
    echo "Filter pool by protocol: $PROTOCOL"
    filtered=`echo $servers | jq -c 'select(.features.'$PROTOCOL' == true)' | jq -s -a -c 'unique'`
    pool_length=`echo $filtered | jq 'length'`
    echo "Servers in filtered pool: $pool_length"
    servers=`echo $filtered | jq -c '.[]'`
fi

if [[ !($pool_length -eq 0) ]]; then
    echo "Filter pool by load, less than $MAX_LOAD%"
    servers=`echo $servers | jq -c 'select(.load <= '$MAX_LOAD')'`
    pool_length=`echo $servers | jq -s -a -c 'unique' | jq 'length'`
    echo "Servers in filtered pool: $pool_length"
    servers=`echo $servers | jq -s -c 'sort_by(.load)[]'`
fi

if [[ !($RANDOM_TOP -eq 0) ]]; then
    echo "Random order of top $RANDOM_TOP servers in filtered pool"
    if [[ $RANDOM_TOP -lt pool_length ]]; then
        filtered=`echo $servers | head -n $RANDOM_TOP | shuf`
        servers="$filtered"`echo $servers | tail -n +$((RANDOM_TOP + 1))`
    else
        servers=`echo $servers | shuf`
    fi
fi

if [[ !($pool_length -eq 0) ]]; then
    echo "--- Top 20 servers in filtered pool ---"
    echo `echo $servers | jq -r '"\(.domain) \(.load)%"' | head -n 20`
    echo "---------------------------------------"
fi

servers=`echo $servers | jq -r '.domain'`
IFS=$'\n'
read -ra filtered <<< "$servers"

for server in "${filtered[@]}"; do
    if [[ "${PROTOCOL}" == "openvpn_udp" ]]; then
        config="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config" ]; then
            break
        else
            echo "UDP config for server $server not found"
        fi
    fi
    if [[ "${PROTOCOL}" == "openvpn_tcp" ]]; then
        config="${ovpn_dir}/${server}.tcp.ovpn"
        if [ -r "$config" ]; then
            break
        else
            echo "TCP config for server $server not found"
        fi
    fi
done

if [ -z $config ]; then
    echo "Filtered pool is empty or configs not found. Select server from recommended list"
    recommendations=`curl -s $URL_RECOMMENDED_SERVERS | jq -r '.[] | .hostname' | shuf`
    for server in ${recommendations}; do # Prefer UDP
        config="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config" ]; then
            break
        else
            echo "UDP config for server $server not found"
        fi
    done
    if [ -z $config ]; then # Use TCP if UDP not available
       for server in ${recommendations}; do
            config="${ovpn_dir}/${server}.tcp.ovpn"
            if [ -r "$config" ]; then
                break
            else
                echo "TCP config for server $server not found"
            fi
        done
    fi
fi

if [ -z $config ]; then
    echo "List of recommended servers is empty or configs not found. Select random server from available configs."
    config="${ovpn_dir}/`ls ${ovpn_dir} | shuf -n 1`"
fi

# Create auth_file
echo "$USER" > $auth_file 
echo "$PASS" >> $auth_file
chmod 0600 $auth_file

cp "$config" "$config_file"
echo "script-security 2" >> "$config_file"
echo "up /etc/openvpn/up.sh" >> "$config_file"
echo "down /etc/openvpn/down.sh" >> "$config_file"

iptablesServer A

exit 0