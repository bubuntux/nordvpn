ARG ARCH=amd64
FROM balenalib/${ARCH}-debian

ARG NORDVPN_VERSION
LABEL maintainer="Pedro Rodrigues"

HEALTHCHECK --interval=1m --timeout=10s --start-period=1m \
    CMD if [[ $( curl -s https://api.nordvpn.com/vpn/check/full | jq -r '.["status"]' ) = "Protected" ]] ; then exit 0; else exit 1; fi

RUN addgroup --system vpn && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y wget dpkg curl gnupg2 jq privoxy runit && \
    wget -nc https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb && dpkg -i nordvpn-release_1.0.0_all.deb && \
    apt-get update && apt-get install -yqq nordvpn${NORDVPN_VERSION:+=$NORDVPN_VERSION} || sed -i "s/init)/$(ps --no-headers -o comm 1))/" /var/lib/dpkg/info/nordvpn.postinst && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && \
    apt-get install -yqq && apt-get clean && \
    rm -rf \
        ./nordvpn* \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*

COPY app /app

RUN echo "####### Changing permissions #######" && \
    find /app -name run | xargs chmod u+x

# Start a process for each of the folders in /app
CMD ["runsvdir", "/app"]
