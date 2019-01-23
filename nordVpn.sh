#!/bin/bash

# Firewall everything has to go through the vpn
iptables  -F OUTPUT
ip6tables -F OUTPUT 2> /dev/null
iptables  -P OUTPUT DROP
ip6tables -P OUTPUT DROP 2> /dev/null
iptables  -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 
ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o tun0 -j ACCEPT 
ip6tables -A OUTPUT -o tun0 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -d `ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}'` -j ACCEPT
ip6tables -A OUTPUT -d `ip -o addr show dev eth0 | awk '$3 == "inet6" {print $4; exit}'` -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -p udp --dport 53 -j ACCEPT
ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o eth0 -p udp --dport 443 -j ACCEPT    
ip6tables -A OUTPUT -o eth0 -p udp --dport 443 -j ACCEPT 2> /dev/null 
iptables  -A OUTPUT -o eth0 -p tcp --dport 443 -j ACCEPT              
ip6tables -A OUTPUT -o eth0 -p tcp --dport 443 -j ACCEPT 2> /dev/null 
iptables  -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT 
ip6tables -A OUTPUT -o eth0 -p udp --dport 1194 -j ACCEPT 2> /dev/null
iptables  -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT 
ip6tables -A OUTPUT -o eth0 -p tcp --dport 1194 -j ACCEPT 2> /dev/null

iptables_domain=`echo $URL_NORDVPN_API | awk -F/ '{print $3}'`
iptables  -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT
ip6tables -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT 2> /dev/null

if [ ! -z $NETWORK ]; then
    gw=`ip route | awk '/default/ {print $3}'`
    ip route add to $NETWORK via $gw dev eth0
    iptables -A OUTPUT --destination $NETWORK -j ACCEPT
fi

if [ ! -z $NETWORK6 ]; then
    gw=`ip -6 route | awk '/default/ {print $3}'`
    ip -6 route add to $NETWORK6 via $gw dev eth0
    ip6tables -A OUTPUT --destination $NETWORK6 -j ACCEPT 2> /dev/null
fi

base_dir="/vpn"
ovpn_dir="$base_dir/ovpn"
auth_file="$base_dir/auth"

if [ `ls -A $ovpn_dir | wc -l` -eq 0 ]
then
    echo "Server configs not found. Download configs from NordVPN"
    iptables_domain=`echo $URL_OVPN_FILES | awk -F/ '{print $3}'`
    iptables  -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT
    ip6tables -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT 2> /dev/null
    curl -s $URL_OVPN_FILES -o /tmp/ovpn.zip
    unzip -q /tmp/ovpn.zip -d /tmp/ovpn
    mv /tmp/ovpn/*/*.ovpn $ovpn_dir
    rm -rf /tmp/*
fi

# Use api.nordvpn.com
servers=`curl -s $URL_NORDVPN_API`
servers=`echo $servers | jq -c '.[] | select(.features.openvpn_udp == true)' &&\
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
    if [[ -z "${PROTOCOL}" ]]; then
        echo "Protocol not set, skip filtering"
    else
        echo "Filter pool by protocol: $PROTOCOL"
        filtered=`echo $servers | jq -c 'select(.features.'$PROTOCOL' == true)' | jq -s -a -c 'unique'`
        pool_length=`echo $filtered | jq 'length'`
        echo "Servers in filtered pool: $pool_length"
        servers=`echo $filtered | jq -c '.[]'`
    fi
fi

if [[ !($pool_length -eq 0) ]]; then
    echo "Filter pool by load, less than $MAX_LOAD%"
    servers=`echo $servers | jq -c 'select(.load <= '$MAX_LOAD')'`
    pool_length=`echo $servers | jq -s -a -c 'unique' | jq 'length'`
    echo "Servers in filtered pool: $pool_length"
    servers=`echo $servers | jq -s -c 'sort_by(.load)[]'`
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
    if [[ -z "${PROTOCOL}" ]] || [[ "${PROTOCOL}" == "openvpn_udp" ]]; then
        config_file="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        else
            echo "UDP config for server $server not found"
        fi
    fi
    if [[ -z "${PROTOCOL}" ]] || [[ "${PROTOCOL}" == "openvpn_tcp" ]]; then
        config_file="${ovpn_dir}/${server}.tcp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        else
            echo "TCP config for server $server not found"
        fi
    fi
done

if [ -z $config ]; then
    echo "Filtered pool is empty or configs not found. Select server from recommended list"
    iptables_domain=`echo $URL_RECOMMENDED_SERVERS | awk -F/ '{print $3}'`
    iptables  -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT
    ip6tables -A OUTPUT -o eth0 -d $iptables_domain -j ACCEPT 2> /dev/null
    recommendations=`curl -s $URL_RECOMMENDED_SERVERS | jq -r '.[] | .hostname' | shuf`
    for server in ${recommendations}; do # Prefer UDP
        config_file="${ovpn_dir}/${server}.udp.ovpn"
        if [ -r "$config_file" ]; then
            config="$config_file"
            break
        else
            echo "UDP config for server $server not found"
        fi
    done
    if [ -z $config ]; then # Use TCP if UDP not available
       for server in ${recommendations}; do
            config_file="${ovpn_dir}/${server}.tcp.ovpn"
            if [ -r "$config_file" ]; then
                config="$config_file"
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

openvpn --cd $base_dir --config $config \
    --auth-user-pass $auth_file --auth-nocache \
    --script-security 2 --up /etc/openvpn/up.sh --down /etc/openvpn/down.sh
