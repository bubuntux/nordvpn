<p align="center">
    <a href="https://nordvpn.com/"><img src="https://github.com/bubuntux/nordvpn/raw/master/NordVpn_logo.png"/></a>
    <a href="https://github.com/bubuntux/nordvpn/blob/master/LICENSE"><img src="https://badgen.net/github/license/bubuntux/nordvpn?color=cyan"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://images.microbadger.com/badges/image/bubuntux/nordvpn.svg"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/pulls/bubuntux/nordvpn?icon=docker&label=pulls"/></a>
    <a href="https://cloud.docker.com/u/bubuntux/repository/docker/bubuntux/nordvpn"><img src="https://badgen.net/docker/stars/bubuntux/nordvpn?icon=docker&label=stars"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/forks/bubuntux/nordvpn?icon=github&label=forks"/></a>
    <a href="https://github.com/bubuntux/nordvpn"><img src="https://badgen.net/github/stars/bubuntux/nordvpn?icon=github&label=stars"/></a>
    <a href="https://cloud.docker.com/repository/docker/bubuntux/nordvpn/builds"><img src="https://badgen.net/github/status/bubuntux/nordvpn"/></a>
</p>

This is a NordVPN client docker container that use the recommended NordVPN servers. It makes routing containers' traffic through OpenVPN easy.

# Supported Architectures

This image use [docker manifest for multi-platform awareness](https://github.com/docker/distribution/blob/master/docs/spec/manifest-v2-2.md#manifest-list), simply pulling `bubuntux/nordvpn` should retrieve the correct image for your arch, but you can also pull specific arch images via tags.

| Architecture      | Tag | 
| :----:            | :---: | 
| Linux x86-64      | amd64-latest | 
| Linux x86/i686    | i386-latest |
| ARMv8 64-bit      | aarch64-latest | 
| ARMv7 32-bit      | armv7hf-latest | 

# How to use this image

This container was designed to be started first to provide a connection to other containers (using `--net=container:vpn`, see below *Starting an NordVPN client instance*).

**NOTE**: More than the basic privileges are needed for NordVPN. With docker 1.2 or newer you can use the `--cap-add=NET_ADMIN` and `--device /dev/net/tun` options. Earlier versions, or with fig, and you'll have to run it in privileged mode.

## Starting an NordVPN instance

    docker run -ti --cap-add=NET_ADMIN --device /dev/net/tun --name vpn \
                -e USER=user@email.com -e PASS='pas$word' \
                -e COUNTRY=country -e CATEGORY=category \
                -e PROTOCOL=protocol -d bubuntux/nordvpn

Once it's up other containers can be started using it's network connection:

    docker run -it --net=container:vpn -d some/docker-container

## Local Network access to services connecting to the internet through the VPN.

The environment variable NETWORK must be your local network that you would connect to the server running the docker containers on. Running the following on your docker host should give you the correct network: `ip route | awk '!/ (docker0|br-)/ && /src/ {print $1}'`

    docker run -ti --cap-add=NET_ADMIN --device /dev/net/tun --name vpn \
                -p 8080:80 -e NETWORK=192.168.1.0/24 \ 
                -e USER=user@email.com -e PASS='pas$word' -d bubuntux/nordvpn                

Now just create the second container _without_ the `-p` parameter, only inlcude the `--net=container:vpn`, the port should be declare in the vpn container.

    docker run -ti --rm --net=container:vpn -d bubuntux/riot-web

now the service provided by the second container would be available from the host machine (http://localhost:8080) or anywhere inside the local network (http://192.168.1.xxx:8080).

## docker-compose

```
version: "3"
services:
  vpn:
    image: bubuntux/nordvpn
    cap_add:
      - net_admin
    devices:
      - /dev/net/tun
    environment:
      - USER=user@email.com
      - PASS='pas$word'
      - COUNTRY=United_States
      - PROTOCOL=UDP
      - CATEGORY=P2P
      - NETWORK=192.168.1.0/24
      - OPENVPN_OPTS=--ping-restart 180
      - TZ=America/Denver
    ports:
      - 8080:80
    restart: unless-stopped
  
  web:
    image: nginx
    network_mode: service:vpn
```

## Reconnect
The container is as simple as it can be, in order to reconnect automatically when connection is lost add:
 - Env variable: OPENVPN_OPTS='--ping-restart 180'
 - Restart policy: unless-stopped or always 

# ENVIRONMENT VARIABLES

 * `USER`     - User for NordVPN account.
 * `PASS`     - Password for NordVPN account, surrounding the password in single quotes will prevent issues with special characters such as `$`.
 * `COUNTRY`  - Use servers from an specific country (IE United_States, Australia, NZ, Hong Kong, MX, [full list](https://nordvpn.com/servers/)).  
 * `CATEGORY` - Use servers from an specific category (IE Double_VPN, Standard VPN servers). Allowed categories are:
   * `Standard VPN servers` Get connected to ultra-fast VPN servers anywhere around the globe to change your IP address and protect your browsing activities.
   * `P2P` Choose from hundreds of servers optimized for P2P sharing. NordVPN has no bandwidth limits and doesn’t log any of your activity.
   * `Dedicated IP servers` Order a dedicated IP address, which can only be used by you and will not be shared with any other NordVPN users.
   * `Double VPN` Send your Internet traffic through two different VPN servers for double encryption. Recommended for the most security-focused.
   * `Onion Over VPN` For maximum online security and privacy, combine the benefits of NordVPN with the anonymizing powers of the Onion Router.
 * `PROTOCOL` - Specify OpenVPN protocol. Allowed protocols are:
   * `UDP`
   * `TCP`
 * `WHITELIST` - List of domains that are gonna be accessible _outside_ vpn (IE rarbg.to,yts.am).
 * `NETWORK`  - CIDR networks (IE 192.168.1.0/24), add a route to allows replies once the VPN is up.
 * `NETWORK6` - CIDR IPv6 networks (IE fe00:d34d:b33f::/64), add a route to allows replies once the VPN is up.
 * `OPENVPN_OPTS` - Used to pass extra parameters to openvpn [full list](https://openvpn.net/community-resources/reference-manual-for-openvpn-2-4/).
 * `TZ` - Set a timezone (IE EST5EDT, America/Denver, [full list](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)).
 * `GROUPID` - Set the GID for the vpn.
 * `NET_IFACE` - Network Interface to bind the vpn (Useful when combined with `--network host` to protect the entire host).

# Versions 
 * **2019.03.12**
    - Remove HEALTH_CHECK.
 * **2019.03.09**
    - Add WHITELIST variable.
    - Add NET_IFACE variable. 
 * **2019.03.03**
    - Fix docker-compose documentation [#21](https://github.com/bubuntux/nordvpn/issues/21).
    - Use UTC timezone for tags.
 * **2019.03.01** 
    - Add documentation on passwords with special characters, refactor to avoid issue [#20](https://github.com/bubuntux/nordvpn/issues/20) and override auth file when need it.
    - Fix issues with TCP protocol.
    - Fallback to a random config file.
    - Add OPENVPN_OPTS environment variable.
 * **2019.02.27** 
    - Use recommended service api.
    - Add multiple architectures.

# Issues

If you have any problems with or questions about this image, please contact me through a [GitHub issue](https://github.com/bubuntux/nordvpn/issues).
