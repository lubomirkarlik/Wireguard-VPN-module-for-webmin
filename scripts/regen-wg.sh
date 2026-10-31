#!/usr/bin/env bash
# Regenerates the WireGuard server part on the NAS (keys, /etc/wireguard/wg0.conf without clients)
# and then calls add-wg-client.sh, which creates the first device (keys, config, QR code).
# Run on the NAS as root:  sudo ./regen-wg.sh [public_IP_or_DDNS_name]
# The WAN name is entered only once, saved to /etc/wireguard/.endpoint and reused by add-wg-client.sh.
# Other values can be overridden with environment variables, e.g. WG_PORT=51820 sudo -E ./regen-wg.sh
set -euo pipefail

ENDPOINT="${1:-${WG_ENDPOINT:-}}"
WG_IF="${WG_IF:-wg0}"
WG_PORT="${WG_PORT:-59656}"
WG_NIC="${WG_NIC:-$(ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
SRV_V4="${SRV_V4:-10.66.66.1/24}"
SRV_V6="${SRV_V6:-fd42:42:42::1/64}"
WG_DIR=/etc/wireguard
CONF="$WG_DIR/$WG_IF.conf"
ENDPOINT_FILE="$WG_DIR/.endpoint"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
[ -n "$WG_NIC" ] || { echo "Could not detect the network card, set WG_NIC=..." >&2; exit 1; }
[ -f "$HERE/add-wg-client.sh" ] || { echo "Missing $HERE/add-wg-client.sh." >&2; exit 1; }

# Packages: install whatever is missing
need_pkgs=()
command -v wg >/dev/null || need_pkgs+=(wireguard)
command -v qrencode >/dev/null || need_pkgs+=(qrencode)
command -v iptables >/dev/null && command -v ip6tables >/dev/null || need_pkgs+=(iptables)
if [ "${#need_pkgs[@]}" -gt 0 ]; then
  echo "Missing packages: ${need_pkgs[*]}"
  read -r -p "Install them with apt? [Y/n] " ans
  [ "$ans" != "n" ] && [ "$ans" != "N" ] || { echo "This cannot work without these packages." >&2; exit 1; }
  apt-get update -qq
  apt-get install -y "${need_pkgs[@]}"
fi

if [ -z "$ENDPOINT" ]; then
  default="$(cat "$ENDPOINT_FILE" 2>/dev/null || true)"
  if [ -n "$default" ]; then
    read -r -p "WAN name (public IP or DDNS name of the router) [$default]: " ENDPOINT
    ENDPOINT="${ENDPOINT:-$default}"
  else
    read -r -p "WAN name (public IP or DDNS name of the router): " ENDPOINT
  fi
fi
[ -n "$ENDPOINT" ] || { echo "The WAN name is required." >&2; exit 1; }

echo "Card: $WG_NIC | Port: $WG_PORT | Endpoint: $ENDPOINT:$WG_PORT"
echo "Warning: the old keys and all clients are discarded, devices must be added again."
read -r -p "Continue? [y/N] " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; exit 1; }

umask 077
mkdir -p "$WG_DIR"
printf '%s\n' "$ENDPOINT" > "$ENDPOINT_FILE"

if [ -f "$CONF" ]; then
  backup="$CONF.bak.$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONF" "$backup"
  echo "Backup of the old configuration: $backup"
fi

srv_key="$(wg genkey)"

cat > "$CONF" <<EOF
[Interface]
Address = $SRV_V4,$SRV_V6
ListenPort = $WG_PORT
PrivateKey = $srv_key
PostUp = iptables -I INPUT -p udp --dport $WG_PORT -j ACCEPT
PostUp = iptables -I FORWARD -i $WG_NIC -o $WG_IF -j ACCEPT
PostUp = iptables -I FORWARD -i $WG_IF -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o $WG_NIC -j MASQUERADE
PostUp = ip6tables -I FORWARD -i $WG_IF -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o $WG_NIC -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT
PostDown = iptables -D FORWARD -i $WG_NIC -o $WG_IF -j ACCEPT
PostDown = iptables -D FORWARD -i $WG_IF -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o $WG_NIC -j MASQUERADE
PostDown = ip6tables -D FORWARD -i $WG_IF -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o $WG_NIC -j MASQUERADE
EOF
chmod 600 "$CONF"

# Forwarding (idempotent)
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' > /etc/sysctl.d/99-wireguard.conf
sysctl -q -p /etc/sysctl.d/99-wireguard.conf

# Firewall on the NAS. The PostUp rules (iptables -I, at the very top) also work with ufw, but we
# allow the port in ufw separately and make sure its reload does not switch forwarding off.
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$WG_PORT/udp" comment 'WireGuard' >/dev/null
  echo "ufw: allowed UDP $WG_PORT"
  if [ -f /etc/ufw/sysctl.conf ] && grep -qE '^net/(ipv4/ip_forward|ipv6/conf/(default|all)/forwarding)=0' /etc/ufw/sysctl.conf; then
    sed -i -E 's#^(net/(ipv4/ip_forward|ipv6/conf/(default|all)/forwarding))=0#\1=1#' /etc/ufw/sysctl.conf
    echo "ufw: forwarding enabled in /etc/ufw/sysctl.conf"
  fi
elif command -v nft >/dev/null && nft list ruleset 2>/dev/null | grep -q 'policy drop'; then
  echo "Warning: nftables has rules with 'policy drop'. If the tunnel does not work, allow UDP $WG_PORT" \
       "and forwarding from/to $WG_IF manually."
fi

systemctl enable "wg-quick@$WG_IF" >/dev/null 2>&1 || true
systemctl restart "wg-quick@$WG_IF"

# Check that everything is running
fail=0
chk() {
  if eval "$2" >/dev/null 2>&1; then echo "  [OK]     $1"; else echo "  [ERROR]  $1"; fail=1; fi
}
echo "Server check:"
chk "service wg-quick@$WG_IF is running" "systemctl is-active --quiet wg-quick@$WG_IF"
chk "service starts at boot" "systemctl is-enabled --quiet wg-quick@$WG_IF"
chk "UDP $WG_PORT is listening" "ss -uln | grep -qE ':$WG_PORT[[:space:]]'"
chk "IPv4 forwarding is enabled" "[ \"\$(sysctl -n net.ipv4.ip_forward)\" = 1 ]"
chk "firewall: INPUT allows UDP $WG_PORT" "iptables -C INPUT -p udp --dport $WG_PORT -j ACCEPT"
chk "firewall: masquerade through $WG_NIC" "iptables -t nat -C POSTROUTING -o $WG_NIC -j MASQUERADE"
if [ "$fail" -ne 0 ]; then
  echo "Something failed, see: systemctl status wg-quick@$WG_IF --no-pager; journalctl -u wg-quick@$WG_IF"
  exit 1
fi

nas_ip="$(ip -4 -o addr show dev "$WG_NIC" scope global | awk '{print $4}' | head -1)"
echo
echo "Server $WG_IF is ready (no devices yet)."
echo "Still to do manually on the router (the script cannot do it):"
echo "  1. Port forward: UDP $WG_PORT from WAN to the NAS IP (${nas_ip%%/*})."
echo "  2. DHCP reservation (fixed IP) for the NAS."
echo "  3. DDNS if the router has a dynamic public IP; make sure the WAN IP is not behind CGNAT."
echo
read -r -p "Press Enter to create the first device (the screen will be cleared)... " _

# First device (name, IP; WAN and the rest are taken from the server).
exec bash "$HERE/add-wg-client.sh"
