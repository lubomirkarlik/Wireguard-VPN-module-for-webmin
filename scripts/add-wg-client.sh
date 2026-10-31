#!/usr/bin/env bash
# Adds (or regenerates) a WireGuard client on the NAS: keys, peer in wg0.conf,
# client configuration and QR code (in the terminal and as a PNG).
# Run on the NAS as root:  sudo ./add-wg-client.sh   (regen-wg.sh also calls it for the first device)
# The server (port, subnet, key) and the WAN are read from wg0.conf and /etc/wireguard/.endpoint, never asked again.
# The LAN (subnet of the server's network card) and the DNS (its default gateway) are detected.
# Optional: ENDPOINT=... (different WAN), WG_PSK=... (your own PSK), LAN=..., DNS=...,
#   KEEP_FILES=1 (do not delete the .conf and .png at the end, needed for Windows/PC)
# If the entered IP address already exists, the keys are regenerated and the old client stops working.
set -euo pipefail

WG_IF="${WG_IF:-wg0}"
WG_DIR=/etc/wireguard
CONF="$WG_DIR/$WG_IF.conf"
OUT_DIR="$WG_DIR/clients"
ENDPOINT_FILE="$WG_DIR/.endpoint"

[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
[ -f "$CONF" ] || { echo "Missing $CONF, run regen-wg.sh first." >&2; exit 1; }
for c in wg wg-quick qrencode awk; do
  command -v "$c" >/dev/null || { echo "Missing '$c' (apt install wireguard qrencode)." >&2; exit 1; }
done

# --- data from the server ---------------------------------------------------
addr_line="$(grep -m1 -E '^Address *=' "$CONF" | cut -d= -f2 | tr -d ' ')"
srv_v4="${addr_line%%,*}"
v4net="${srv_v4%.*}"
v6base=""
case "$addr_line" in *,*) srv_v6="${addr_line#*,}"; v6base="${srv_v6%%::*}" ;; esac
port="$(grep -m1 -E '^ListenPort *=' "$CONF" | cut -d= -f2 | tr -d ' ')"
srv_priv="$(grep -m1 -E '^PrivateKey *=' "$CONF" | cut -d= -f2- | tr -d ' ')"
[ -n "$v4net" ] && [ -n "$port" ] && [ -n "$srv_priv" ] || { echo "Invalid $CONF." >&2; exit 1; }
srv_pub="$(printf '%s' "$srv_priv" | wg pubkey)"

# --- LAN and DNS from the server's network card ------------------------------
nic="$(awk '/^PostUp/ && /POSTROUTING/ {for(i=1;i<NF;i++) if($i=="-o"){print $(i+1); exit}}' "$CONF")"
[ -n "$nic" ] || nic="$(ip -4 route show default | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
LAN="${LAN:-$(ip -4 route show dev "$nic" proto kernel scope link 2>/dev/null | awk '$1 ~ /\//{print $1; exit}' || true)}"
DNS="${DNS:-$(ip -4 route show default dev "$nic" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="via"){print $(i+1); exit}}' || true)}"
[ -n "$LAN" ] || { echo "Could not detect the LAN, set LAN=..." >&2; exit 1; }

list_peers() {
  awk 'BEGIN{RS="";FS="\n"}
    /\[Peer\]/ {
      n="?"; ip=""
      for(i=1;i<=NF;i++){
        if($i ~ /^### Client /){ n=substr($i,12) }
        if($i ~ /^AllowedIPs/){ v=$i; sub(/^AllowedIPs *= */,"",v); split(v,b,","); ip=b[1] }
      }
      print ip "\t" n
    }' "$CONF"
}

echo "Existing clients:"
peers="$(list_peers)"
if [ -n "$peers" ]; then printf '%s\n' "$peers" | awk -F'\t' '{printf "  %-22s %s\n", $1, $2}'; else echo "  (none)"; fi
echo

# --- inputs -----------------------------------------------------------------
used_octets="$(printf '%s\n' "$peers" | awk -F'[./\t]' -v net="$v4net" '$0 ~ "^"net"\\." {print $4}')"
suggest=""
for i in $(seq 2 254); do
  printf '%s\n' "$used_octets" | grep -qx "$i" || { suggest="$i"; break; }
done
[ -n "$suggest" ] || { echo "No free address in $v4net.0/24." >&2; exit 1; }

read -r -p "Device IP address in the tunnel [$v4net.$suggest] (the last number is enough): " ip_in
ip_in="${ip_in:-$v4net.$suggest}"
case "$ip_in" in
  *.*.*.*) ;;
  *[!0-9]*|'') echo "Invalid IP address." >&2; exit 1 ;;
  *) ip_in="$v4net.$ip_in" ;;
esac
n="${ip_in##*.}"
[ "${ip_in%.*}" = "$v4net" ] && [ "$n" -ge 2 ] && [ "$n" -le 254 ] \
  || { echo "The IP must be in $v4net.2 to $v4net.254." >&2; exit 1; }

existing_name="$(printf '%s\n' "$peers" | awk -F'\t' -v ip="$ip_in/32" '$1==ip {print $2; exit}')"
exists=0
if [ -n "$existing_name" ]; then
  exists=1
  echo "The IP $ip_in is already used by '$existing_name'. The keys will be regenerated and the old client stops working."
  read -r -p "Continue? [y/N] " ans
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "Cancelled."; exit 1; }
fi

default_name="${existing_name:-device$n}"
read -r -p "Device name [$default_name]: " name
name="${name:-$default_name}"
case "$name" in *[!A-Za-z0-9_-]*|'') echo "The name may contain only letters, digits, '_' and '-'." >&2; exit 1 ;; esac

# The WAN is entered only once (regen-wg.sh saves it); here it is just read.
endpoint="${ENDPOINT:-$(cat "$ENDPOINT_FILE" 2>/dev/null || true)}"
if [ -z "$endpoint" ]; then
  read -r -p "WAN name (public IP or DDNS name of the router): " endpoint
fi
[ -n "$endpoint" ] || { echo "The WAN name is required." >&2; exit 1; }
echo "WAN: $endpoint (saved in $ENDPOINT_FILE, to change: ENDPOINT=... sudo -E ./add-wg-client.sh)"
echo "LAN: $LAN, DNS: ${DNS:-none} (to change: LAN=... DNS=... sudo -E ./add-wg-client.sh)"

# --- generation -------------------------------------------------------------
umask 077
mkdir -p "$OUT_DIR"
printf '%s\n' "$endpoint" > "$ENDPOINT_FILE"

cli_key="$(wg genkey)"
cli_pub="$(printf '%s' "$cli_key" | wg pubkey)"
psk="${WG_PSK:-$(wg genpsk)}"

cli_allowed="$ip_in/32"
cli_addr="$ip_in/32"
if [ -n "$v6base" ]; then
  cli_allowed="$cli_allowed,$v6base::$n/128"
  cli_addr="$cli_addr,$v6base::$n/128"
fi

backup="$CONF.bak.$(date +%Y%m%d-%H%M%S)"
cp -p "$CONF" "$backup"
echo "Backup: $backup"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
if [ "$exists" -eq 1 ]; then
  awk -v key="AllowedIPs = $ip_in/32" 'BEGIN{RS="";ORS="\n\n"} !($0 ~ /\[Peer\]/ && index($0, key))' "$CONF" > "$tmp"
else
  cat "$CONF" > "$tmp"
fi
# remove trailing blank lines and append the new peer
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
cat >> "$tmp" <<EOF

### Client $name
[Peer]
PublicKey = $cli_pub
PresharedKey = $psk
AllowedIPs = $cli_allowed
EOF
cat "$tmp" > "$CONF"
chmod 600 "$CONF"

client_conf="$OUT_DIR/$name.conf"
cat > "$client_conf" <<EOF
[Interface]
PrivateKey = $cli_key
Address = $cli_addr
${DNS:+DNS = $DNS
}
[Peer]
PublicKey = $srv_pub
PresharedKey = $psk
Endpoint = $endpoint:$port
AllowedIPs = $LAN, $v4net.0/24
PersistentKeepalive = 25
EOF
chmod 600 "$client_conf"
qrencode -t png -l L -m 2 -s 6 -o "$OUT_DIR/$name.png" < "$client_conf"
chmod 600 "$OUT_DIR/$name.png"

# --- load the change without disconnecting the other clients ----------------
if ip link show "$WG_IF" >/dev/null 2>&1; then
  wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
else
  systemctl enable --now "wg-quick@$WG_IF"
fi
echo "Client '$name' ($ip_in) is active on the server."
echo "Files: $client_conf and $OUT_DIR/$name.png (they contain the private key, root-only)."
echo "They are securely deleted at the end of the script (shred -u) unless you choose 'q'."
echo

# --- QR code in the terminal (at the end, only when it fits the window) -----
qr="$(qrencode -t ansiutf8 -m 2 -l L < "$client_conf")"
need=$(( $(printf '%s\n' "$qr" | wc -l) + 3 ))
while [ "$(tput lines 2>/dev/null || echo 0)" -lt "$need" ]; do
  echo "The QR code needs $need lines, the terminal window is shorter ($(tput lines 2>/dev/null || echo '?'))."
  echo "Enlarge the window or reduce the font size (Ctrl and minus), then press Enter."
  echo "'s' = print it anyway, 'q' = do not print (the PNG is saved)."
  read -r -p "> " key
  case "$key" in
    q) exit 0 ;;
    s) break ;;
  esac
done

clear
echo "Scan in the WireGuard app (+ -> Scan from QR code), tunnel name: $name"
printf '%s\n' "$qr"

if [ "${KEEP_FILES:-0}" = "1" ]; then
  echo "KEEP_FILES=1: the files stayed in $OUT_DIR (they contain the private key). Delete them after use: shred -u $client_conf $OUT_DIR/$name.png"
else
  shred -u "$client_conf" "$OUT_DIR/$name.png"
  echo "Key files deleted (shred -u). The QR code stays on the terminal screen, close it after scanning."
fi
