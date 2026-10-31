# Access your home LAN from a phone over WireGuard (server on a NAS)

Slovak version: [setup.md](setup.md)

Goal: a direct encrypted tunnel between a NAS (Debian 12) and a Samsung Galaxy
S25+ through which the phone can reach the LAN `192.168.99.0/24`. No third-party
coordination server, everything runs at your place. On the UniFi USG you only
need to forward one port.

The USG does not offer a VPN a phone can use (only L2TP/PPTP), so the VPN runs
on the NAS. The NAS must be reachable from the internet (port forward and a
public IP).

Values used (defaults in the scripts, they match the original server on the NAS):

| What | Value |
|------|-------|
| LAN | `192.168.99.0/24` (the script detects it from the NAS card, change it with `LAN=...`) |
| DNS for clients | `192.168.99.1` (the script detects the default gateway, change it with `DNS=...`) |
| NAS network card | `enp2s0` (the script detects it itself) |
| Tunnel IPv4 | `10.66.66.0/24` |
| Tunnel IPv6 | `fd42:42:42::/64` |
| NAS in the tunnel | `10.66.66.1`, `fd42:42:42::1` |
| Devices in the tunnel | `10.66.66.2`, `.3`, ... (and `fd42:42:42::2`, `::3`, ...) |
| Port | `59656/udp` |

## How it works

- The NAS is the WireGuard server and forwards traffic from the tunnel to the LAN.
- The phone connects to the public IP (or DDNS name) of your USG, and the USG
  forwards UDP `59656` to the NAS.
- When forwarding into the LAN, the NAS replaces the source address with its own
  (masquerade), so replies from LAN devices come back through the NAS. Routing on
  the USG does not change.
- The configuration is split into the server part (server key, port, network,
  forwarding), done by `regen-wg.sh`, and the part for one device (its keys, IP,
  QR code), done by `add-wg-client.sh`.

## 0. Prerequisites

Check that the USG really has a public IP. Compare the WAN IP in the UniFi
controller (Devices → USG → WAN) with the address shown at
<https://ifconfig.me>. If they differ, the ISP uses CGNAT and a port forward from
the internet will not work.

If you have a dynamic public IP, enable DDNS on the USG
(Settings → Services → Dynamic DNS) and use the DDNS name in the script.

## 1. Installation on the NAS

You can install the packages by hand, or `regen-wg.sh` offers to do it:

```bash
sudo apt update
sudo apt install wireguard iptables qrencode
```

The scripts are in the [`scripts/`](../scripts/) folder. Copy `regen-wg.sh` and
`add-wg-client.sh` to the NAS into one folder (they must stay together) and make
them executable:

```bash
chmod +x regen-wg.sh add-wg-client.sh
```

## 2. Setting up the server and the first device (scripts)

```bash
sudo ./regen-wg.sh
```

`regen-wg.sh`:

- Asks for the WAN name (public IP or DDNS name of the router). It is entered
  only once and saved to `/etc/wireguard/.endpoint`. On the next run it is
  offered as the default. You can also pass the WAN as an argument.
- If packages are missing (`wireguard`, `qrencode`, `iptables`), it offers to
  install them with apt.
- Backs up the old `wg0.conf` (`wg0.conf.bak.<date>`), generates a new server
  key, writes `wg0.conf` with only the server part (no clients) including the
  firewall rules (`PostUp`/`PostDown`: allows the UDP port, forwarding from and
  to `wg0`, and masquerade), enables IP forwarding (IPv4 and IPv6), and enables
  and starts the `wg-quick@wg0` service (it also starts after the NAS reboots).
- If **ufw** is active on the NAS, it allows the UDP port in it and makes sure
  `/etc/ufw/sysctl.conf` does not switch forwarding off. With nftables and
  `policy drop` it prints a warning that the rules must be added by hand.
- Checks the result (service running and starting at boot, port listening,
  forwarding, firewall rules) and prints `[OK]`/`[ERROR]`.
- Prints what is left to do on the USG by hand: port forward, a fixed IP for the
  NAS and DDNS. The script cannot set these, the USG cannot be configured from
  the NAS.
- Then it calls `add-wg-client.sh` itself to create the first device.
- **Discards all existing clients.** Add further devices directly with
  `add-wg-client.sh` (see below).
- Values can be overridden with variables, e.g.
  `WG_PORT=51820 sudo -E ./regen-wg.sh`: `WG_PORT`, `WG_NIC`, `SRV_V4`,
  `SRV_V6`.

With ufw active the script allows the port itself. By hand it would be (change
the number for a different port):

```bash
sudo ufw allow 59656/udp
```

### A device (`add-wg-client.sh`)

`regen-wg.sh` calls it for the first device, and after that you run it yourself:

```bash
sudo ./add-wg-client.sh
```

- Lists the existing clients and asks only for the device details:
  - the IP address in the tunnel (the first free one is suggested, entering just
    the last number is enough),
  - the device name (letters, digits, `_`, `-`),
  - whether the device can scan a QR code. If you answer `n`, the script does not
    print the QR code, copies the `.conf` file to the user's home folder and
    prints the download command (see [Windows 11](#windows-11-laptop-pc)).
- The WAN, port, subnet and server key are not asked, they are taken from
  `wg0.conf` and `/etc/wireguard/.endpoint`. You can override them with
  variables: `ENDPOINT=...` (different WAN, saved), `WG_PSK=...` (your own PSK),
  `LAN`, `DNS`, `KEEP_FILES=1` (does not ask about the QR code and works as if
  you answered `n`).
- Generates the keys and the PSK, adds the peer to `wg0.conf` (after a backup)
  and loads the change with `wg syncconf`, so the other devices stay connected.
- If the entered IP already exists, after confirmation it **regenerates the
  keys** and replaces the old `[Peer]` block. The original device stops working
  until you scan the new QR code on it.
- Creates `/etc/wireguard/clients/<name>.conf` and `<name>.png` (root only),
  prints the QR code in the terminal, and at the end securely deletes both files
  (`shred -u`). If you choose `q` at the window height check, the files stay,
  delete them by hand.

### QR code in the terminal

- The QR code is printed last and only when it fits the window. If not, the
  script prints the height it needs. Enlarge the window or reduce the font size
  (Ctrl and minus) and press Enter. `s` = print it anyway, `q` = do not print
  (the PNG stays saved).
- A tunnel name cannot be put into the QR code, the app asks for it on import.
  The script therefore shows it above the QR code.
- The QR code contains the device's private key. Close the terminal after
  scanning.

### Output samples

Illustrative console samples (not real screenshots, dates and names will
differ). `regen-wg.sh` followed by `add-wg-client.sh` for the first device:

```text
WAN name (public IP or DDNS name of the router): my-ddns.example.com
Card: enp2s0 | Port: 59656 | Endpoint: my-ddns.example.com:59656
Warning: the old keys and all clients are discarded, devices must be added again.
Continue? [y/N] y
Backup of the old configuration: /etc/wireguard/wg0.conf.bak.20261030-193000
Server check:
  [OK]     service wg-quick@wg0 is running
  [OK]     service starts at boot
  [OK]     UDP 59656 is listening
  [OK]     IPv4 forwarding is enabled
  [OK]     firewall: INPUT allows UDP 59656
  [OK]     firewall: masquerade through enp2s0

Server wg0 is ready (no devices yet).
Still to do manually on the router (the script cannot do it):
  1. Port forward: UDP 59656 from WAN to the NAS IP (192.168.99.10).
  2. DHCP reservation (fixed IP) for the NAS.
  3. DDNS if the router has a dynamic public IP; make sure the WAN IP is not behind CGNAT.

Press Enter to create the first device (the screen will be cleared)...

Existing clients:
  (none)

Device IP address in the tunnel [10.66.66.2] (the last number is enough):
Device name [device2]: SamsungS25
Can this device scan a QR code? [Y/n]:
WAN: my-ddns.example.com (saved in /etc/wireguard/.endpoint, to change: ENDPOINT=... sudo -E ./add-wg-client.sh)
Backup: /etc/wireguard/wg0.conf.bak.20261030-193005
Client 'SamsungS25' (10.66.66.2) is active on the server.
Files: /etc/wireguard/clients/SamsungS25.conf and /etc/wireguard/clients/SamsungS25.png (they contain the private key, root-only).
They are securely deleted at the end of the script (shred -u) unless you choose 'q'.
```

The QR code screen (after the screen is cleared):

```text
Scan in the WireGuard app (+ -> Scan from QR code), tunnel name: SamsungS25
<QR code>
Key files deleted (shred -u). The QR code stays on the terminal screen, close it after scanning.
```

Another device, which gets the free address `10.66.66.3`:

```text
Existing clients:
  10.66.66.2/32          SamsungS25

Device IP address in the tunnel [10.66.66.3] (the last number is enough):
Device name [device3]: Tablet
Can this device scan a QR code? [Y/n]:
```

Regenerating an existing device (the entered IP already exists):

```text
Device IP address in the tunnel [10.66.66.3] (the last number is enough): 2
The IP 10.66.66.2 is already used by 'SamsungS25'. The keys will be regenerated and the old client stops working.
Continue? [y/N] y
Device name [SamsungS25]:
Can this device scan a QR code? [Y/n]:
```

The terminal window is shorter than the QR code:

```text
The QR code needs 38 lines, the terminal window is shorter (24).
Enlarge the window or reduce the font size (Ctrl and minus), then press Enter.
's' = print it anyway, 'q' = do not print (the PNG is saved).
>
```

You can take real screenshots straight from the NAS terminal and paste them here.

## 3. Port forward on the USG

In the UniFi controller:
Settings → Routing & Firewall → Port Forwarding → Create New Port Forward Rule.

| Field | Value |
|-------|-------|
| Name | `wireguard` |
| From | Anywhere (WAN) |
| Port | `59656` |
| Forward IP | the NAS IP in the LAN (`192.168.99.x`) |
| Forward Port | `59656` |
| Protocol | UDP |

The NAS should have a fixed IP in the LAN (a DHCP reservation or a static
address), otherwise the forward stops working after its IP changes.

## 4. Setting up the phone

1. Install the **WireGuard** app from Google Play.
2. Tap **+** → **Scan from QR code** and scan the QR code from the NAS console.
3. Name the tunnel with the name the script showed above the QR code and switch
   it on.

In the configuration from the QR code only the LAN and the tunnel go through the
VPN (`AllowedIPs = 192.168.99.0/24, 10.66.66.0/24`), the rest of the internet
goes directly as usual (split tunnel). To send all traffic through the tunnel,
change `AllowedIPs` to `0.0.0.0/0, ::/0`.

## 5. Test and check

Turn Wi-Fi off on the phone (test on mobile data), switch the tunnel on and open
`http://192.168.99.x` of some device in the LAN in the browser.

On the NAS:

```bash
sudo wg show
```

The peer must show `latest handshake` a few seconds ago and `transfer` with
non-zero values.

## Using it on the phone

- **Quick on/off:** in the quick panel (pencil → add tile) add the WireGuard
  tile, one tap switches the last used tunnel on or off. The official app cannot
  create a home-screen shortcut for a specific tunnel. For the home screen use
  Tasker or MacroDroid through the "Allow remote control apps" option in the app
  (commands `SET_TUNNEL_UP` and `SET_TUNNEL_DOWN`).
- **At home on Wi-Fi (`192.168.99.0/24`):** with the tunnel on, LAN traffic goes
  through the tunnel, because the tunnel route takes priority over Wi-Fi. If the
  USG cannot do hairpin NAT (connecting to your own public IP from inside), the
  handshake fails and the LAN will not be reachable. So switch the tunnel off at
  home, or point the DDNS name to the NAS LAN IP in your home DNS.
- **Tunnel always on, but off at home:** the official app has no rules based on
  Wi-Fi. Tasker/MacroDroid (through "Allow remote control apps") or the
  third-party app WG Tunnel (auto-tunnel based on trusted Wi-Fi networks; check
  its features in the store, it has not been verified) can switch it off on the
  home Wi-Fi. Android allows only one VPN app at a time.
- **Always-on VPN:** Settings → Connections → More connection settings → VPN →
  WireGuard → Always-on VPN. Do not enable "Block connections without VPN",
  otherwise normal internet outside the tunnel stops working.

## Windows 11 (laptop, PC)

There is an official **WireGuard** app for Windows (download it from
<https://www.wireguard.com/install/>). A tunnel for a PC is created the same way
as for a phone: add the device with `add-wg-client.sh` (its own IP, e.g.
`10.66.66.3`, and a name). The Windows app cannot scan a QR code though, so you
need the `.conf` configuration file.

Other devices without a QR scanner (Linux, a router) are set up the same way.

1. On the NAS run the script and answer `n` to `Can this device scan a QR code?`.
   A short device name without spaces is better, the app names the tunnel after
   it.

   ```bash
   sudo ./add-wg-client.sh
   ```

2. The script copies `NAME.conf` to your home folder and prints the exact
   download command.
3. On Windows (PowerShell) run the printed command. It looks like this:

   ```powershell
   scp user@nas-ip:/home/user/NAME.conf .
   ```

4. In the WireGuard app click **Add Tunnel** (the arrow next to it) → **Import
   tunnel(s) from file**, choose `NAME.conf` and click **Activate**.
5. Delete the key files. On the NAS:

   ```bash
   sudo shred -u ~/NAME.conf /etc/wireguard/clients/NAME.conf /etc/wireguard/clients/NAME.png
   ```

   and on Windows delete the downloaded `NAME.conf` (the app stores the tunnel
   itself).

The behaviour at home in the LAN is the same as with the phone (see Using it on
the phone): with the tunnel on, LAN traffic goes through the tunnel, so switch
it off at home (**Deactivate**).

## Webmin module (optional)

To manage clients from a web interface there is a custom Webmin module in the
[`webmin/`](../webmin/) folder (client list, adding, regenerating, QR code in the
browser, `.conf` download, tunnel control) and also the initial server setup
(packages, firewall including ufw, forwarding, service, checks), that is, what
`regen-wg.sh` does. It works with the same `wg0.conf` as the scripts.
Installation and description are in
[webmin/readme.md](../webmin/readme.md) (with screenshots; in Slovak:
[webmin/citajma.md](../webmin/citajma.md)). On a live Webmin the module
installation, the server setup, the server overview, the installation status,
adding a client including its actual connection, and deleting a client are
verified. Editing the server settings and the uninstall are verified only in a
simulated environment.

## Adding another device

Run `add-wg-client.sh` and enter the IP and the device name (see above). The
other devices stay connected. The same IP means regenerating the keys of the
existing device.

To disconnect a device, delete its `### Client ...` / `[Peer]` block from
`/etc/wireguard/wg0.conf` and load the change:

```bash
sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'
```

## Troubleshooting

| Problem | What to check |
|---------|---------------|
| No handshake | The port forward on the USG (UDP 59656 to the right NAS IP), the public IP/DDNS in `Endpoint`, CGNAT (step 0). Is the NAS listening? `ss -ulnp \| grep 59656`. |
| Handshake works, but the LAN is not reachable | `sysctl net.ipv4.ip_forward` must return `1`. `PostUp` must contain the right card name (`enp2s0`). `AllowedIPs` on the phone must contain `192.168.99.0/24`. |
| The tunnel is not running after a NAS reboot | `sudo systemctl enable --now wg-quick@wg0`, status with `systemctl status wg-quick@wg0`. |
| `iptables: command not found` | `sudo apt install iptables`. |
| Error in `PostUp` | Try `sudo wg-quick up wg0` by hand and read the output. |
| The QR code is not shown completely | Enlarge the window or reduce the font size (Ctrl and minus), see the QR code in the console. |
| The WAN/DDNS changed | Run `ENDPOINT=new-address sudo -E ./add-wg-client.sh` (it is saved). Existing devices must be set up again (regenerate the IP). |
| It does not work after switching on another VPN | Android allows only one VPN at a time. Switch off the other VPN apps. |
| The phone is on the home Wi-Fi | The tunnel is not needed, the LAN is directly reachable. Hairpin NAT on the USG may also cause problems with an `Endpoint` on the public IP. |

## Manual procedure (alternative to the scripts)

If you do not want the scripts, do this on the NAS as root.

IP forwarding:

```bash
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

The name of the network card towards the LAN (the `dev` column, here `enp2s0`):

```bash
ip route show default
```

Keys (do not paste them anywhere, not into chat or e-mail; if a key leaks,
generate it again and replace it on both sides):

```bash
cd /etc/wireguard
sudo sh -c 'umask 077; wg genkey | tee server.key | wg pubkey > server.pub'
sudo sh -c 'umask 077; wg genkey | tee phone.key | wg pubkey > phone.pub'
sudo sh -c 'umask 077; wg genpsk > phone.psk'
```

Server, the file `/etc/wireguard/wg0.conf` (replace `<SERVER_KEY>`, `<PHONE_PUB>`,
`<PHONE_PSK>` with the contents of the files `server.key`, `phone.pub`,
`phone.psk`):

```ini
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 59656
PrivateKey = <SERVER_KEY>
PostUp = iptables -I INPUT -p udp --dport 59656 -j ACCEPT
PostUp = iptables -I FORWARD -i enp2s0 -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD -i wg0 -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o enp2s0 -j MASQUERADE
PostUp = ip6tables -I FORWARD -i wg0 -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -o enp2s0 -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport 59656 -j ACCEPT
PostDown = iptables -D FORWARD -i enp2s0 -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o enp2s0 -j MASQUERADE
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -t nat -D POSTROUTING -o enp2s0 -j MASQUERADE

### Client SamsungS25
[Peer]
PublicKey = <PHONE_PUB>
PresharedKey = <PHONE_PSK>
AllowedIPs = 10.66.66.2/32,fd42:42:42::2/128
```

Secure the file and start the tunnel (also after every reboot):

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

The phone, the file `phone.conf` (only temporarily, it contains the private key;
replace `<PHONE_KEY>`, `<SERVER_PUB>`, `<PHONE_PSK>` with the contents of
`phone.key`, `server.pub`, `phone.psk` and `<PUBLIC_IP_OR_DDNS>` with the address
of the USG):

```ini
[Interface]
PrivateKey = <PHONE_KEY>
Address = 10.66.66.2/32,fd42:42:42::2/128
DNS = 192.168.99.1

[Peer]
PublicKey = <SERVER_PUB>
PresharedKey = <PHONE_PSK>
Endpoint = <PUBLIC_IP_OR_DDNS>:59656
AllowedIPs = 192.168.99.0/24, 10.66.66.0/24
PersistentKeepalive = 25
```

`DNS` is optional (the USG address), drop it if you do not want to change DNS on
the phone.

The QR code in the NAS terminal and then deleting the key file:

```bash
sudo qrencode -t ansiutf8 -m 2 -l L < phone.conf
```

```bash
shred -u phone.conf
```

## Notes

- The phone does not support old L2TP/PPTP VPN profiles on the USG. PPTP is also
  insecure, I recommend deleting it (Settings → VPN → VPN Server).
