#!/usr/bin/env bash
# Zostaví inštalačný balík Webmin modulu: wireguard.wbm.gz (vedľa tohto skriptu).
# Build the Webmin module package: wireguard.wbm.gz (next to this script).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
[ -d wireguard ] || { echo "Missing ./wireguard directory." >&2; exit 1; }

chmod 755 wireguard/*.cgi wireguard/log_parser.pl wireguard/wireguard-lib.pl
chmod 644 wireguard/config.info.*
tar --owner=0 --group=0 -czf wireguard.wbm.gz wireguard
echo "Created $(pwd)/wireguard.wbm.gz ($(tar -tzf wireguard.wbm.gz | wc -l) entries)"
