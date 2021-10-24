#!/usr/bin/with-contenv bash

nvcountries=$(curl -s https://api.nordvpn.com/v1/servers/countries | jq -c '.[]')
nvgroups=$(curl -s https://api.nordvpn.com/v1/servers/groups | jq -c '.[]')
nvtechnologies=$(curl -s https://api.nordvpn.com/v1/technologies | jq -c '.[]')

numericregex="^[0-9]+$"

ovpntemplatefile="/etc/nordvpn/template.ovpn"
authfile="/tmp/auth"
ovpnfile="/tmp/nordvpn.ovpn"

### iptablesserver: adds or removes a iptable rule for the remote (server) in the config file
# Arguments:
#    mode) can be 'A' for append a rule or 'D' for delete (default)
# Return: none
iptablesserver()
{
    mode=${1-"D"}
    
    if [[ -f "$ovpnfile" ]]; then
        config_remote=$(cat $ovpnfile | awk '$1 == "remote" {print $2,$3,$4}')
        config_ip=$(echo $config_remote | awk '{print $1}')
        config_port=$(echo $config_remote | awk '{print $2}')
        config_proto=$(echo $config_remote | awk '{print $3}')

        if [[ -z "$config_proto" ]]; then
            config_proto=$(cat $ovpnfile | awk '$1 == "proto" {print $2}')
        fi

        #get only the first three letters as the proto can be also be tcp6/udp6
        config_proto="${config_proto:0:3}"

        if [ $mode == "A" ]; then
            echo "Adding iptable rule for: $config_ip $config_port $config_proto"
        else
            echo "Deleting iptable rule for: $config_ip $config_port $config_proto"
        fi
        
        iptables -$mode OUTPUT -p $config_proto -m $config_proto -d $config_ip --dport $config_port -j ACCEPT
        ip6tables -$mode OUTPUT -p $config_proto -m $config_proto -d $config_ip --dport $config_port -j ACCEPT 2> /dev/null
    fi
}

getcountryid()
{
    input=$1

    id=$(echo "$nvcountries" | jq -r --arg NAME "$input" 'select(.name == $NAME) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    id=$(echo "$nvcountries" | jq -r --arg CODE "$input" 'select(.code == $CODE) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    printf "$input"
    return 0
}

getcountryname()
{
    input=$1

    if [[ "$input" =~ $numericregex ]]; then
        name=$(echo "$nvcountries" | jq -r --argjson ID $input 'select(.id == $ID) | .name')
        if [ ! -z "$name" ]; then
            printf "$name"
            return 0
        fi
    fi

    name=$(echo "$nvcountries" | jq -r --arg CODE "$input" 'select(.code == $CODE) | .name')
    if [ ! -z "$name" ]; then
        printf "$name"
        return 0
    fi

    printf "$input"
    return 0
}

getgroupid()
{
    input=$1

    id=$(echo "$nvgroups" | jq -r --arg TITLE "$input" 'select(.title == $TITLE) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    id=$(echo "$nvgroups" | jq -r --arg IDENTIFIER "$input" 'select(.identifier == $IDENTIFIER) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    printf "$input"
    return 0
}

getgrouptitle()
{
    input=$1

    if [[ "$input" =~ $numericregex ]]; then
        name=$(echo "$nvgroups" | jq -r --argjson ID $input 'select(.id == $ID) | .title')
        if [ ! -z "$name" ]; then
            printf "$name"
            return 0
        fi
    fi

    name=$(echo "$nvgroups" | jq -r --arg IDENTIFIER "$input" 'select(.identifier == $IDENTIFIER) | .title')
    if [ ! -z "$name" ]; then
        printf "$name"
        return 0
    fi

    printf "$input"
    return 0
}

gettechnologyid()
{
    input=$1

    id=$(echo "$nvtechnologies" | jq -r --arg NAME "$input" 'select(.name == $NAME) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    id=$(echo "$nvtechnologies" | jq -r --arg IDENTIFIER "$input" 'select(.identifier == $IDENTIFIER) | .id')
    if [ ! -z "$id" ]; then
        printf "$id"
        return 0
    fi

    printf "$input"
    return 0
}

gettechnologyname()
{
    input=$1

    if [[ "$input" =~ $numericregex ]]; then
        name=$(echo "$nvtechnologies" | jq -r --argjson ID $input 'select(.id == $ID) | .name')
        if [ ! -z "$name" ]; then
            printf "$name"
            return 0
        fi
    fi

    name=$(echo "$nvtechnologies" | jq -r --arg IDENTIFIER "$input" 'select(.identifier == $IDENTIFIER) | .name')
    if [ ! -z "$name" ]; then
        printf "$name"
        return 0
    fi

    printf "$input"
    return 0
}

getopenvpnprotocol()
{
    input=$1

    ident=$(echo "$nvtechnologies" | jq -r --arg NAME "$input" 'select(.name == $NAME) | .identifier')
    if [ -z "$ident" ]; then
        if [[ "$input" =~ $numericregex ]]; then
            ident=$(echo "$nvtechnologies" | jq -r --argjson ID $input 'select(.id == $ID) | .identifier')
        fi
    fi
    if [ -z "$ident" ]; then
        ident=$input
    fi

    if [[ $ident != *"openvpn"* ]]; then
        printf ""
    elif [[ $ident == *"udp"* ]]; then
        printf "udp"
    elif [[ $ident == *"tcp"* ]]; then
        printf "tcp"
    else
        printf ""
    fi
}

#remove iptables rules for the current config
iptablesserver D

echo "Select NordVPN server and create config file"

echo "Apply filter technology \"$(gettechnologyname "$TECHNOLOGY")\""
filterserver="filters\[servers_technologies\]\[id\]=$(gettechnologyid "$TECHNOLOGY")"

IFS=';'
read -ra RA_GROUPS <<< $GROUP
for value in "${RA_GROUPS[@]}"; do
    if [ ! -z "$value" ]; then
        echo "Apply filter group \"$(getgrouptitle $value)\""
        filterserver="$filterserver""&filters\[servers_groups\]\[id\]=$(getgroupid "$value")"
    fi
done

servers=""

if [ -z "$COUNTRY" ]; then
    servers=$(curl -s "https://api.nordvpn.com/v1/servers/recommendations?""$filterserver" | jq -c '.[]')
else
    read -ra RA_COUNTRIES <<< $COUNTRY
    for value in "${RA_COUNTRIES[@]}"; do
        if [ ! -z "$value" ]; then
            serversincountry=$(curl -s "https://api.nordvpn.com/v1/servers/recommendations?""$filterserver""&filters\[country_id\]=$(getcountryid "$value")" | jq -c '.[]')
            echo ""$(echo "$serversincountry" | jq -s 'length')" recommended servers in \"$(getcountryname "$value")\""
            servers="$servers""$serversincountry"
        fi
    done
fi

poollength=$(echo "$servers" | jq -s 'unique | length')
servers=$(echo "$servers" | jq -s -c 'unique | sort_by(.load) | .[]')

if [[ !($RANDOM_TOP -eq 0) ]]; then
    if [[ $RANDOM_TOP -lt poollength ]]; then
        filtered=$(echo $servers | head -n $RANDOM_TOP | shuf)
        servers="$filtered"$(echo $servers | tail -n +$((RANDOM_TOP + 1)))
    else
        servers=$(echo $servers | shuf)
    fi
fi

echo "$poollength"" recommended servers in pool"
if [[ !($poollength -eq 0) ]]; then
    echo "--- Top 20 servers in filtered pool ---"
    echo $(echo $servers | jq -r '[.hostname, .load] | "\(.[0]): \(.[1])"' | head -n 20)
    echo "---------------------------------------"
fi

if [[ $poollength -eq 0 ]]; then
    echo "ERROR: selected server list is empty"
fi

serverip=$(echo $servers | jq -r '.station' | head -n 1)
name=$(echo $servers | jq -r '.name' | head -n 1)
hostname=$(echo $servers | jq -r '.hostname' | head -n 1)
protocol=$(getopenvpnprotocol "$TECHNOLOGY")

echo "Select server \""$name"\" hostname=\""$hostname"\" ip="$serverip" protocol=\""$protocol"\""

cp "$ovpntemplatefile" "$ovpnfile"
echo "script-security 2" >> "$ovpnfile"
echo "up /etc/openvpn/up.sh" >> "$ovpnfile"
echo "down /etc/openvpn/down.sh" >> "$ovpnfile"

sed -i "s/__IP__/$serverip/g" "$ovpnfile"
sed -i "s/__PROTOCOL__/$protocol/g" "$ovpnfile"

if [[ "$protocol" == "udp" ]]; then
    sed -i "s/__PORT__/1194/g" "$ovpnfile"
elif [[ "$protocol" == "tcp" ]]; then
    sed -i "s/__PORT__/443/g" "$ovpnfile"
else
    echo "ERROR: TECHNOLOGY environment variable contains wrong parameter ("$TECHNOLOGY")"
fi

# Create auth_file
echo "$USER" > "$authfile"
echo "$PASS" >> "$authfile"
chmod 0600 "$authfile"

iptablesserver A

exit 0
