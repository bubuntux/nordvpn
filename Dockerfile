# s6 overlay builder
FROM alpine:3.21.3 AS s6-builder

ENV PACKAGE="just-containers/s6-overlay"
ENV PACKAGEVERSION="3.2.0.2"
ARG TARGETPLATFORM

RUN echo "**** install security fix packages ****" && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add \
        tar=1.35-r2 \
        xz=5.6.3-r0 \
        && \
    echo "**** create folders ****" && \
    mkdir -p /s6 && \
    echo "**** download ${PACKAGE} ****" && \
    PACKAGEPLATFORM=$(case ${TARGETPLATFORM} in \
        "linux/386")      echo "i486"        ;; \
        "linux/amd64")    echo "x86_64"      ;; \
        "linux/arm/v6")   echo "arm"         ;; \
        "linux/arm/v7")   echo "armhf"       ;; \
        "linux/arm64")    echo "aarch64"     ;; \
        "linux/ppc64le")  echo "powerpc64le" ;; \
        "linux/riscv64")  echo "riscv64"     ;; \
        "linux/s390x")    echo "s390x"       ;; \
        *)                echo ""            ;; esac) && \
    echo "Package ${PACKAGE} platform ${PACKAGEPLATFORM} version ${PACKAGEVERSION}" && \
    wget -q "https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}/s6-overlay-noarch.tar.xz" -qO /tmp/s6-overlay-noarch.tar.xz && \
    wget -q "https://github.com/${PACKAGE}/releases/download/v${PACKAGEVERSION}/s6-overlay-${PACKAGEPLATFORM}.tar.xz" -qO /tmp/s6-overlay-binaries.tar.xz && \
    tar -C /s6/ -Jxpf /tmp/s6-overlay-noarch.tar.xz && \
    tar -C /s6/ -Jxpf /tmp/s6-overlay-binaries.tar.xz

# rootfs builder
FROM alpine:3.21.3 AS rootfs-builder

RUN echo "**** install security fix packages ****" && \
    echo "**** end run statement ****"

COPY root/ /rootfs/
RUN chmod +x /rootfs/usr/bin/*
RUN chmod +x /rootfs/etc/nordvpn/init/*
COPY --from=s6-builder /s6/ /rootfs/

# Main image
FROM alpine:3.21.3

LABEL maintainer="Alexander Zinchenko <alexander@zinchenko.com>"

ENV TECHNOLOGY=openvpn_udp \
    RANDOM_TOP=0 \
    CHECK_CONNECTION_ATTEMPTS=5 \
    CHECK_CONNECTION_ATTEMPT_INTERVAL=10 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=120000

RUN echo "**** install security fix packages ****" && \
    echo "**** install mandatory packages ****" && \
    apk --no-cache --no-progress add \
        bash=5.2.37-r0 \
        curl=8.12.1-r0 \
        iptables=1.8.11-r1 \
        ip6tables=1.8.11-r1 \
        jq=1.7.1-r0 \
        shadow=4.16.0-r1 \
        shadow-login=4.16.0-r1 \
        openvpn=2.6.12-r1 \
        bind-tools=9.18.34-r0 \
        && \
    echo "**** create process user ****" && \
    addgroup --system --gid 912 nordvpn && \
    adduser --system --uid 912 --disabled-password --no-create-home --ingroup nordvpn nordvpn && \
    echo "**** cleanup ****" && \
    rm -rf /tmp/* && \
    rm -rf /var/cache/apk/*

COPY --from=rootfs-builder /rootfs/ /

ENTRYPOINT ["/init"]
