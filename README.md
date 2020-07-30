<p align="center">
    <a href="https://nordvpn.com/"><img src="https://github.com/bubuntux/nordvpn/raw/master/NordVpn_logo.png"/></a>
    </br>
    <a href="https://github.com/bubuntux/nordvpn/blob/master/LICENSE"><img src="https://badgen.net/github/license/bubuntux/nordvpn?color=cyan"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/size/bubuntux/nordvpn?icon=docker&label=size"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/pulls/bubuntux/nordvpn?icon=docker&label=pulls"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/stars/bubuntux/nordvpn?icon=docker&label=stars"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/forks/bubuntux/nordvpn?icon=github&label=forks&color=black"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/stars/bubuntux/nordvpn?icon=github&label=stars&color=black"/></a>
    <a href="https://travis-ci.com/bubuntux/nordvpn"><img src="https://travis-ci.com/bubuntux/nordvpn.svg?branch=master"/></a>
</p>

NordVpn official client in a docker. It makes routing containers traffic through NordVpn easy.

# How to use this image

This container was designed to be started first to provide a connection to other containers (using `--net=container:vpn`, see below _Starting an NordVPN client instance_).

**NOTE**: More than the basic privileges are needed for NordVPN. With docker 1.2 or newer you can use the `--cap-add=NET_ADMIN` and `--device /dev/net/tun` options. Earlier versions, or with fig, and you'll have to run it in privileged mode.

## Starting an NordVPN instance

    docker run -ti --cap-add=NET_ADMIN --cap-add=SYS_MODULE --device /dev/net/tun --name vpn \
                --sysctl net.ipv4.conf.all.rp_filter=2 \
                -e USER=user@email.com -e PASS='pas$word' \
                -e CONNECT=country -e TECHNOLOGY=NordLynx -d bubuntux/nordvpn

Once it's up other containers can be started using it's network connection:

    docker run -it --net=container:vpn -d some/docker-container

## Local Network access to services connecting to the internet through the VPN.

However to access them from your normal network (off the 'local' docker bridge), you'll also need to run a web proxy, like so:

```
sudo docker run -it --name web -p 80:80 -p 443:443 \
            --link vpn:<service_name> -d dperson/nginx \
            -w "http://<service_name>:<PORT>/<URI>;/<PATH>"
```

Which will start a Nginx web server on local ports 80 and 443, and proxy any requests under /<PATH> to the to http://<service_name>:<PORT>/<URI>. To use a concrete example:

```
sudo docker run -it --name bit --net=container:vpn -d dperson/transmission
sudo docker run -it --name web -p 80:80 -p 443:443 --link vpn:bit \
            -d dperson/nginx -w "http://bit:9091/transmission;/transmission"
```

For multiple services (non-existant 'foo' used as an example):

```
sudo docker run -it --name bit --net=container:vpn -d dperson/transmission
sudo docker run -it --name foo --net=container:vpn -d dperson/foo
sudo docker run -it --name web -p 80:80 -p 443:443 --link vpn:bit \
            --link vpn:foo -d dperson/nginx \
            -w "http://bit:9091/transmission;/transmission" \
            -w "http://foo:8000/foo;/foo"
```

## Routing access without the web proxy.

The environment variable NETWORK must be your local network that you would connect to the server running the docker containers on. Running the following on your docker host should give you the correct network: `ip route | awk '!/ (docker0|br-)/ && /src/ {print $1}'`

    docker run -ti --cap-add=NET_ADMIN --device /dev/net/tun --name vpn \
                -p 8080:80 -e NETWORK=192.168.1.0/24 \
                -e USER=user@email.com -e PASS='pas$word' -d bubuntux/nordvpn

Now just create the second container _without_ the `-p` parameter, only inlcude the `--net=container:vpn`, the port should be declare in the vpn container.

    docker run -ti --rm --net=container:vpn -d bubuntux/riot-web

now the service provided by the second container would be available from the host machine (http://localhost:8080) or anywhere inside the local network (http://192.168.1.xxx:8080).

## docker-compose example with web proxy

```
version: "3"
services:
  vpn:
    image: bubuntux/nordvpn
    cap_add:
      - NET_ADMIN               # Required
      - SYS_MODULE              # Required for TECHNOLOGY=NordLynx
    sysctls:
      - net.ipv4.conf.all.rp_filter=2
    devices:
      - /dev/net/tun            # Required
    environment:                # Review https://github.com/bubuntux/nordvpn#environment-variables
      - USER=user@email.com     # Required
      - "PASS=pas$word"         # Required
      - CONNECT=United_States
      - TECHNOLOGY=NordLynx

  torrent:
    image: linuxserver/qbittorrent
    network_mode: service:vpn
    depends_on:
      - vpn

  web:
    image: dperson/nginx        # https://github.com/dperson/nginx
    links:
      - vpn:torrent
    depends_on:
      - torrent
    tmpfs:
      - /run
      - /tmp
      - /var/cache/nginx
    ports:
      - 80:80
      - 443:443
    command: -w "http://torrent:8080/;/"

# The torrent service would be available at http://localhost/
```

## docker-compose example without web proxy

```
version: "3"
services:
  vpn:
    image: bubuntux/nordvpn
    network_mode: bridge        # Required
    cap_add:
      - NET_ADMIN               # Required
      - SYS_MODULE              # Required for TECHNOLOGY=NordLynx
    sysctls:
      - net.ipv4.conf.all.rp_filter=2
    devices:
      - /dev/net/tun            # Required
    environment:                # Review https://github.com/bubuntux/nordvpn#environment-variables
      - USER=user@email.com     # Required
      - "PASS=pas$word"         # Required
      - CONNECT=United_States
      - TECHNOLOGY=NordLynx
      - NETWORK=192.168.1.0/24
    ports:
      - 8080:8080

  torrent:
    image: linuxserver/qbittorrent
    network_mode: service:vpn
    depends_on:
      - vpn

# The torrent service would be available at https://localhost:8080/ or anywhere inside the local network http://192.168.1.xxx:8080
```

## Killswitch

All traffic going through the container is router to the vpn (unless whitelisted), If connection to the vpn drops your connection to the internet stays blocked until the VPN tunnel is restored. THIS IS THE DEFAULT BEHAVIOUR AND CAN NOT BE DISABLE.

## Privoxy support

By defining the `HTTP_PROXY_PORT` ENV variable, [Privoxy](https://www.privoxy.org/) is enabled, to allow using the VPN from the browser.
Thanks to [Joentje](https://github.com/Joentje/nordvpn-proxy) for both Privoxy and runit example, in which this was based.

# ENVIRONMENT VARIABLES

- `USER` - User for NordVPN account.
- `PASS` - Password for NordVPN account, surrounding the password in single quotes will prevent issues with special characters such as `$`.
- `CONNECT` - [country]/[server]/[country_code]/[city]/[group] or [country][city], if none provide you will connect to the recommended server.
  - Provide a [country] argument to connect to a specific country. For example: Australia , Use `docker run --rm bubuntux/nordvpn sh -c "nordvpnd & sleep 1 && nordvpn countries"` to get the list of countries.
  - Provide a [server] argument to connecto to a specific server. For example: jp35 , [Full List](https://nordvpn.com/servers/tools/)
  - Provide a [country_code] argument to connect to a specific country. For example: us
  - Provide a [city] argument to connect to a specific city. For example: 'Hungary Budapest' , Use `docker run --rm bubuntux/nordvpn sh -c "nordvpnd & sleep 1 && nordvpn cities [country]"` to get the list of cities.
  - Provide a [group] argument to connect to a specific servers group. For example: P2P , Use `docker run --rm bubuntux/nordvpn sh -c "nordvpnd & sleep 1 && nordvpn groups"` to get the full list.
  - --group value, -g value Specify a server group to connect to. For example: 'us -g p2p'
- `TECHNOLOGY` - Specify Technology to use:
  - OpenVPN - Traditional connection.
  - NordLynx - NordVpn wireguard implementation (3x-5x times faster). NOTE: Requires `--cap-add=SYS_MODULE` and `--sysctl net.ipv4.conf.all.rp_filter=2`
- `PROTOCOL` - TCP or UDP (only valid when using OpenVPN).
- `OBFUSCATE` - Enable or Disable. When enabled, this feature allows to bypass network traffic sensors which aim to detect usage of the protocol and log, throttle or block it (only valid when using OpenVpn).
- `CYBER_SEC` - Enable or Disable. When enabled, the CyberSec feature will automatically block suspicious websites so that no malware or other cyber threats can infect your device. Additionally, no flashy ads will come into your sight. More information on how it works: https://nordvpn.com/features/cybersec/.
- `DNS` - Can set up to 3 DNS servers. For example 1.1.1.1,8.8.8.8 or Disable, Setting DNS disables CyberSec.
- `WHITELIST` - List of domains that are gonna be accessible _outside_ vpn (IE rarbg.to,yts.am).
- `NETWORK` - CIDR networks (IE 192.168.1.0/24), add a route to allows replies once the VPN is up.
- `NETWORK6` - CIDR IPv6 networks (IE fe00:d34d:b33f::/64), add a route to allows replies once the VPN is up.
- `TZ` - Set a timezone (IE EST5EDT, America/Denver, [full list](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)).
- `GROUPID` - Set the GID for the vpn.
- `DEBUG` - Set to 'on' for troubleshooting (User and Pass would be log).
- `PORTS` - Semicolon delimited list of ports to whitelist for both UDP and TCP. For example `- PORTS=9091;9095`
- `HTTP_PROXY_PORT` - Set a port to enable Privoxy on. Disabled by default

# Supported Architectures

This image use [docker manifest for multi-platform awareness](https://github.com/docker/distribution/blob/master/docs/spec/manifest-v2-2.md#manifest-list), simply pulling `bubuntux/nordvpn` should retrieve the correct image for your arch, but you can also pull specific arch images via tags.

| Architecture |   Tag   |
| :----------: | :-----: |
|   x86/i686   |  i386   |
| Linux x86-64 |  amd64  |
| ARMv5 32-bit | armv5e  |
| ARMv7 32-bit | armv7hf |
| ARMv8 64-bit | aarch64 |

# Issues

If you have any problems with or questions about this image, please contact me through a [GitHub issue](https://github.com/bubuntux/nordvpn/issues).
