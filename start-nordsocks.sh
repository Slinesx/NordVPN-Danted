#!/usr/bin/env bash
# start-nordsocks.sh  —  launch a SOCKS5-over-NordVPN container
#  • image default: nordvpn-danted:latest (override via IMAGE=…)
#  • requires: NORD_USERNAME, NORD_PASSWORD, and 1 arg = .ovpn path
set -Eeuo pipefail
trap 'ret=$?; printf "\n❌ ERROR (line %d): %s (exit %d)\n" \
       "$LINENO" "$BASH_COMMAND" "$ret" >&2' ERR

# 1. Arg check
[[ $# -eq 1 ]] || { echo "Usage: $0 /path/to/file.ovpn" >&2; exit 1; }
OVPN_FILE=$1
[[ -f $OVPN_FILE ]] || { echo "❌ .ovpn file not found: $OVPN_FILE" >&2; exit 1; }

# 2. Env check
: "${NORD_USERNAME:?Please export NORD_USERNAME}"
: "${NORD_PASSWORD:?Please export NORD_PASSWORD}"

# 3. Docker helper
DOCKER=docker
if ! docker info &>/dev/null; then
  echo "ℹ️  Using sudo for Docker (user not in docker group)"
  DOCKER='sudo docker'
  $DOCKER info &>/dev/null \
    || { echo "❌ sudo docker failed — is Docker running?" >&2; exit 1; }
fi

# 4. Image (override by setting IMAGE=… in your env)
IMAGE=${IMAGE:-nordvpn-danted:latest}

# 5. Container name & free port
BASE=$(basename "$OVPN_FILE" .ovpn)
SUFFIX=${BASE:0:2}
CONTAINER="nordsocks-${SUFFIX}"
$DOCKER rm -f "$CONTAINER" &>/dev/null || true

while :; do
  PORT=$(shuf -i 10000-65535 -n 1)
  $DOCKER ps --format '{{.Ports}}' | grep -q ":${PORT}->" || break
done

# 6. Proxy credentials
PROXY_USER=socksuser
# Generate a 16-character password from [A-Za-z0-9_-]
RAW_PASS=$(openssl rand -base64 24)
FILTERED_PASS=$(echo "$RAW_PASS" | tr -dc 'A-Za-z0-9_-')
PROXY_PASS=${FILTERED_PASS:0:16}

# 7. Run
echo "▶ Starting $CONTAINER (host port $PORT → 1080)"
$DOCKER run -d --name "$CONTAINER" \
  --cap-add=NET_ADMIN --device=/dev/net/tun \
  -p "${PORT}:1080/tcp" -p "${PORT}:1080/udp" \
  -e NORD_USERNAME="$NORD_USERNAME" \
  -e NORD_PASSWORD="$NORD_PASSWORD" \
  -e PROXY_USER="$PROXY_USER" \
  -e PROXY_PASS="$PROXY_PASS" \
  --mount type=bind,src="$(realpath "$OVPN_FILE")",dst=/nordvpn.ovpn,readonly \
  "$IMAGE"

# 8. Health check
sleep 2
if [[ "$($DOCKER inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
  echo "❌ Container died — showing last 40 log lines:"
  $DOCKER logs --tail 40 "$CONTAINER"
  exit 1
fi

# 9. Success
HOST_IP=$(hostname -I | awk '{print $1}')
cat <<EOF
-----------------------------------------------------------------
  ✅  SOCKS5 proxy is ready!

  Container : $CONTAINER
  Address   : ${HOST_IP}:${PORT}
  Username  : ${PROXY_USER}
  Password  : ${PROXY_PASS}
-----------------------------------------------------------------
EOF
