# THIS REPOSITORY IS NOT MAINTAINED

**I recommend switching to use [github.com/qdm12/gluetun](https://github.com/qdm12/gluetun) instead.**

---

<p align="center">
    <a href="https://nordvpn.com/"><img src="https://github.com/bubuntux/nordvpn/raw/master/.img/NordVpn_logo.png"/></a>
    </br>
    <a href="https://github.com/bubuntux/nordvpn/blob/master/LICENSE"><img src="https://badgen.net/github/license/bubuntux/nordvpn?color=cyan"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/size/bubuntux/nordvpn?icon=docker&label=size"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/pulls/bubuntux/nordvpn?icon=docker&label=pulls"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/stars/bubuntux/nordvpn?icon=docker&label=stars"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/forks/bubuntux/nordvpn?icon=github&label=forks&color=black"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/stars/bubuntux/nordvpn?icon=github&label=stars&color=black"/></a>
    <a href="https://github.com/bubuntux/nordvpn/actions/workflows/deploy.yml"><img src="https://github.com/bubuntux/nordvpn/actions/workflows/deploy.yml/badge.svg?branch=master"/></a>
</p>

Official `NordVPN` client in a docker container; it makes routing traffic through the `NordVPN` network easy and secure with an integrated iptables kill switch.

# How to use this image
This container was designed to be started first to provide a connection to other containers (using `--net=container:vpn`, see below *Starting an NordVPN client instance*).

**NOTE**: More than the basic privileges are needed for NordVPN. With Docker 1.2 or newer, Podman, Kubernetes, etc. you can use the `--cap-add=NET_ADMIN,NET_RAW` option. Earlier versions, or with fig, and you'll have to run it in privileged mode.

## Starting an NordVPN instance
    docker run -ti --cap-add=NET_ADMIN --cap-add=NET_RAW --name vpn \
               -e TOKEN=f6f2bb45... \
               -e TECHNOLOGY=NordLynx -d ghcr.io/bubuntux/nordvpn

Once it's up other containers can be started using its network connection:

    docker run -it --net=container:vpn -d other/docker-container

## docker-compose example
```
version: "3"
services:
  vpn:
    image: ghcr.io/bubuntux/nordvpn
    cap_add:
      - NET_ADMIN               # Required
      - NET_RAW                 # Required
    environment:                # Review https://github.com/bubuntux/nordvpn#environment-variables
      - TOKEN=f6f2bb45...     # Required
      - CONNECT=United_States
      - TECHNOLOGY=NordLynx
      - NETWORK=192.168.1.0/24  # So it can be accessed within the local network
    ports:
      - 8080:8080
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=1  # Recomended if using ipv4 only
  torrent:
    image: ghcr.io/linuxserver/qbittorrent
    network_mode: service:vpn
    depends_on:
      - vpn
      
# The torrent service would be available at http://localhost:8080/ 
# or anywhere inside of the local network http://192.168.1.xxx:8080
 ```

## docker-compose example using reverse proxy
```
version: "3"
services:
  proxy:
    image: traefik:v2.4         # Review traefik documentation https://doc.traefik.io/traefik/ 
    container_name: traefik
    command:
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
    ports:
      - 80:80
      - 8080:8080
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
  vpn:
    image: ghcr.io/bubuntux/nordvpn
    container_name: vpn
    cap_add:
      - NET_ADMIN               # Required
      - NET_RAW                 # Required
    environment:                # Review https://github.com/bubuntux/nordvpn#environment-variables
      - TOKEN=f6f2bb45...       # Required
      - CONNECT=United_States
      - TECHNOLOGY=NordLynx
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=1  # Recomended if using ipv4 only
  torrent:
    image: ghcr.io/linuxserver/qbittorrent
    network_mode: container:vpn
    labels:
      - traefik.enable=true
      - traefik.http.services.torrent.loadbalancer.server.port=8080
      - traefik.http.routers.torrent.rule=Host(`custom-host`)
    depends_on:
      - vpn
      
# Make sure that custom-host resolves to the ip address of the server 
# for example /etc/hosts contains 127.0.0.1  custom-host
# the torrent service would be available at http://custom-host
```

## docker-compose example using reverse proxy with TLS
```
version: "3"
services:
  proxy:
    image: traefik:v2.4             # Review traefik documentation https://doc.traefik.io/traefik/ 
    container_name: traefik
    command:
      - --api.insecure=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.websecure.address=:443
      - --entrypoints.websecure.http.tls.certresolver=letsencrypt
      - --certificatesresolvers.letsencrypt.acme.tlschallenge=true
      - --certificatesresolvers.letsencrypt.acme.email=my@email.com # Replace with your email
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
    ports:
      - 80:80
      - 443:443
      - 8080:8080
    volumes:
      - ./letsencrypt:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
  domain:
    image: ghcr.io/linuxserver/duckdns   # Review doc https://github.com/linuxserver/docker-duckdns
    container_name: duckdns
    environment:
      - TOKEN=ABCDFEG                    # Required
      - SUBDOMAINS=domain1,domain2       # Required
    restart: unless-stopped
  media:
    image: ghcr.io/linuxserver/plex
    container_name: plex
    labels:
      - traefik.enable=true
      - traefik.http.services.media.loadbalancer.server.port=32400
      - traefik.http.routers.media.rule=Host(`myplex.duckdns.org`)   # Replace with your domain
    devices:
      - /dev/dri:/dev/dri
    restart: unless-stopped
  vpn:
    image: ghcr.io/bubuntux/nordvpn
    container_name: nordvpn
    cap_add:
      - NET_ADMIN               # Required
      - NET_RAW                 # Required
    environment:                # Review https://github.com/bubuntux/nordvpn#environment-variables
      - TOKEN=f6f2bb45...       # Required
      - CONNECT=United_States
      - TECHNOLOGY=NordLynx
      - WHITELIST=showrss.info,rarbg.to,yts.mx
     sysctls:
      - net.ipv6.conf.all.disable_ipv6=1  # Recomended if using ipv4 only
  torrent:
    image: ghcr.io/linuxserver/qbittorrent
    container_name: qbittorrent
    network_mode: service:vpn
    depends_on:
      - vpn
    labels:
      - traefik.enable=true
      - traefik.http.services.torrent.loadbalancer.server.port=8080
      - traefik.http.routers.torrent.rule=Host(`mytorrent.duckdns.org`) # Replace with your domain
    restart: unless-stopped
    
# Make sure that you can access your server from the internet
# for example configure dmz on your router
# the torrent service would be available at https://mytorrent.duckdns.org
```

# ENVIRONMENT VARIABLES

* `TOKEN`    - Token for NordVPN account, can be generated in the web portal
* `TOKENFILE` - File from which to get `TOKEN`, if using [docker secrets](https://docs.docker.com/compose/compose-file/compose-file-v3/#secrets) this should be set to `/run/secrets/<secret_name>`. Thi
* `CONNECT`  -  [country]/[server]/[country_code]/[city]/[group] or [country] [city], if none provide you will connect to  the recommended server.
   - Provide a [country] argument to connect to a specific country. For example: Australia , Use `docker run --rm ghcr.io/bubuntux/nordvpn nordvpn countries` to get the list of countries.
   - Provide a [server] argument to connect to a specific server. For example: jp35 , [Full List](https://nordvpn.com/servers/tools/)
   - Provide a [country_code] argument to connect to a specific country. For example: us 
   - Provide a [city] argument to connect to a specific city. For example: 'Hungary Budapest' , Use `docker run --rm ghcr.io/bubuntux/nordvpn nordvpn cities [country]` to get the list of cities. 
   - Provide a [group] argument to connect to a specific servers group. For example: P2P , Use `docker run --rm ghcr.io/bubuntux/nordvpn nordvpn groups` to get the full list.
   - --group value  Specify a server group to connect to. For example: '--group p2p us'
* `PRE_CONNECT` - Command to execute before attempt to connect.
* `POST_CONNECT` - Command to execute after successful connection.
* `CYBER_SEC`  - Enable or Disable. When enabled, the CyberSec feature will automatically block suspicious websites so that no malware or other cyber threats can infect your device. Additionally, no flashy ads will come into your sight. More information on how it works: https://nordvpn.com/features/cybersec/.
* `DNS` -   Can set up to 3 DNS servers. For example 1.1.1.1,8.8.8.8 or Disable, Setting DNS disables CyberSec.
* `FIREWALL`  - Enable or Disable.
* `OBFUSCATE`  - Enable or Disable. When enabled, this feature allows to bypass network traffic sensors which aim to detect usage of the protocol and log, throttle or block it (only valid when using OpenVpn).
* `PROTOCOL`   - TCP or UDP (only valid when using OpenVPN).
* `TECHNOLOGY` - Specify Technology to use (NordLynx by default): 
   * OpenVPN    - Traditional connection.
   * NordLynx   - NordVpn wireguard implementation (3x-5x times faster than OpenVPN).
* `ALLOW_LIST` - List of domains that are going to be accessible _outside_ vpn (IE rarbg.to,yts.mx).
* `NET_LOCAL`  - CIDR networks (IE 192.168.1.0/24), add a route to allows replies once the VPN is up.
* `NET6_LOCAL` - CIDR IPv6 networks (IE fe00:d34d:b33f::/64), add a route to allows replies once the VPN is up.
* `PORTS`  - Semicolon delimited list of ports to whitelist for both UDP and TCP. For example '- PORTS=9091;9095'
* `PORT_RANGE`  - Port range to whitelist for both UDP and TCP. For example '- PORT_RANGE=9091 9095'
* `CHECK_CONNECTION_INTERVAL`  - Time in seconds to check connection and reconnect if need it. (300 by default) For example '- CHECK_CONNECTION_INTERVAL=600'
* `CHECK_CONNECTION_URL`  - URL for checking Internet connection. (www.google.com by default) For example '- CHECK_CONNECTION_URL=www.custom.domain'
* `MESHNET` - Enable or Disable.
* `ALLOWLOCAL` - Comma delimited list of Meshnet devices you will allow to access this devices local network. For example 'ALLOWLOCAL=vpn-friction5976.nord,vpn-world2962.nord'
* `ALLOWROUTE` - Comma delimited list of Meshnet devices you will allow to route though this device. For example 'ALLOWROUTE=vpn-friction5976.nord,vpn-world2962.nord'
* `LAN_DISCOVERY` - on or off.


# Issues

If you have any problems with or questions about this image, please contact me through a [GitHub issue](https://github.com/bubuntux/nordvpn/issues).

# Disclaimer 
This project is independently developed for personal use, there is no affiliation with NordVpn or Nord Security companies,
Nord Security companies are not responsible for and have no control over the nature, content and availability of this project.
