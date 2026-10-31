# Vlastná WireGuard VPN pre domácu LAN

English version: [readme.md](readme.md)

Prístup do domácej siete z telefónu alebo notebooku cez WireGuard tunel, ktorý
beží na tvojom NAS (Debian 12). Bez cudzieho koordinačného servera, na routeri
stačí presmerovať jeden UDP port.

Projekt vznikol pre router UniFi USG (nemá VPN použiteľnú pre telefón), NAS s
Debianom 12 a Samsung Galaxy S25+, ale nič v ňom nie je viazané len na ne.
LAN a DNS pre klientov sa zistia zo sieťovej karty NAS (jej podsieť a predvolená
brána). Predvolené hodnoty: tunel `10.66.66.0/24` a `fd42:42:42::/64`, port
`59656/udp`. Všetko sa dá zmeniť.

## Obsah repozitára

| Cesta | Čo to je |
|-------|----------|
| [`scripts/regen-wg.sh`](scripts/regen-wg.sh) | Nastaví **server** WireGuard na NAS (balíky, `wg0.conf`, pravidlá firewallu, forwarding, služba), potom zavolá `add-wg-client.sh`. |
| [`scripts/add-wg-client.sh`](scripts/add-wg-client.sh) | Vytvorí alebo pregeneruje jedno **zariadenie**: kľúče, PSK, konfigurácia, QR kód (PNG aj v termináli). Súkromné súbory na konci zmaže cez `shred`. |
| [`webmin/`](webmin/citajma.md) | Webmin modul (natívny Perl), ktorý robí to isté z prehliadača, plus zistenie inštalácie, odinštalovanie s upratovaním a úpravu nastavení servera. K dispozícii v 12 jazykoch. |
| [`docs/setup.md`](docs/setup.md) | Celý postup krok za krokom (aj anglicky: [`docs/setup.en.md`](docs/setup.en.md)): presmerovanie portu na routeri, telefón a Windows, riešenie problémov, ručný postup. |

Výpisy skriptov sú len po anglicky.

## Rýchly štart

Na NAS ako root:

```bash
sudo apt install wireguard iptables qrencode
chmod +x scripts/*.sh
sudo ./scripts/regen-wg.sh        # server + prvé zariadenie, zobrazí QR kód
sudo ./scripts/add-wg-client.sh   # každé ďalšie zariadenie
```

Potom na routeri presmeruj `UDP 59656` na NAS, v aplikácii WireGuard naskenuj QR
kód a zapni tunel. Podrobnosti (kontrola CGNAT, DDNS, správanie na Androide a vo
Windows) sú v [`docs/setup.md`](docs/setup.md).

Ak chceš VPN spravovať cez Webmin, pozri [`webmin/citajma.md`](webmin/citajma.md).

## Bezpečnosť

- Skripty aj modul bežia ako root a hodnoty sa dostanú do riadkov `PostUp` a
  `PostDown` v `wg0.conf`, preto modul prísne kontroluje každý vstup. Skripty si
  pred spustením prečítaj.
- Súkromné kľúče zariadení sa zobrazia raz (QR kód alebo súbor) a neukladajú sa,
  server má len verejné kľúče.
- Nikdy nezverejňuj `wg0.conf`, `.conf` súbory zariadení ani kľúče. `.gitignore`
  blokuje bežné názvy, ale pred odoslaním na GitHub to skontroluj.

## Stav overenia

- Webmin modul je overený na živom Webmine 2.670 (Debian 12): inštalácia,
  nastavenie servera, prehľad servera, stav inštalácie, pridanie zariadenia
  vrátane jeho skutočného pripojenia a zmazanie zariadenia. Zmena nastavení a
  odinštalovanie sú overené len v simulovanom prostredí.
- Shell skripty sú skontrolované na syntax (`bash -n`). Pred nasadením na NAS ich
  skús celé spustiť na testovacom stroji.

## Licencia

[MIT](LICENSE)
