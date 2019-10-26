ARG ARCH=amd64
FROM balenalib/${ARCH}-alpine

LABEL maintainer="Julio Gutierrez <bubuntux@gmail.com>"

#CROSSRUN [ "cross-build-start" ]
RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add bash curl jq ip6tables iptables openvpn shadow tini tzdata && \
    addgroup -S vpn && \
    rm -rf /tmp/*
#CROSSRUN [ "cross-build-end" ]

ENV NET_IFACE=eth0

VOLUME ["/vpn"]
ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/nordVpn.sh"]
COPY nordVpn.sh /usr/bin
