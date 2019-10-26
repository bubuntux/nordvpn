#!/bin/bash

firewall() { # Everything has to go through the vpn
    local docker_network=` ip -o addr show dev ${NET_IFACE} | awk '$3 == "inet"  {print $4}'      ` \
          docker6_network=`ip -o addr show dev ${NET_IFACE} | awk '$3 == "inet6" {print $4; exit}'`

    echo "Staring firewall..." > /dev/stderr
    iptables  -F OUTPUT
    ip6tables -F OUTPUT 2> /dev/null
    iptables  -P OUTPUT DROP
    ip6tables -P OUTPUT DROP 2> /dev/null
    iptables  -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2> /dev/null
    iptables  -A OUTPUT -o lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT 2> /dev/null
    iptables  -A OUTPUT -o tap0 -j ACCEPT
    ip6tables -A OUTPUT -o tap0 -j ACCEPT 2>/dev/null
    iptables  -A OUTPUT -o tun0 -j ACCEPT
    ip6tables -A OUTPUT -o tun0 -j ACCEPT 2> /dev/null
    iptables  -A OUTPUT -d ${docker_network} -j ACCEPT
    ip6tables -A OUTPUT -d ${docker6_network} -j ACCEPT 2> /dev/null
    iptables  -A OUTPUT -p udp --dport 53 -j ACCEPT
    ip6tables -A OUTPUT -p udp --dport 53 -j ACCEPT 2> /dev/null
    iptables  -A OUTPUT -p tcp -m owner --gid-owner vpn -j ACCEPT 2>/dev/null &&
    iptables  -A OUTPUT -p udp -m owner --gid-owner vpn -j ACCEPT || {
        iptables  -A OUTPUT -p tcp -m tcp --dport 1194 -j ACCEPT
        iptables  -A OUTPUT -p udp -m udp --dport 1194 -j ACCEPT; }
    ip6tables -A OUTPUT -p tcp -m owner --gid-owner vpn -j ACCEPT 2>/dev/null &&
    ip6tables -A OUTPUT -p udp -m owner --gid-owner vpn -j ACCEPT 2>/dev/null || {
        ip6tables -A OUTPUT -p tcp -m tcp --dport 1194 -j ACCEPT 2>/dev/null
        ip6tables -A OUTPUT -p udp -m udp --dport 1194 -j ACCEPT 2>/dev/null; }

    [[ -n ${NETWORK} ]]  && for net in ${NETWORK//[;,]/ };  do return_route ${net};  done
    [[ -n ${NETWORK6} ]] && for net in ${NETWORK6//[;,]/ }; do return_route6 ${net}; done
    [[ -n ${WHITELIST} ]] && for domain in ${WHITELIST//[;,]/ }; do white_list ${domain}; done
}

return_route() { # Add a route back to your network, so that return traffic works
    local network="$1" gw="$(ip route | awk '/default/ {print $3}')"
    echo "Adding network route ${network}..." > /dev/stderr
    ip route add to ${network} via ${gw} dev ${NET_IFACE}
    iptables -A OUTPUT --destination ${network} -j ACCEPT
}

return_route6() { # Add a route back to your network, so that return traffic works
    local network="$1" gw="$(ip -6 route | awk '/default/ {print $3}')"
    echo "Adding network route ${network}..." > /dev/stderr
    ip -6 route add to ${network} via ${gw} dev ${NET_IFACE}
    ip6tables -A OUTPUT --destination ${network} -j ACCEPT 2> /dev/null
}

white_list() { # Allow unsecured traffic for an specific domain
    local domain=`echo $1 | sed 's/^.*:\/\///;s/\/.*$//'`
    echo "Whitelisting ${domain}..." > /dev/stderr
    iptables  -A OUTPUT -o ${NET_IFACE} -d ${domain} -j ACCEPT
    ip6tables -A OUTPUT -o ${NET_IFACE} -d ${domain} -j ACCEPT 2> /dev/null
}

download_ovpn() { # Download ovpn files into the specified directory
    local nordvpn_ovpn="https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip" \
          ovpn_dir="/vpn/ovpn"

    mkdir -p ${ovpn_dir}
    if [[ $(ls -A ${ovpn_dir} | wc -l) -eq 0 ]]; then
        white_list ${nordvpn_ovpn}
        echo "Downloading config files..." > /dev/stderr
        curl -s ${nordvpn_ovpn} -o /tmp/ovpn.zip
        mkdir -p /tmp/ovpn/
        unzip -q /tmp/ovpn.zip -d /tmp/ovpn
        mv /tmp/ovpn/*/*.ovpn ${ovpn_dir}
        rm -rf /tmp/*
    fi
    if [[ $(ls -A ${ovpn_dir} | wc -l) -eq 0 ]]; then
        echo "Unable to download config files" > /dev/stderr
        kill -s TERM ${TOP_PID} ; return
    fi

    echo ${ovpn_dir}
}

country_filter() { # curl -s "https://api.nordvpn.com/v1/servers/countries" | jq -r '.[] | [.code, .name] | @tsv'
    local nordvpn_api=$1 country=(${COUNTRY//[;,]/ })
    if [[ ${#country[@]} -ge 1 ]]; then
        country=${country[0]//_/ }
        local country_id=`curl -s "${nordvpn_api}/v1/servers/countries" | jq -r ".[] |
                          select( (.name|test(\"^${country}$\";\"i\")) or
                                  (.code|test(\"^${country}$\";\"i\")) ) |
                          .id" | head -n 1`
        if [[ -n ${country_id} ]]; then
            echo "Searching for country : ${country} (${country_id})" > /dev/stderr
            echo "filters\[country_id\]=${country_id}&"
        fi
    fi
}

group_filter() { # curl -s "https://api.nordvpn.com/v1/servers/groups" | jq -r '.[] | [.identifier, .title] | @tsv'
    local nordvpn_api=$1 category=(${CATEGORY//[;,]/ })
    if [[ ${#category[@]} -ge 1 ]]; then
        category=${category[0]//_/ }
        local identifier=`curl -s "${nordvpn_api}/v1/servers/groups" | jq -r ".[] |
                          select( .title | test(\"${category}\";\"i\") ) |
                          .identifier" | head -n 1`
        if [[ -n ${identifier} ]]; then
            echo "Searching for group: ${identifier}" > /dev/stderr
            echo "filters\[servers_groups\]\[identifier\]=${identifier}&"
        fi
    fi
}

technology_filter() { # curl -s "https://api.nordvpn.com/v1/technologies" | jq -r '.[] | [.identifier, .name ] | @tsv' | grep openvpn
    local identifier
    if [[ ${PROTOCOL,,} =~ .*udp.* ]]; then
        identifier="openvpn_udp"
    elif [[ ${PROTOCOL,,} =~ .*tcp.* ]];then
        identifier="openvpn_tcp"
    fi
    if [[ -n ${identifier} ]]; then
        echo "Searching for technology: ${identifier}" > /dev/stderr
        echo "filters\[servers_technologies\]\[identifier\]=${identifier}&"
    fi
}

select_hostname() {
    local nordvpn_api="https://api.nordvpn.com" \
          filters hostname

    white_list ${nordvpn_api}

    if [[ -z $HOSTNAME ]]; then
        echo "Selecting the best server..." > /dev/stderr
        filters+="$(country_filter ${nordvpn_api})"
        filters+="$(group_filter ${nordvpn_api})"
        filters+="$(technology_filter )"

        hostname=`curl -s "${nordvpn_api}/v1/servers/recommendations?${filters}limit=1" | jq -r ".[].hostname"`
        if [[ -z ${hostname} ]]; then
            echo "Unable to find a server with the specified parameters, using any recommended server" > /dev/stderr
            hostname=`curl -s "${nordvpn_api}/v1/servers/recommendations?limit=1" | jq -r ".[].hostname"`
        fi

        echo "Best server : ${hostname}" > /dev/stderr
        echo ${hostname}
    else
        echo "Using supplied hostname '$HOSTNAME'..." > /dev/stderr
        echo ${HOSTNAME}
    fi

}

select_config_file() {
    local ovpn_dir=$1 \
          hostname=$(select_hostname) \
          post_fix config_file

    if [[ ${PROTOCOL,,} =~ .*udp.* ]]; then
        post_fix=".udp.ovpn"
    elif [[ ${PROTOCOL,,} =~ .*tcp.* ]];then
        post_fix=".tcp.ovpn"
    fi

    config_file="${ovpn_dir}/$(ls ${ovpn_dir} | grep "${hostname}${post_fix}" | shuf | head -n 1)"
    if [[ ! -f ${config_file} ]]; then
        echo "Unable to find config file ${config_file}" > /dev/stderr
        config_file="${ovpn_dir}/$(ls ${ovpn_dir} | shuf | head -n 1)"
        if [[ ! -f ${config_file} ]]; then
                kill -s TERM ${TOP_PID} ; return
        fi
    fi

    echo "Using config file ${config_file}..." > /dev/stderr
    echo ${config_file}
}

write_auth_file() {
    local auth_file="/vpn/auth"

    if [[ -z ${USER} || -z ${PASS} ]]; then
        if [[ ! -f ${auth_file} ]]; then
            echo "Missing USER or PASS" > /dev/stderr
            kill -s TERM ${TOP_PID} ; return
        fi
    else
        echo "${USER}" > ${auth_file}
        echo "${PASS}" >> ${auth_file}
    fi
    chmod 0600 ${auth_file}

    echo ${auth_file}
}

if [[ $# -ge 1 && -x $(which $1 2>&-) ]]; then
    exec "$@"
elif [[ $# -ge 1 ]]; then
    echo "ERROR: command not found: $1"
    exit 13
elif ps -ef | egrep -v 'grep|nordVpn.sh' | grep -q openvpn; then
    echo "Service already running, please restart container to apply changes"
else
    trap "exit 1" TERM
    TOP_PID=$$

    auth_file=$(write_auth_file)

    [[ ${GROUPID:-""} =~ ^[0-9]+$ ]] && groupmod -g ${GROUPID} -o vpn
    firewall

    ovpn_dir=$(download_ovpn)

    mkdir -p /dev/net
    [[ -c /dev/net/tun ]] || mknod -m 0666 /dev/net/tun c 10 200

    while :; do
        config_file=$(select_config_file ${ovpn_dir})
        echo "Connecting ... "
        set -x
        sg vpn -c "openvpn --config ${config_file} --auth-user-pass ${auth_file} --auth-nocache \
                                --script-security 2 --up /etc/openvpn/up.sh --down /etc/openvpn/down.sh \
                                ${OPENVPN_OPTS}"
        set +x
        sleep 1
    done
fi