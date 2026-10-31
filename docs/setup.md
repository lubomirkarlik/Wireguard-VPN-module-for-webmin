# Prístup z mobilu do domácej LAN cez WireGuard (server na NAS)

English version: [setup.en.md](setup.en.md)

Cieľ: priamy šifrovaný tunel medzi NAS (Debian 12) a Samsung Galaxy S25+, cez
ktorý telefón vidí LAN `192.168.99.0/24`. Bez cudzieho koordinačného servera,
všetko beží len u teba. Na USG treba iba presmerovať jeden port.

USG neposkytuje VPN, ktorú by telefón vedel použiť (iba L2TP/PPTP), preto VPN
beží na NAS. NAS musí byť dostupný z internetu (port forward + verejná IP).

Použité hodnoty (predvolené v skriptoch, zhodujú sa s pôvodným serverom na NAS):

| Čo | Hodnota |
|----|---------|
| LAN | `192.168.99.0/24` (skript ju zistí sám z karty NAS, zmena cez `LAN=...`) |
| DNS pre klientov | `192.168.99.1` (skript zistí predvolenú bránu, zmena cez `DNS=...`) |
| Sieťová karta NAS | `enp2s0` (skript ju zistí sám) |
| Tunel IPv4 | `10.66.66.0/24` |
| Tunel IPv6 | `fd42:42:42::/64` |
| NAS v tuneli | `10.66.66.1`, `fd42:42:42::1` |
| Zariadenia v tuneli | `10.66.66.2`, `.3`, ... (a `fd42:42:42::2`, `::3`, ...) |
| Port | `59656/udp` |

## Ako to funguje

- NAS je WireGuard server a posiela prevádzku z tunela do LAN.
- Telefón sa pripojí na verejnú IP (alebo DDNS meno) tvojho USG, USG presmeruje
  UDP `59656` na NAS.
- NAS pri preposielaní do LAN mení zdrojovú adresu na svoju (masquerade), takže
  odpovede zo zariadení v LAN prídu späť cez NAS. Na USG sa nemení routing.
- Konfigurácia sa delí na serverovú časť (kľúč servera, port, sieť, forwarding),
  ktorú robí `regen-wg.sh`, a časť jedného zariadenia (jeho kľúče, IP, QR kód),
  ktorú robí `add-wg-client.sh`.

## 0. Predpoklady

Skontroluj, že USG má skutočne verejnú IP. Porovnaj WAN IP v UniFi kontroléri
(Devices → USG → WAN) s adresou na <https://ifconfig.me>. Ak sa líšia, ISP
používa CGNAT a port forward z internetu nebude fungovať.

Ak máš dynamickú verejnú IP, zapni DDNS na USG
(Settings → Services → Dynamic DNS) a pri skripte použi DDNS meno.

## 1. Inštalácia na NAS

Balíky môžeš doinštalovať ručne, alebo to ponúkne `regen-wg.sh` samo:

```bash
sudo apt update
sudo apt install wireguard iptables qrencode
```

Skripty sú v priečinku [`scripts/`](../scripts/). Skopíruj `regen-wg.sh` a
`add-wg-client.sh` na NAS do jedného priečinka (musia byť spolu) a sprístupni ich:

```bash
chmod +x regen-wg.sh add-wg-client.sh
```

## 2. Nastavenie servera a prvého zariadenia (skripty)

```bash
sudo ./regen-wg.sh
```

`regen-wg.sh`:

- Vypýta názov WAN (verejná IP alebo DDNS meno USG). Zadáva sa len raz, uloží
  sa do `/etc/wireguard/.endpoint`. Pri ďalšom spustení ho ponúkne ako
  predvolený. WAN môžeš dať aj ako argument.
- Ak chýbajú balíky (`wireguard`, `qrencode`, `iptables`), ponúkne ich
  doinštalovanie cez apt.
- Zálohuje starý `wg0.conf` (`wg0.conf.bak.<dátum>`), vygeneruje nový kľúč
  servera, zapíše `wg0.conf` len so serverovou časťou (bez klientov) vrátane
  firewall pravidiel (`PostUp`/`PostDown`: povolí UDP port, forward z/do
  `wg0` a masquerade), zapne IP forwarding (IPv4 aj IPv6) a
  zapne a spustí službu `wg-quick@wg0` (štart aj po reštarte NAS).
- Ak je na NAS aktívny **ufw**, povolí v ňom UDP port a postará sa, aby
  `/etc/ufw/sysctl.conf` nevypol forwarding. Pri nftables s `policy drop`
  vypíše upozornenie, že pravidlá treba doplniť ručne.
- Skontroluje výsledok (služba beží a štartuje pri štarte, port počúva,
  forwarding, pravidlá firewallu) a vypíše `[OK]`/`[ERROR]`.
- Vypíše, čo ostáva ručne na USG: port forward, pevná IP pre NAS a DDNS.
  Skript to nevie nastaviť, USG sa nedá nakonfigurovať z NAS.
- Potom sám zavolá `add-wg-client.sh` na vytvorenie prvého zariadenia.
- **Zahodí všetkých existujúcich klientov.** Ďalšie zariadenia pridávaj priamo
  cez `add-wg-client.sh` (pozri nižšie).
- Hodnoty sa dajú prepísať premennými, napr.
  `WG_PORT=51820 sudo -E ./regen-wg.sh`: `WG_PORT`, `WG_NIC`, `SRV_V4`,
  `SRV_V6`.

Pri aktívnom ufw skript port povolí sám. Ručne by to bolo (pre iný port zmeň
číslo):

```bash
sudo ufw allow 59656/udp
```

### Zariadenie (`add-wg-client.sh`)

Volá ho `regen-wg.sh` pre prvé zariadenie, a ďalej ho spúšťaš sám:

```bash
sudo ./add-wg-client.sh
```

- Vypíše existujúcich klientov a vypýta len údaje o zariadení:
  - IP adresu v tuneli (ponúkne prvú voľnú, stačí zadať posledné číslo),
  - názov zariadenia (písmená, čísla, `_`, `-`).
- WAN, port, podsieť a kľúč servera sa nepýtajú, preberú sa z `wg0.conf` a
  `/etc/wireguard/.endpoint`. Prepísať sa dajú premennými: `ENDPOINT=...`
  (iný WAN, uloží sa), `WG_PSK=...` (vlastný PSK), `LAN`, `DNS`,
  `KEEP_FILES=1` (súbory `.conf` a `.png` na konci nezmaže, treba pre Windows).
- Vygeneruje kľúče a PSK, pridá peera do `wg0.conf` (záloha predtým) a načíta
  zmenu cez `wg syncconf`, takže ostatné zariadenia ostanú pripojené.
- Ak zadaná IP už existuje, po potvrdení **pregeneruje kľúče** a nahradí starý
  blok `[Peer]`. Pôvodné zariadenie prestane fungovať, kým na ňom nenaskenuješ
  nový QR.
- Vytvorí `/etc/wireguard/clients/<názov>.conf` a `<názov>.png` (len root),
  vypíše QR v konzole a na konci oba súbory bezpečne zmaže (`shred -u`). Ak pri
  kontrole výšky okna zvolíš `q`, súbory ostanú, zmaž ich ručne.

### QR kód v konzole

- QR sa vypisuje až ako posledný a len keď sa zmestí do okna. Ak nie, skript
  vypíše potrebnú výšku. Zväčši okno alebo zmenši písmo (Ctrl a mínus) a stlač
  Enter. `s` = vypísať aj tak, `q` = nevypisovať (PNG ostane uložené).
- Názov tunela sa do QR vložiť nedá, aplikácia ho vypýta pri importe. Skript ho
  preto zobrazí nad QR kódom.
- QR obsahuje súkromný kľúč zariadenia. Po naskenovaní zavri terminál.

### Ukážky výstupu

Ilustračné ukážky konzoly (nie skutočné screenshoty, dátumy a názvy sa budú
líšiť). Výpisy skriptov sú len po anglicky. `regen-wg.sh` a následne `add-wg-client.sh` pre prvé zariadenie:

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
WAN: my-ddns.example.com (saved in /etc/wireguard/.endpoint, to change: ENDPOINT=... sudo -E ./add-wg-client.sh)
Backup: /etc/wireguard/wg0.conf.bak.20261030-193005
Client 'SamsungS25' (10.66.66.2) is active on the server.
Files: /etc/wireguard/clients/SamsungS25.conf and /etc/wireguard/clients/SamsungS25.png (they contain the private key, root-only).
They are securely deleted at the end of the script (shred -u) unless you choose 'q'.
```

Obrazovka s QR kódom (po vyčistení obrazovky):

```text
Scan in the WireGuard app (+ -> Scan from QR code), tunnel name: SamsungS25
<QR code>
Key files deleted (shred -u). The QR code stays on the terminal screen, close it after scanning.
```

Ďalšie zariadenie, ktoré dostane voľnú adresu `10.66.66.3`:

```text
Existing clients:
  10.66.66.2/32          SamsungS25

Device IP address in the tunnel [10.66.66.3] (the last number is enough):
Device name [device3]: Tablet
```

Pregenerovanie existujúceho zariadenia (zadaná IP už existuje):

```text
Device IP address in the tunnel [10.66.66.3] (the last number is enough): 2
The IP 10.66.66.2 is already used by 'SamsungS25'. The keys will be regenerated and the old client stops working.
Continue? [y/N] y
Device name [SamsungS25]:
```

Okno terminálu je nižšie ako QR kód:

```text
The QR code needs 38 lines, the terminal window is shorter (24).
Enlarge the window or reduce the font size (Ctrl and minus), then press Enter.
's' = print it anyway, 'q' = do not print (the PNG is saved).
>
```

Skutočné screenshoty si vieš urobiť priamo z terminálu NAS a vložiť ich sem.

## 3. Presmerovanie portu na USG

V UniFi kontroléri:
Settings → Routing & Firewall → Port Forwarding → Create New Port Forward Rule.

| Pole | Hodnota |
|------|---------|
| Name | `wireguard` |
| From | Anywhere (WAN) |
| Port | `59656` |
| Forward IP | IP NAS v LAN (`192.168.99.x`) |
| Forward Port | `59656` |
| Protocol | UDP |

NAS by mal mať v LAN pevnú IP (DHCP rezerváciu alebo statickú adresu), inak
presmerovanie po zmene IP prestane fungovať.

## 4. Nastavenie telefónu

1. Nainštaluj aplikáciu **WireGuard** z Google Play.
2. Klikni na **+** → **Scan from QR code** a naskenuj QR z konzoly NAS.
3. Pomenuj tunel názvom, ktorý skript zobrazil nad QR, a zapni ho.

V konfigurácii z QR ide cez VPN len LAN a tunel (`AllowedIPs = 192.168.99.0/24,
10.66.66.0/24`), ostatný internet ide normálne priamo (split tunnel). Pre
tunel cez všetku prevádzku zmeň `AllowedIPs` na `0.0.0.0/0, ::/0`.

## 5. Test a kontrola

Vypni Wi-Fi na telefóne (testuj na mobilných dátach), zapni tunel a otvor v
prehliadači `http://192.168.99.x` nejakého zariadenia v LAN.

Na NAS:

```bash
sudo wg show
```

Pri peerovi musí byť `latest handshake` pred pár sekundami a `transfer` s
nenulovými hodnotami.

## Používanie na telefóne

- **Rýchle zapnutie/vypnutie:** v rýchlom paneli (ceruzka → pridať dlaždicu)
  pridaj dlaždicu WireGuard, jedným ťuknutím zapne alebo vypne naposledy
  použitý tunel. Oficiálna aplikácia nevie vytvoriť odkaz na plochu pre
  konkrétny tunel. Plochu rieši Tasker alebo MacroDroid cez voľbu
  „Allow remote control apps“ v aplikácii (príkazy `SET_TUNNEL_UP` a
  `SET_TUNNEL_DOWN`).
- **Doma na Wi-Fi (`192.168.99.0/24`):** pri zapnutom tunele pôjde LAN
  prevádzka cez tunel, lebo trasa tunela má prednosť pred Wi-Fi. Ak USG nevie
  hairpin NAT (pripojenie na vlastnú verejnú IP zvnútra), handshake zlyhá a LAN
  nebude dostupná. Doma preto tunel vypni, alebo v domácom DNS nasmeruj DDNS
  meno na LAN IP NAS.
- **Trvalo zapnutý tunel, doma bez tunela:** oficiálna aplikácia nemá pravidlá
  podľa Wi-Fi. Automatické vypnutie na domácej Wi-Fi vie Tasker/MacroDroid
  (cez „Allow remote control apps“) alebo aplikácia tretej strany WG Tunnel
  (Auto-tunnel podľa dôveryhodných Wi-Fi; funkcie si over v obchode, nebola
  overená). Android povolí naraz len jednu VPN aplikáciu.
- **Always-on VPN:** Nastavenia → Pripojenia → Ďalšie nastavenia pripojenia →
  VPN → WireGuard → Always-on VPN. „Blokovať pripojenia bez VPN“ nezapínaj,
  inak prestane fungovať bežný internet mimo tunela.

## Windows 11 (notebook, PC)

Pre Windows existuje oficiálna aplikácia **WireGuard** (stiahni z
<https://www.wireguard.com/install/>). Tunel pre PC sa vytvára rovnako ako pre
telefón: zariadenie pridáš cez `add-wg-client.sh` (vlastná IP, napr.
`10.66.66.3`, a názov). Aplikácia pre Windows ale nevie naskenovať QR kód, preto
treba konfiguračný súbor `.conf`.

1. Na NAS spusti skript tak, aby súbory nezmazal:

   ```bash
   KEEP_FILES=1 sudo -E ./add-wg-client.sh
   ```

2. Skopíruj konfiguráciu do domovského priečinka (súbor v
   `/etc/wireguard/clients/` môže čítať len root). Nahraď `NAZOV` názvom
   zariadenia. Krátky názov bez medzier je lepší, aplikácia podľa neho
   pomenuje tunel.

   ```bash
   sudo install -o "$USER" -m 600 /etc/wireguard/clients/NAZOV.conf ~/NAZOV.conf
   ```

3. Na Windows (PowerShell) stiahni súbor. Nahraď `pouzivatel` a `ip-nas`:

   ```powershell
   scp pouzivatel@ip-nas:NAZOV.conf .
   ```

4. V aplikácii WireGuard klikni na **Add Tunnel** (šípka vedľa) → **Import
   tunnel(s) from file**, vyber `NAZOV.conf` a klikni na **Activate**.
5. Zmaž súbory s kľúčom. Na NAS:

   ```bash
   sudo shred -u ~/NAZOV.conf /etc/wireguard/clients/NAZOV.conf /etc/wireguard/clients/NAZOV.png
   ```

   a na Windows zmaž stiahnuté `NAZOV.conf` (aplikácia si tunel uloží sama).

Správanie doma v LAN je rovnaké ako pri telefóne (pozri Používanie na
telefóne): pri zapnutom tunele pôjde LAN prevádzka cez tunel, preto ho doma
vypni (**Deactivate**).

## Webmin modul (voliteľné)

Pre správu klientov z webového rozhrania je v priečinku [`webmin/`](../webmin/) vlastný modul
Webminu (zoznam klientov, pridanie, pregenerovanie, QR kód v prehliadači,
stiahnutie `.conf`, ovládanie tunela) aj prvotné nastavenie servera (balíky,
firewall vrátane ufw, forwarding, služba, kontroly), teda to, čo robí
`regen-wg.sh`. Pracuje s rovnakým `wg0.conf` ako skripty. Inštalácia a popis sú v
[webmin/citajma.md](../webmin/citajma.md) (so screenshotmi, anglicky:
[webmin/readme.md](../webmin/readme.md)). Na živom Webmine je
overená inštalácia modulu, nastavenie servera, prehľad servera, stav inštalácie,
pridanie klienta vrátane jeho skutočného pripojenia a zmazanie klienta. Zmena
nastavení servera a odinštalovanie sú overené len na simulovanom prostredí.

## Pridanie ďalšieho zariadenia

Spusti `add-wg-client.sh` a zadaj IP a názov zariadenia (pozri vyššie). Ostatné
zariadenia sa neodpoja. Rovnaká IP znamená pregenerovanie kľúčov existujúceho
zariadenia.

Zariadenie odpojíš tak, že zmažeš jeho blok `### Client ...` / `[Peer]` z
`/etc/wireguard/wg0.conf` a načítaš zmenu:

```bash
sudo bash -c 'wg syncconf wg0 <(wg-quick strip wg0)'
```

## Riešenie problémov

| Problém | Čo skontrolovať |
|---------|-----------------|
| Žiadny handshake | Port forward na USG (UDP 59656 na správnu IP NAS), verejná IP/DDNS v `Endpoint`, CGNAT (krok 0). Počúva NAS? `ss -ulnp \| grep 59656`. |
| Handshake je, ale LAN nie je dostupná | `sysctl net.ipv4.ip_forward` musí vrátiť `1`. V `PostUp` musí byť správny názov karty (`enp2s0`). `AllowedIPs` v telefóne musí obsahovať `192.168.99.0/24`. |
| Po reštarte NAS tunel nebeží | `sudo systemctl enable --now wg-quick@wg0`, stav cez `systemctl status wg-quick@wg0`. |
| `iptables: command not found` | `sudo apt install iptables`. |
| Chyba pri `PostUp` | Skús ručne `sudo wg-quick up wg0` a pozri výpis. |
| QR sa nezobrazí celý | Zväčši okno alebo zmenši písmo (Ctrl a mínus), pozri QR kód v konzole. |
| Zmenil sa WAN/DDNS | Spusti `ENDPOINT=nova-adresa sudo -E ./add-wg-client.sh` (uloží sa). Existujúce zariadenia treba nastaviť znova (pregenerovať IP). |
| Nefunguje po zapnutí inej VPN | Android povolí naraz len jednu VPN. Vypni ostatné VPN aplikácie. |
| Telefón je na domácej Wi-Fi | Tunel nie je potrebný, LAN je dostupná priamo. Prípadne môže hairpin NAT na USG robiť problémy s `Endpoint` na verejnú IP. |

## Ručný postup (alternatíva k skriptom)

Ak nechceš skripty, urob toto na NAS ako root.

IP forwarding:

```bash
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' | sudo tee /etc/sysctl.d/99-wireguard.conf
sudo sysctl -p /etc/sysctl.d/99-wireguard.conf
```

Názov sieťovej karty do LAN (stĺpec `dev`, tu `enp2s0`):

```bash
ip route show default
```

Kľúče (nikam ich nevkladaj, ani do chatu a e-mailu; ak unikne kľúč, vygeneruj
ho znova a vymeň na oboch stranách):

```bash
cd /etc/wireguard
sudo sh -c 'umask 077; wg genkey | tee server.key | wg pubkey > server.pub'
sudo sh -c 'umask 077; wg genkey | tee phone.key | wg pubkey > phone.pub'
sudo sh -c 'umask 077; wg genpsk > phone.psk'
```

Server, súbor `/etc/wireguard/wg0.conf` (nahraď `<SERVER_KEY>`, `<PHONE_PUB>`,
`<PHONE_PSK>` obsahom súborov `server.key`, `phone.pub`, `phone.psk`):

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

Zabezpeč súbor a spusti tunel (aj po každom reštarte):

```bash
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

Telefón, súbor `phone.conf` (len dočasne, obsahuje súkromný kľúč; nahraď
`<PHONE_KEY>`, `<SERVER_PUB>`, `<PHONE_PSK>` obsahom `phone.key`, `server.pub`,
`phone.psk` a `<VEREJNA_IP_ALEBO_DDNS>` adresou USG):

```ini
[Interface]
PrivateKey = <PHONE_KEY>
Address = 10.66.66.2/32,fd42:42:42::2/128
DNS = 192.168.99.1

[Peer]
PublicKey = <SERVER_PUB>
PresharedKey = <PHONE_PSK>
Endpoint = <VEREJNA_IP_ALEBO_DDNS>:59656
AllowedIPs = 192.168.99.0/24, 10.66.66.0/24
PersistentKeepalive = 25
```

`DNS` je voliteľné (adresa USG), vyhoď ho, ak nechceš meniť DNS v telefóne.

QR kód v termináli NAS a následné zmazanie súboru s kľúčom:

```bash
sudo qrencode -t ansiutf8 -m 2 -l L < phone.conf
```

```bash
shred -u phone.conf
```

## Poznámky

- Staré VPN profily L2TP/PPTP na USG telefón nepodporuje. PPTP je navyše
  nezabezpečený, odporúčam ho zmazať (Settings → VPN → VPN Server).
