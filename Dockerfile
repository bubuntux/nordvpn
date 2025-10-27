FROM lscr.io/linuxserver/baseimage-ubuntu:noble
LABEL maintainer="Julio Gutierrez julio.guti+nordvpn@pm.me"

ARG NORDVPN_VERSION=4.1.1
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y curl iputils-ping libc6 wireguard && \
    curl https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/nordvpn-release/nordvpn-release_1.0.0_all.deb --output /tmp/nordrepo.deb && \
    apt-get install -y /tmp/nordrepo.deb && \
    apt-get update -y && \
    apt-get install -y nordvpn${NORDVPN_VERSION:+=$NORDVPN_VERSION} && \
    apt-get remove -y nordvpn-release && \
    apt-get autoremove -y && \
    apt-get autoclean -y && \
    rm -rf \
		/tmp/* \
		/var/cache/apt/archives/* \
		/var/lib/apt/lists/* \
		/var/tmp/*

COPY /rootfs /
RUN chmod +x /etc/cont-init.d/* /etc/services.d/nordvpn/* \
    /usr/bin/dockerNetworks /usr/bin/dockerNetworks6 /usr/bin/nord_config /usr/bin/nord_connect /usr/bin/nord_login /usr/bin/nord_migrate /usr/bin/nord_watch \
    /etc/services.d/nordvpn/data/check /usr/bin/healthcheck

HEALTHCHECK --interval=60s --timeout=15s --start-period=120s \
            CMD /usr/bin/healthcheck

ENV S6_CMD_WAIT_FOR_SERVICES=1
CMD nord_login && nord_config && nord_connect && nord_migrate && nord_watch
