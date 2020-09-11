ARG ARCH=amd64
FROM balenalib/${ARCH}-debian

ARG NORDVPN_VERSION
LABEL maintainer="Julio Gutierrez"

HEALTHCHECK --interval=5m --timeout=20s --start-period=1m \
  CMD if test $( curl -m 10 -s https://api.nordvpn.com/vpn/check/full | jq -r '.["status"]' ) = "Protected" ; then exit 0; else nordvpn connect ${CONNECT} ; exit $?; fi

#CROSSRUN [ "cross-build-start" ]
RUN addgroup --system vpn && \
    apt-get update && apt-get upgrade -y && \
    apt-get install -y wget dpkg curl gnupg2 jq && \
    wget -nc https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn-release_1.0.0_all.deb && dpkg -i nordvpn-release_1.0.0_all.deb && \
    apt-get update && apt-get install -yqq nordvpn${NORDVPN_VERSION:+=$NORDVPN_VERSION} || sed -i "s/init)/$(ps --no-headers -o comm 1))/" /var/lib/dpkg/info/nordvpn.postinst && \
    update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy && \
    mv /sbin/sysctl /sbin/sysctl.orig && \
    apt-get install -yqq && apt-get clean && \
    rm -rf \
        ./nordvpn* \
        /tmp/* \
        /var/lib/apt/lists/* \
        /var/tmp/*
#CROSSRUN [ "cross-build-end" ]

COPY start_vpn.sh /usr/bin
COPY sysctl_wrapper.sh /sbin/sysctl

CMD /usr/bin/start_vpn.sh
