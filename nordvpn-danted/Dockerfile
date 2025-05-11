# -----------------------------------------------------------------------------
# nordvpn-danted: SOCKS5-over-NordVPN container (OpenVPN-only, .ovpn REQUIRED)
# -----------------------------------------------------------------------------
FROM debian:bookworm-slim

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openvpn \
        dante-server \
        iproute2 \
        iptables \
        tini \
        openssl \
        ca-certificates; \
    apt-get clean; rm -rf /var/lib/apt/lists/*

COPY danted.conf /etc/danted.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 1080/tcp 1080/udp
ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/entrypoint.sh"]
