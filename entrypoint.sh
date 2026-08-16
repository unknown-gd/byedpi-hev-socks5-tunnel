#!/bin/sh
set -eu

TUN="${TUN:-tun0}"
MTU="${MTU:-9000}"
IPV4="${IPV4:-198.18.0.1}"
IPV6="${IPV6:-fc00::1}"
MARK="${MARK:-438}"
SOCKS5_UDP_MODE="${SOCKS5_UDP_MODE:-udp}"
OTHER_ROUTE="${OTHER_ROUTE:-}"
LOG_LEVEL="${LOG_LEVEL:-warn}"

GATEWAY="${GATEWAY:-$(ip route | awk '/^default/ {print $3; exit}')}"
IFACE="${IFACE:-$(ip route | awk '/^default/ {print $5; exit}')}"

if [ -z "${GATEWAY:-}" ] || [ -z "${IFACE:-}" ]; then
  echo "ERROR: could not auto-detect default gateway/interface." >&2
  echo "       Current routes:" >&2
  ip route >&2 || true
  echo "       Set GATEWAY and IFACE explicitly, e.g. GATEWAY=192.168.1.1 IFACE=veth1" >&2
  exit 1
fi

config_file() {
  cat > /hs5t.yml << EOF
misc:
  log-level: '${LOG_LEVEL}'
tunnel:
  name: '${TUN}'
  mtu: ${MTU}
  ipv4: '${IPV4}'
  ipv6: '${IPV6}'
  post-up-script: '/route.sh'
socks5:
  address: '127.0.0.1'
  port: 1080
  udp: '${SOCKS5_UDP_MODE}'
  mark: ${MARK}
EOF
}

config_route() {
  {
    echo "#!/bin/sh"
    echo "set -e"

    # IPv4 uid 1000 exemption
    echo "ip rule add from all uidrange 1000-1000 lookup 110 pref 28000"
    echo "ip route flush table 110 || true"
    echo "ip route add default via ${GATEWAY} dev ${IFACE} metric 50 table 110"

    # IPv4 default routing through tunnel
    echo "ip route del default || true"
    echo "ip route add default via ${IPV4} dev ${TUN} metric 1"
    echo "ip route add default via ${GATEWAY} dev ${IFACE} metric 10"

    # IPv4 exclude local networks
    echo "ip route add 10.0.0.0/8 via ${GATEWAY} dev ${IFACE}"
    echo "ip route add 172.16.0.0/12 via ${GATEWAY} dev ${IFACE}"
    echo "ip route add 192.168.0.0/16 via ${GATEWAY} dev ${IFACE}"

    # IPv6 uid 1000 exemption
    echo "ip -6 rule add from all uidrange 1000-1000 lookup 110 pref 28000"
    echo "ip -6 route flush table 110 || true"
    echo "ip -6 route add default via ${GATEWAY} dev ${IFACE} metric 50 table 110"

    # IPv6 default routing through tunnel
    echo "ip -6 route del default || true"
    echo "ip -6 route add default via ${IPV6} dev ${TUN} metric 1"
    echo "ip -6 route add default via ${GATEWAY} dev ${IFACE} metric 10"

    # IPv6 exclude local networks
    echo "ip -6 route add fe80::/10 via ${GATEWAY} dev ${IFACE}"
    echo "ip -6 route add ::1/128 via ${GATEWAY} dev ${IFACE}"

    if [ -n "${OTHER_ROUTE}" ]; then
      echo "${OTHER_ROUTE}"
    fi

    echo "echo 1 > /success"
  } > /route.sh

  chmod +x /route.sh
}

run() {
  config_file
  config_route

  echo "ByeDPI v.$(ciadpi --version)"
  echo "hev-socks5-tunnel $(hev-socks5-tunnel --version | sed -n '2p')"

  hev-socks5-tunnel /hs5t.yml &
  TUNNEL_PID=$!

  # Give the tunnel a moment to come up and verify it didn't die immediately.
  sleep 1
  if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo "ERROR: hev-socks5-tunnel exited immediately, aborting." >&2
    exit 1
  fi

  # Run ciadpi in the foreground; safely pass through args without
  # word-splitting/injection risk (was: `su - ciadpi -c "ciadpi $*"`).
  su - ciadpi -s /bin/sh -c 'exec ciadpi "$@"' -- "$@"
  CIADPI_EXIT=$?

  # If the tunnel died in the background while ciadpi was running,
  # surface that rather than reporting a misleading clean exit.
  if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then
    echo "WARNING: hev-socks5-tunnel is no longer running." >&2
  fi

  exit "$CIADPI_EXIT"
}

run "$@"
