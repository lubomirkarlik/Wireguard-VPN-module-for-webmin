# WireGuard VPN module for Webmin

Slovak version: [citajma.md](citajma.md)

A Webmin module for installing and managing a WireGuard server on a NAS
(Debian 12). It does the same as the `regen-wg.sh` and `add-wg-client.sh`
scripts in [`../scripts/`](../scripts/) (initial server setup and client management) and
reads and writes the same `/etc/wireguard/wg0.conf` format, so the scripts and
the module can be used interchangeably.

This is not an official Webmin module (there is none), it is a custom module
written in Perl. Languages: English, Slovak, German, French, Spanish, Italian,
Brazilian Portuguese, Russian, Polish, Czech, Simplified Chinese and Japanese
(see Languages).

## What the module can do

- **Initial server setup** (the **Set up server** page, like `regen-wg.sh`):
  - installs missing packages (`wireguard`, `qrencode`, `iptables`) with apt,
  - generates the server key and writes `wg0.conf` with firewall rules
    (`PostUp`/`PostDown`: allows the UDP port, forwarding to and from `wg0`,
    masquerade); the old `wg0.conf` is backed up,
  - enables IP forwarding (IPv4 and IPv6) in `/etc/sysctl.d/99-wireguard.conf`,
  - if **ufw** is active, allows the UDP port in it and makes sure its
    `/etc/ufw/sysctl.conf` does not switch forwarding off (with nftables and
    `policy drop` it only shows a warning),
  - enables and starts the `wg-quick@wg0` service (it also starts after a
    reboot),
  - checks the result (service running and enabled at boot, port listening,
    forwarding, firewall rules) and shows `[OK]` or the errors step by step,
  - lists what is still left to do manually on the router (port forward, fixed
    IP for the NAS, DDNS).
- **Installation status** (the **Installation** page, also on the main page
  when the server is missing): whether the `wg` command and the `wireguard` and
  `wireguard-tools` packages are installed, whether the kernel supports
  WireGuard, whether `qrencode`, `iptables` and `ip6tables` are present,
  whether a configuration exists, whether the tunnel is running and starts at
  boot, and the state of `ufw`.
- **Package installation:** a button installs only the missing packages with
  apt.
- **Uninstall with safe cleanup** (see Uninstall).
- **Editing the server settings** (the **Edit server settings** page): the
  listening port, the server tunnel addresses (IPv4 and IPv6), the network card
  used for masquerade, and regenerating the server key (a new public key), see
  Editing the server settings.
- **Server overview:** tunnel state (running or stopped), start at boot,
  tunnel addresses, port, server public key.
- **Tunnel control:** start, stop, restart, enable or disable start at boot
  (`wg-quick@wg0`).
- **Client list:** name, tunnel addresses, time of the last handshake and the
  amount of data transferred (from `wg show`).
- **Adding a client:** a name and the last number of the IP address (the first
  free one is suggested). The module generates the keys and the PSK, adds the
  peer to `wg0.conf` and loads the change with `wg syncconf`, so the other
  clients stay connected.
- **QR code in the browser** and **`.conf` download** (for Windows/PC)
  immediately after a client is created.
- **Regenerating the keys** of an existing client (after confirmation) and
  **deleting** a client (after confirmation).
- **Public address (WAN):** entered on the main page, stored in
  `/etc/wireguard/.endpoint` and shared with the scripts.
- Entries in the Webmin Actions Log (creating, regenerating and deleting a
  client, tunnel control, WAN change).

## What the module does not do

- **It does not configure the router (UniFi USG).** The port forward, the fixed
  IP for the NAS and DDNS must be set manually in UniFi; the module only
  reminds you. It also cannot tell whether the router is behind CGNAT (compare
  the WAN IP in UniFi with <https://ifconfig.me>).
- **It does not store client configurations.** After changing the port, the
  tunnel addresses or the server key, every client must be set up again
  (regenerated, see Editing the server settings).
- **It does not store client private keys.** They are shown once on the page
  after the client is created and are not kept anywhere afterwards (the server
  only has the public key). If you lose them, regenerate the client keys.

## Requirements

- Webmin on Debian 12 (verified on Webmin 2.670, see Testing status).
- The packages `wireguard`, `qrencode` and `iptables`: the server setup
  installs them (the **Install missing packages** option), or install them
  manually.
- A server created by the module setup, by the `regen-wg.sh` script, or a
  `wg0.conf` in the same format (see Configuration format).
- Webmin must run as root (the default), because of `wg`, `systemctl`,
  `apt-get`, `ufw` and writing to `/etc/wireguard`.

## Installation

### Through Webmin (recommended)

1. Get `wireguard.wbm.gz`: download it from the repository's **Releases** page,
   or build it yourself with `./build.sh` (see Building the package). Copy it to
   the computer you open Webmin from.
2. Webmin → **Webmin Configuration** → **Webmin Modules** → **From uploaded
   file**, choose `wireguard.wbm.gz` and click **Install Module**.
3. The module appears in the **Networking** category as **WireGuard VPN**. If
   you do not see it, reload the page or use **Refresh Modules**.

   ![The WireGuard VPN entry in the Networking menu](docs/img/01-menu.png)

4. Give other Webmin users access through **Webmin Users** (the module can
   manage the VPN and read private keys, so give it only to trusted accounts).

### Manually

Copy the `wireguard/` folder to the NAS into the Webmin directory (on Debian
`/usr/share/webmin/`), set the permissions, and refresh the module list:

```bash
sudo cp -r wireguard /usr/share/webmin/
sudo chmod 755 /usr/share/webmin/wireguard/*.cgi
```

Then use **Refresh Modules** in Webmin. You can find the Webmin directory with
`grep ^root= /etc/webmin/miniserv.conf`.

## Configuration

Module main page → the gear icon (**Module Config**):

![Module Config](docs/img/10-module-config.png)

| Option | Default | Meaning |
|--------|---------|---------|
| WireGuard configuration directory | `/etc/wireguard` | Where `wg0.conf` and `.endpoint` are. |
| WireGuard interface name | `wg0` | The interface name. |
| Path to wg / wg-quick / qrencode | `wg`, `wg-quick`, `qrencode` | Paths to the commands. |
| LAN routed through the tunnel | `auto` | `AllowedIPs` in client configurations (besides the tunnel subnet). `auto` uses the subnet of the server's network card. |
| DNS server for clients | `auto` | `DNS` in client configurations. `auto` uses the default gateway of that card, None means no DNS. |
| Directory for backup archives created on uninstall | `/root` | Where the backup is stored on uninstall. |
| Sysctl file for IP forwarding | `/etc/sysctl.d/99-wireguard.conf` | Where the server setup writes forwarding. |
| ufw sysctl configuration file | `/etc/ufw/sysctl.conf` | The ufw file in which forwarding is enabled when ufw is active. |

The router's public address (WAN) is set directly on the main page, not in
Module Config. The defaults match the defaults of the scripts.

## Usage

### The main page

Server overview (interface, state, start at boot, addresses, port, public key)
and buttons for tunnel control, editing the server settings, and installation:

![Main page: server and buttons](docs/img/02-index-server.png)

Below that are the public address (WAN), the client list with the last
handshake time and the data transferred, and the form for adding a client. The
server public key and the WAN are covered in the pictures:

![Main page: WAN, clients and adding a client](docs/img/03-index-clients.png)

### Steps

0. **First server setup.** If the server does not exist yet, the main page
   offers the **Set up server** button. Fill in the WAN (public IP or DDNS name
   of the router), the UDP port (default `59656`), the network card to the LAN
   (detected automatically), the server tunnel addresses (`10.66.66.1/24`,
   optionally IPv6 `fd42:42:42::1/64`), and the options to install packages
   and configure the firewall, then click **Set up server**. The page shows the
   progress and the checks step by step. At the end it lists what is still to
   be done on the router (port forward, fixed IP, DDNS). If a server already
   exists, setting up again discards all clients and asks for confirmation. The
   input is validated strictly, because it ends up in `PostUp` commands that
   run as root.

   ![The server setup form](docs/img/07-setup-server.png)

1. **Check the WAN** on the main page (it is filled in after the server setup).
2. In the **Add client** section enter the device name (letters, digits, `_`,
   `-`) and the last number of the IP (`10.66.66.` + number, 2 to 254, the
   first free one by default) and click **Create client**.
3. On the result page scan the QR code in the WireGuard app on the phone
   (**+** → **Scan from QR code**), or for Windows/PC click **Download
   configuration file** and import the file into the WireGuard app.
4. Then close the page. The private key is not stored anywhere.

   ![The page after a client is created (the QR code and the keys are covered in the picture)](docs/img/08-client-created.png)

5. If the IP is already used by another client, the module warns that
   regenerating invalidates the old client and asks for confirmation. The same
   name for two different IPs is rejected.

If the tunnel is not running, the change is written to `wg0.conf` and the
client becomes active when the tunnel starts. If it is running, the change is
loaded immediately and the other clients stay connected.

**Deleting a client:** click **Delete** in the client list. The module shows a
confirmation with the client name and addresses and, after confirmation,
removes it from `wg0.conf` and from the running tunnel. The other clients stay
connected.

![Delete client confirmation](docs/img/09-delete-client.png)

**Regenerating keys:** **Regenerate keys** opens a form with the name and IP
filled in. After you submit it, the module warns that the original device will
stop working and, after confirmation, creates new keys and a QR code.

## Editing the server settings

Main page → **Edit server settings**. The form is filled in with the current
values from `wg0.conf` (the public key is covered in the picture):

![Edit server settings](docs/img/06-edit-server.png)

| Option | What the module does |
|--------|----------------------|
| Listening port | Changes `ListenPort` and the port number in the `PostUp`/`PostDown` rules. In ufw (if active) it removes the old rule and adds the new one. |
| Server tunnel address (IPv4/IPv6) | Changes `Address`. If the subnet changes, it **also moves all clients** to the new subnet (same last number, for example `10.66.66.12` to `10.77.77.12`). IPv6 can be removed by leaving the field empty. |
| Network card | Replaces the card name in the rules (`FORWARD`, `MASQUERADE`). |
| Generate a new server key | Creates a new private key, and so a new server public key. |

Behaviour:

- A backup `wg0.conf.bak.<date-time>` is always created before saving.
- A running tunnel is restarted so that the new rules and addresses apply.
- The server address must not end with a number already used by a client.
- **Client configurations are not stored.** After changing the port, the
  addresses or the key, the existing clients stop working until you regenerate
  each one (a new `Endpoint`, `Address` or server key on the client). The
  module therefore shows the list of changes and asks for confirmation before
  the change, and lists links to regenerate each client after it.
- The port also changes on the router: after changing the port, update the
  port forward in UniFi to the new port.

## Uninstall

Main page → **Installation**. The upper part shows the installation status (the
`wg` command, packages, kernel, `qrencode`, `iptables`, configuration, tunnel,
`ufw`):

![Installation status](docs/img/04-install-status.png)

In the **Uninstall** section choose what to remove, and type the interface name
(`wg0`) to confirm:

![Uninstalling WireGuard](docs/img/05-uninstall.png)

The module performs these steps in this order:

1. **Backup** (optional, on by default): the whole configuration directory as
   `wireguard-backup-<date-time>.tar.gz` (in `/root` by default, mode `600`).
   If the backup fails, nothing is deleted.
2. **Stop and disable** the `wg-quick@wg0` service (`PostDown` removes the
   iptables rules) and, if needed, remove the interface.
3. **The ufw rule** for the UDP port (optional).
4. **The forwarding file** `/etc/sysctl.d/99-wireguard.conf` (optional). The
   running forwarding is not changed because other services may need it, and
   the change to `/etc/ufw/sysctl.conf` made by the server setup is not
   reverted.
5. **Configuration files** (optional): only `wg0.conf`, its backups
   `wg0.conf.bak.*`, `.endpoint` and the files in `clients/` are deleted.
   Private keys are overwritten (`shred`) before deleting. The `/etc/wireguard`
   directory is removed only if it is empty afterwards; otherwise it stays
   (with a warning) and other files are not touched.
6. **Packages** (optional, off by default): `apt-get remove --purge wireguard
   wireguard-tools`. `qrencode` and `iptables` stay installed.

Protection against mistakes: the module refuses to clean up a directory that is
not an absolute path with at least two components (for example
`/etc/wireguard`), and never deletes directories recursively.

## Configuration format

The module recognizes clients by the format the scripts create. Keep it when
editing `wg0.conf` by hand:

```ini
[Interface]
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = 59656
PrivateKey = ...
PostUp = ...

### Client SamsungS25
[Peer]
PublicKey = ...
PresharedKey = ...
AllowedIPs = 10.66.66.2/32,fd42:42:42::2/128
```

- Blocks are separated by an empty line.
- The client name is in the comment `### Client <name>` immediately before
  `[Peer]`.
- The first `AllowedIPs` entry is the client's IPv4 address (`/32`) and
  determines its ordinal number.
- `[Interface]` must contain `Address` (IPv4, optionally IPv6), `ListenPort`
  and `PrivateKey`.

On every change the module creates a backup `wg0.conf.bak.<date-time>` (mode
`600`), the same as the scripts. Old backups are not deleted, remove them
manually.

## Security

- The page shown after a client is created contains the **client's private
  key** (QR code, download link and text). Use Webmin only over **HTTPS** and
  close the page after scanning. The key is not stored, but it stays in the
  browser history of the displayed page until you close it. The QR code is
  created through a `data:` URI, so it is not written to the server as a file.
- Temporary files used to create the QR code (`qrencode` reads the
  configuration from a file) are created in the Webmin directory with mode
  `600` and deleted right after use.
- The module runs with the rights of Webmin (root). Whoever has access to the
  module can add and delete VPN clients, stop the tunnel, install packages
  (`apt-get`), and change the firewall rules and `wg0.conf` (including the
  `PostUp` commands, which root runs). Restrict access through **Webmin Users**.
- Values from the server setup form (WAN, port, card, addresses) are validated
  strictly before they are written to `wg0.conf`, so that arbitrary commands
  cannot get into `PostUp`. The same validation applies when editing the server
  settings.
- The backup created on uninstall contains private keys (the server's and the
  clients', if you have them stored). It has mode `600` and belongs to root.
  Once you have checked that you do not need it, delete it securely
  (`shred -u`). Uninstall requires typing the interface name so that it is not
  started by accident.
- If someone gains access to Webmin, they also get the keys of new clients.
  Protect Webmin with a strong password and 2FA.

## Testing status

### On a live server

Environment: Webmin 2.670 with the Authentic 26.70 theme on Debian 12 (kernel
6.1), an existing `wg0` server created by an external script with one client.

Verified:

- **Installing the module** from `wireguard.wbm.gz` through Webmin Modules (the
  module was placed in **Networking**, `/usr/share/webmin/wireguard`).
- **The main page** read the existing server correctly: state, start at boot,
  addresses, port, public key, and the client with the last handshake time and
  the data transferred.
- **Installation:** all checks were correct (the `wg` command, packages, kernel,
  `qrencode`, `iptables`, configuration, tunnel running and enabled at boot,
  `ufw` not installed).
- **Set up server:** the server setup was run on a live server and works.
- **Edit server settings and Module Config:** the forms were displayed and
  filled in with the correct values (display only, nothing was saved or
  submitted).
- **Adding a client** (a test client on a free IP): the module created the
  client, showed the QR code, the configuration and the download link, and the
  client appeared in the list. A client created by the module also connected
  for real.
- **Deleting a client:** confirmation and removal of the test client. The
  original client stayed in the list and its handshake did not change, so the
  change did not interrupt it.

**Not tested** on the live server: saving a change to the server settings
(port, addresses, card, key), regenerating keys, uninstalling, installing
packages, the Start/Stop/Restart buttons, and `ufw` (not installed).

A note about Webmin: the module pages cannot be opened by a direct link, Webmin
shows a "Security Warning" (referer check). Open the module by clicking through
the menu. Do not change the `referers_none` security setting because of this.

### In a simulated environment

The configuration handling was tested in Perl on Windows with stand-in
`wg` and `qrencode` commands:

- reading and writing `wg0.conf`, adding, regenerating and deleting a client,
  input validation, backups, QR in base64 format,
- server setup with stand-in `systemctl`, `sysctl`, `ss`, `iptables`, `ufw`,
  `apt-get` and `ip` commands: writing `wg0.conf` with `PostUp`/`PostDown`,
  `.endpoint`, the sysctl file, the ufw sysctl change, the `ufw allow` call,
  enabling and starting the service, the checks, installing missing packages,
  rejecting unsafe input (for example `;` or `$(...)` in the WAN, the card or
  the port),
- installation status, installing packages, uninstall (backup, stopping the
  service, ufw, sysctl, deleting only own files, keeping foreign files and the
  directory, removing an empty directory, refusing an unsafe path such as
  `/etc` or `/etc/../x`, stopping when the backup fails),
- server editing: changing the port, the addresses (including moving clients
  to a new subnet and removing IPv6), the card and the key, rejecting an address
  that a client already uses, the ufw calls and the service restart,
- the syntax of all `.cgi`/`.pl` files (`perl -c`) and a check that all text
  keys exist in every language file with the same placeholders (`$1`, `$2`).

When you first use the untested parts on your own server, verify the result
(`sudo wg show`, the `[OK]` checks after the server setup) and make a backup of
`/etc/wireguard` before the change.

If something does not work, look for the error in **Webmin → Webmin Actions
Log** and in `/var/webmin/miniserv.error`.

## Troubleshooting

| Problem | What to check |
|---------|---------------|
| "Security Warning" when opening a page | Webmin blocks direct links (referer check). Open the module by clicking through the menu **Networking → WireGuard VPN**. |
| The module does not appear | Use **Refresh Modules**, check the user's rights, and add the module in Webmin Users. |
| "The WireGuard command was not found" | `apt install wireguard qrencode`, or set the path in Module Config. |
| "The configuration file does not exist" | Click **Set up server**, or set the correct directory and interface in Module Config. |
| The server setup fails on packages | Check `apt-get update` on the NAS, or install the packages manually and repeat the setup. |
| A `[ERROR]` check after the setup | Look at `systemctl status wg-quick@wg0` and `journalctl -u wg-quick@wg0`; most often the port is taken or `iptables` is missing. |
| "The configuration is not valid" | `[Interface]` must have `Address` (IPv4), `ListenPort` and `PrivateKey`. |
| "The public address (WAN) is not set" | Fill in the WAN on the module main page. |
| The QR code is not shown | Check `qrencode`, use the download link or the configuration text. |
| The change was saved but loading it failed | See the message on the page. Restart the tunnel with the **Restart tunnel** button. |
| The client does not connect | The same checks as in [setup.en.md](../docs/setup.en.md) (port forward on the router, CGNAT, forwarding). |

## Removing the module from Webmin

(This removes only the module, not WireGuard. Uninstall WireGuard in the
module, see Uninstall above.)

Webmin → **Webmin Configuration** → **Webmin Modules** → **Delete** and choose
the module **WireGuard VPN**. The WireGuard configuration (`/etc/wireguard`) is
left untouched. A manually installed module is removed like this:

```bash
sudo rm -rf /usr/share/webmin/wireguard
```

## Folder contents

| File | Purpose |
|------|---------|
| `build.sh` | Builds the installation package `wireguard.wbm.gz` from the `wireguard/` folder (the package itself is not in git, publish it as a Release). |
| `wireguard/module.info` | Module name, category and description. |
| `wireguard/config`, `config.info`, `config.info.<lang>` | Default settings and their descriptions. |
| `wireguard/wireguard-lib.pl` | Shared functions: reading and writing `wg0.conf`, key generation, QR, tunnel control. |
| `wireguard/index.cgi` | Main page: server, WAN, clients, adding a client. |
| `wireguard/install.cgi` | Installation status, package installation and the uninstall form. |
| `wireguard/install_pkgs.cgi` | Installing missing packages. |
| `wireguard/uninstall.cgi` | Uninstall with cleanup and a list of the steps. |
| `wireguard/edit_server.cgi`, `save_server.cgi` | Editing the port, addresses, card and server key, with confirmation. |
| `wireguard/setup.cgi` | The initial server setup form. |
| `wireguard/setup_server.cgi` | Performing the server setup, confirming an overwrite, listing the steps and checks. |
| `wireguard/add_client.cgi` | Form for adding and regenerating a client. |
| `wireguard/save_client.cgi` | Creating a client, confirming regeneration, showing the QR code. |
| `wireguard/delete_client.cgi` | Deleting a client with confirmation. |
| `wireguard/service.cgi` | Start, stop, restart, start at boot. |
| `wireguard/save_endpoint.cgi` | Saving the public address (WAN). |
| `wireguard/log_parser.pl` | Readable entries in the Webmin Actions Log. |
| `wireguard/lang/<lang>` | Texts (12 languages, see Languages). |
| `wireguard/images/icon.gif` | The module icon. |
| `docs/img/*.png` | Cropped screenshots of the module pages used in this document (keys, QR code and WAN are covered). |

## Languages

The module follows the language selected in Webmin (**Webmin Configuration** →
**Language and Locale**). Available: `en` (English, the source texts), `sk`,
`de`, `fr`, `es`, `it`, `pt_BR`, `ru`, `pl`, `cs`, `zh_CN` and `ja`. Any other
language falls back to English.

Only `en` and `sk` were written by the author. The other translations are
machine-generated and have not been reviewed by native speakers, so wording
may be off in places. Corrections are welcome as pull requests.

To add a language: copy `wireguard/lang/en` to `wireguard/lang/<code>` (the
Webmin language code, for example `tr` or `nl`), translate the text after each
`=` and keep the keys and the `$1`, `$2` placeholders unchanged. Optionally add
`config.info.<code>` and a `longdesc_<code>` line in `module.info`.

## Building the package

After changing files in `wireguard/`, build the package again (in the `webmin`
folder):

```bash
./build.sh
```

The script sets the permissions and creates `wireguard.wbm.gz` next to it (the
file is in `.gitignore`; attach it to a GitHub Release).
