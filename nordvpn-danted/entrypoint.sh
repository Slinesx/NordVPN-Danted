#!/usr/bin/env bash
set -euo pipefail

# 1) Disable IPv6 inside container
for iface in /proc/sys/net/ipv6/conf/*; do
  echo 1 > "$iface/disable_ipv6" 2>/dev/null || true
done

# 2) Record original default route (before VPN) for policy-routing
orig=$(ip route show default | head -n1)
gw=$(awk '/via/ {print $3}' <<<"$orig")
dev=$(awk '/dev/ {print $5}' <<<"$orig")

# 3) Require exactly one .ovpn at /nordvpn.ovpn
if [[ ! -f /nordvpn.ovpn ]]; then
  echo "ERROR: you must mount your .ovpn file to /nordvpn.ovpn" >&2
  exit 1
fi

# 4) NordVPN credentials from env
: "${NORD_USERNAME?Need NORD_USERNAME}"
: "${NORD_PASSWORD?Need NORD_PASSWORD}"

# 5) Generate (or reuse) proxy user & password
PROXY_USER="${PROXY_USER:-socksuser}"
PROXY_PASS="${PROXY_PASS:-$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9_-' | head -c16)}"
useradd -M -s /usr/sbin/nologin "$PROXY_USER" 2>/dev/null || true
echo "$PROXY_USER:$PROXY_PASS" | chpasswd

echo "=== SOCKS5 credentials ==="
echo "  USER : $PROXY_USER"
echo "  PASS : $PROXY_PASS"
echo "=========================="

# 6) Start OpenVPN in background, ignore any IPv6 pushes
printf '%s\n%s\n' "$NORD_USERNAME" "$NORD_PASSWORD" > /run/openvpn-auth.txt
chmod 600 /run/openvpn-auth.txt
openvpn \
  --config /nordvpn.ovpn \
  --auth-user-pass /run/openvpn-auth.txt \
  --route-nopull --redirect-gateway def1 \
  --pull-filter ignore "route-ipv6" \
  --pull-filter ignore "ifconfig-ipv6" &

# wait for tun0
echo -n "Waiting for tun0 "
until ip link show tun0 &>/dev/null; do
  sleep 0.5
  echo -n "."
done
echo " up."

# 7) Policy-route Dante replies (port 1080) back via original NIC
echo "200 eth0table" >> /etc/iproute2/rt_tables
ip route add default via "$gw" dev "$dev" table eth0table
iptables -t mangle -A OUTPUT -p tcp --sport 1080 -j MARK --set-mark 1
iptables -t mangle -A OUTPUT -p udp --sport 1080 -j MARK --set-mark 1
ip rule add fwmark 1 table eth0table priority 100

# 8) Launch Dante in foreground
exec danted -f /etc/danted.conf
