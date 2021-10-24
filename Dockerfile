# s6 overlay builder
FROM alpine:3.14 AS s6-builder

ENV PACKAGE="just-containers/s6-overlay"
ENV PACKAGEVERSION="2.2.0.3"
ARG TARGETPLATFORM

RUN echo "**** upgrade packages ****" && \
    apk --no-cache --no-progress add openssl=1.1.1l-r0 && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add tar=1.34-r0 && \
    echo "**** create folders ****" && \
    mkdir -p /s6 && \
    echo "**** download ${PACKAGE} ****" && \
    PACKAGEPLATFORM=$(case ${TARGETPLATFORM} in \
        "linux/amd64")    echo "amd64"    ;; \
        "linux/386")      echo "x86"      ;; \
        "linux/arm64")    echo "aarch64"  ;; \
        "linux/arm/v7")   echo "armhf"    ;; \
        "linux/arm/v6")   echo "arm"      ;; \
        "linux/ppc64le")  echo "ppc64le"  ;; \
        *)                echo ""         ;; esac) && \
    echo "Package ${PACKAGE} platform ${PACKAGEPLATFORM} version ${PACKAGEVERSION}" && \
    wget -q "https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}/s6-overlay-${PACKAGEPLATFORM}.tar.gz" -qO /tmp/s6-overlay.tar.gz && \
    tar xfz /tmp/s6-overlay.tar.gz -C /s6/

# ovpn builder
FROM alpine:3.14 AS ovpn-builder

COPY /ovpn.zip /tmp/ovpn.zip

RUN echo "**** upgrade packages ****" && \
    apk --no-cache --no-progress add openssl=1.1.1l-r0 && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add unzip=6.0-r9 && \
    echo "**** create folders ****" && \
    mkdir -p /ovpn && \
    echo "**** download NordVPN OpenVPN config files ****" && \
    unzip -q /tmp/ovpn.zip -d /tmp/ovpn && \
    mv /tmp/ovpn/*/*.ovpn /ovpn

# rootfs builder
FROM alpine:3.14 AS rootfs-builder

RUN echo "**** upgrade packages ****" && \
    apk --no-cache --no-progress add openssl=1.1.1l-r0 && \
    echo "**** create folders ****" && \
    mkdir -p /ovpn

COPY root/ /rootfs/
RUN chmod +x /rootfs/usr/bin/*
COPY --from=s6-builder /s6/ /rootfs/
COPY --from=ovpn-builder /ovpn/ /rootfs/ovpn/

# Main image
FROM alpine:3.14

LABEL maintainer="Alexander Zinchenko <alexander@zinchenko.com>"

ENV TECHNOLOGY=openvpn_udp \
    RANDOM_TOP=0 \
    CHECK_CONNECTION_ATTEMPTS=5 \
    CHECK_CONNECTION_ATTEMPT_INTERVAL=10

RUN echo "**** upgrade packages ****" && \
    apk --no-cache --no-progress add openssl=1.1.1l-r0 && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add bash=5.1.4-r0 \
        curl=7.79.1-r0 \
        iptables=1.8.7-r1 \
        ip6tables=1.8.7-r1 \
        jq=1.6-r1 \
        openvpn=2.5.2-r0 && \
    echo "**** create folders ****" && \
    mkdir -p /vpn && \
    mkdir -p /ovpn && \
    echo "**** cleanup ****" && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/*

COPY --from=rootfs-builder /rootfs/ /

VOLUME ["/config"]

WORKDIR  /config

ENTRYPOINT ["/init"]
