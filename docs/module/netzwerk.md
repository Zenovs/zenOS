# Netz · WLAN-Menü mit NetworkManager

zenOS hat oben rechts im System-Menü ein schlichtes WLAN-Menü: Netz wählen, verbinden, vergessen, WLAN aus. Es ist
nur eine Oberfläche für den NetworkManager von Ubuntu; Verbindungen, Passwörter und Rechte bleiben dort
(`MANIFEST.md`, «Was zenOS bewusst nicht ist»). Bis Oktober 2026 lief das Netz über netplan mit systemd-networkd,
ohne WLAN-Menü. Der Umstieg auf NetworkManager geschieht einmal und ausdrücklich mit `zen netzwerk umstellen`
und einem Neustart; ein neues Image stellt beim ersten Start selbst um.

## Was gebaut ist

| Teil | Datei | Aufgabe |
|---|---|---|
| Paket | `scripts/pakete/netzwerk.txt` | `network-manager`, `wpasupplicant` (bei NetworkManager nur empfohlen), `wireless-regdb`, `iw`, ohne Empfehlungen (also ohne Ubuntus Konnektivitätsprüfung, ModemManager, ppp, dnsmasq) |
| Installer | `scripts/module/35-netzwerk.sh` | Einheiten ablegen; vor dem Umstieg NetworkManager deaktivieren, danach aktiviert halten; im Image vorbereiten |
| Umsteller | `scripts/bin/zenos-netzwerk` (python3) | `status`, `plan`, `umstellen`, `zurueck`, `erststart` |
| Befehl | `scripts/zen.d/netzwerk.sh` | `zen netzwerk [status\|umstellen\|zurueck]`, zeigt den Plan und fragt nach |
| Prüfbericht | `scripts/doctor.d/40-netzwerk.sh` | Abschnitt «Netz» in `zen doctor` |
| WLAN-Land | `system/systemd/system/zenos-wlan-land.service` | `iw reg set ${LAND}` aus `/etc/xdg/zenos/wlan-land` (Ersatz für `netplan-regdom.service`) |
| wait-online | `system/systemd/system/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf` | überspringt `systemd-networkd-wait-online`, solange NetworkManager das Netz verwaltet |
| Erster Start | `system/systemd/system/zenos-netzwerk-erststart.service` | Image: nach cloud-init und vor NetworkManager umstellen (einmal) |
| WPA3 | `system/modprobe/zenos-brcmfmac.conf` | `options brcmfmac feature_disable=0x2082000` (siehe unten) |
| cloud-init | `system/cloud/99-zenos-netzwerk.cfg` | `network: {config: disabled}` |
| Oberfläche | `shell/leiste/WlanQuelle.qml`, `WlanAbschnitt.qml`, `WlanZeile.qml`, `WlanSymbol.qml`, `wlan.js` | WLAN im System-Menü, Signalstufe in der Leiste |
| Tests | `test/einheiten/netzwerk.test.py`, `test/einheiten/wlan.test.mjs` | Umsteller gegen netplan in einem Testordner; Logik des Menüs (node) |

## Umstieg: `zen netzwerk umstellen`

`zen update` (bzw. `install.sh`) installiert nur das Paket. Die `policy-rc.d` des Installers verhindert, dass
NetworkManager dabei startet; `35-netzwerk` deaktiviert ihn wieder (mit ihm `NetworkManager-wait-online`, über
`Also=`), damit der nächste Neustart genau wie vorher hochfährt. Läuft NetworkManager schon oder hat er Profile,
gehört er jemandem und bleibt, wie er ist.

`zen netzwerk umstellen` (fragt selbst nach sudo, braucht ein Terminal):

1. Nichts tun, wenn `/etc/netplan/90-zenos-netzwerk.yaml` schon da ist.
2. Die ganze netplan-Konfiguration lesen (`netplan get all`; netplan führt die Dateien selbst zusammen).
3. Ohne jede Änderung abbrechen, wenn etwas nicht sicher übernommen werden kann: andere Typen als `ethernets` und
   `wifis`, unbekannte Schlüssel, Unternehmens-WLAN (EAP), `key-management` ausser `psk` und `none`, mehrere Länder,
   NetworkManager oder `wpa_supplicant` fehlt (ohne ihn gäbe es danach kein WLAN).
4. Den Plan zeigen: übernommene WLANs (nur Namen), Kabel, Land, WPA3 im Treiber, Sicherung, Rückweg. Erst die
   Eingabe «umstellen» stellt um, alles andere bricht ab.
5. `90-zenos-netzwerk.yaml`: `renderer: NetworkManager` für alles, jede Kabel-Definition übernommen.
6. Jeder WLAN-Zugangspunkt wird ein eigenes Profil in `90-NM-<uuid>.yaml`, im Format, das NetworkManager selbst
   schreibt (eigene Definition `NM-<uuid>`, `match: {}`, Name = SSID). So löscht «Vergessen» im Menü genau dieses
   eine Netz. Hängen alle WLANs an einer Definition `wlan0` (so schreibt es der Imager), löscht NetworkManager beim
   Vergessen eines Netzes die ganze Definition: alle WLANs und das Land (im Container belegt).
7. Probe: die neuen Dateien allein in einem leeren Ordner mit `netplan generate --root-dir` erzeugen. Verlangt
   werden Exit 0, keine Fehlerzeile, ein Profil je Netz und Kabel und nichts für systemd-networkd.
8. Sicherung der bisherigen Dateien nach `/var/lib/zenos/netplan-vorher/<zeit>/` (0700) mit `zenos.json` (alte
   und neue Dateien, Land, was zusätzlich angelegt wurde).
9. Neue Dateien atomar schreiben (0600 root), erst dann die alten löschen.
10. Land nach `/etc/xdg/zenos/wlan-land`, `/etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg` (sonst schriebe cloud-init
    bei einer neuen Instanz wieder `50-cloud-init.yaml` mit `renderer: networkd`) und auf Raspberry Pis die
    WPA3-Option.
11. `NetworkManager`, `NetworkManager-wait-online` und `zenos-wlan-land` aktivieren, nicht starten. Kein
    `netplan apply`: Eine SSH-Verbindung über WLAN bliebe sonst womöglich mitten im Umschalten hängen, und die
    WPA3-Option wirkt ohnehin erst mit dem Neustart.

Danach genau ein Befehl: `sudo reboot`. Zeno sitzt dabei am Gerät; eine SSH-Verbindung ist während des Neustarts
weg. Ist der WLAN-Treiber im initramfs, bricht `umstellen` vorher ab (die Option wirkte dort nicht).

## Rückweg: `zen netzwerk zurueck`

Geht ohne Netz und ohne apt: neueste Sicherung zurückkopieren, `90-zenos-netzwerk.yaml` und alle `90-NM-*.yaml`
(auch später im Menü angelegte) in die Sicherung verschieben (`nachher-<zeit>/`), die angelegten Zusatzdateien
entfernen, NetworkManager und `zenos-wlan-land` deaktivieren. Danach `sudo reboot`; das Netz läuft wieder über
netplan mit systemd-networkd, das Land setzt `netplan-regdom`. Die WPA3-Option entfernt `zurueck` nur, wenn
`umstellen` sie angelegt hat; im Image lag sie schon vor dem ersten Start und bleibt (sie hilft auch
systemd-networkd mit `wpa_supplicant` bei Mischnetzen; von Hand: `sudo rm /etc/modprobe.d/zenos-brcmfmac.conf`).
Die Sicherungen samt WLAN-Passwörtern bleiben liegen (`docs/sicherheit.md`). `systemd-networkd-wait-online` läuft wieder, weil
seine Bedingung (Datei `90-zenos-netzwerk.yaml` fehlt) wieder erfüllt ist.

## Image: erster Start

`install.sh --image` aktiviert NetworkManager und `zenos-netzwerk-erststart.service`, legt auf arm64 die
WPA3-Option ab und die Marke `/var/lib/zenos/netzwerk-erststart`. Beim ersten Start schreibt cloud-init das WLAN aus
dem Raspberry Pi Imager nach netplan; danach (und vor NetworkManager) stellt der Dienst um wie oben und macht es
sofort wirksam (`netplan generate`, `udevadm trigger`). Die Marke wird vorher gelöscht: höchstens ein Versuch.
Scheitert er, bleibt das Netz bei systemd-networkd, NetworkManager wird für die nächsten Starts deaktiviert (wie auf
einem nicht umgestellten System), und `zen netzwerk umstellen` geht später von Hand. Die Einheit ordnet sich vor
`cloud-init-network.service` (cloud-init ab 24.3) und `cloud-init.service` (ältere Versionen) ein. Die
cloud-init-Datei liegt nie im Image, sonst griffe das WLAN aus dem Imager nicht.

## Oberfläche

- **Nur in der Leiste:** `Quickshell.Networking` steht nur in `shell/leiste/WlanQuelle.qml`, nie unter `dienste/`.
  Quickshell wählt sein Netz-Backend einmal beim ersten Zugriff und behält es bis zum Neustart von Quickshell;
  ohne NetworkManager bliebe es «None», mit einer Fehlerzeile im Protokoll. `Leiste.qml` prüft deshalb beim Start
  und beim Öffnen des System-Menüs mit `systemctl is-active --quiet NetworkManager.service` (Argumentliste), bis
  NetworkManager einmal lief, und lädt erst dann `WlanQuelle` (`LazyLoader` mit `source`: Fehlt
  `Quickshell.Networking` oder hat die Datei einen Fehler, bleibt die Leiste stehen, und das Menü zeigt die
  Netzzeile mit «NetworkManager antwortet nicht»).
- **`WlanQuelle`** gibt nur einfache Werte weiter (`bereit`, `geraetDa`, `wlanAn`, `netze`, `verbunden`,
  `verbundenStufe`, `versuch`, `fehler` …) und Funktionen (`verbinden`, `verbindenMitPasswort`, `vergessen`,
  `abbrechen`, `aufraeumen`, `wlanSetzen`). Dieselbe Schnittstelle hat die Attrappe im Container-Test.
- **System-Menü** (`WlanAbschnitt`): Kabel (falls verbunden), «WLAN» mit Schalter (nur der Schalter schaltet, auch
  per Tastatur; ein Klick auf das Wort «WLAN» trennt nichts), das verbundene Netz mit Signal, Schloss, Haken und
  «x», darunter «Netze in Reichweite» zum Aufklappen. Aufgeklappt sucht das Gerät (Quickshell fragt höchstens alle
  10 s neu), zugeklappt und bei geschlossenem Menü nicht. Höchstens fünfeinhalb Zeilen, dann scrollt die Liste; die
  angeschnittene Zeile und ein schmaler Balken rechts zeigen, dass es weitergeht. Reihenfolge: verbunden, verbindet, bekannt, Signal, Name
  (`wlan.js`).
- **Netznamen** kommen ungeprüft aus der Luft: nur als reiner Text (`Text.PlainText`, sonst würde Qt
  Auszeichnungen wie `<s></s>` oder `<img>` auswerten) und mit sichtbar gemachten unsichtbaren Zeichen
  (`anzeigeName`: Zeichen ohne Breite, Richtungs- und Steuerzeichen werden «�»).
- **Verbinden:** Ein Klick (oder Enter) verbindet ein bekanntes oder offenes Netz direkt. Bei einem neuen Netz mit
  Passwort steht an Stelle der Liste das Netz mit einem Passwortfeld (`echoMode` Password): Enter verbindet, Esc
  bricht ab. Das Feld prüft die Länge (8–63 Zeichen oder 64 Hex-Zeichen) und leert sich nach dem Senden. Unter dem
  Feld ruhig «Verbinde …», «Passwort falsch?» oder ein anderer Grund. Bietet das Netz WPA3 an und scheitert es an
  Zeit, Ablehnung oder ohne Antwort, steht dazu «Bietet das Netz nur WPA3 an, geht es mit diesem WLAN-Chip
  nicht.». Quickshell meldet Mischnetze (WPA2/WPA3) und reine WPA3-Netze gleich (`Sae`); deshalb nur als
  Möglichkeit und nicht nach «Passwort falsch?». Ob ein Netz nur WPA3 kann, zeigt
  `sudo wpa_cli -p /run/wpa_supplicant -i wlan0 scan_results` bzw. `nmcli -f SSID,SECURITY dev wifi`
  (`WPA2 WPA3` = Mischnetz, nur `WPA3` = rein).
- **Offene Netze nur auf Klick:** Das Profil eines neu verbundenen offenen Netzes (auch OWE) bekommt gleich
  «autoconnect: nein» (`NMSettings.write`), sonst verbände sich NetworkManager später überall mit jedem
  Zugangspunkt gleichen Namens. Aus dem Menü verbindet ein Klick es wieder.
- **Passwörter** gehen nur über D-Bus an NetworkManager (`connectWithPsk`), nie in eine Kommandozeile, ein
  Protokoll oder eine zenOS-Datei.
- **Gescheiterte neue Netze:** NetworkManager legt beim ersten Versuch ein dauerhaftes Profil an, auch mit falschem
  Passwort. Bricht Zeno ab oder schliesst das Menü, vergisst `WlanQuelle` jedes Profil, das ein Versuch aus dem
  Menü angelegt hat und das nie verbunden war (sonst versuchte NetworkManager es weiter). Scheitert ein solcher
  Versuch bei geschlossenem Menü, sofort. Ohne Antwort (z. B. polkit lehnt ab) gibt das Menü nach 40 s auf.
- **Vergessen:** «x» rechts bei gespeicherten Netzen, fragt einmal nach (««Telefon» vergessen?» in `fehler`).
- **Nicht verbindbar:** Unternehmens-WLAN (802.1X) und WEP stehen blass mit «nicht möglich» da. Verborgene Netze
  gibt es im Menü nicht.
- **Bildschirmfreigabe:** keine Netznamen («Netzname verborgen», Liste zu, Passwortfeld zu), sie verraten Orte.
- **Sperre:** Die Menüs der Leiste sind während der Sperre zu; der Abschnitt entsteht mit dem Menü neu.
- **Ohne NetworkManager:** die Netzzeile wie bisher (aus `System`), mit WLAN-Gerät darunter ruhig «WLAN wählen: im
  Terminal «zen netzwerk umstellen», dann neu starten.»
- **Leiste:** WLAN-Symbol mit Signalstufe (`wlan-1`, `wlan-2`, `wlan`; die fehlenden Bögen blass), von
  NetworkManager, sonst aus `/proc/net/wireless`. Ab 60 % drei, ab 35 % zwei Bögen.
- **IPC:** `zenos-ipc leiste menue wlan` öffnet das System-Menü mit aufgeklappter Liste.

## Rechte

Keine eigene polkit-Regel. Ubuntus network-manager bringt
`/usr/share/polkit-1/rules.d/org.freedesktop.NetworkManager.rules` mit: `settings.modify.system` (Profil anlegen,
ändern, löschen) für lokale, aktive Sitzungen von Mitgliedern der Gruppen `sudo` oder `netdev`. Suchen
(`wifi.scan`) und Verbinden (`network-control`) erlaubt die Policy von NetworkManager jeder lokalen Sitzung, auch
einer inaktiven; WLAN an/aus (`enable-disable-wifi`) nur aktiven. Zeno ist in `sudo`; seine Sitzung über
greetd ist `Type=wayland`, lokal und aktiv. Quickshell läuft als Benutzerdienst, polkit nimmt dafür die
«Display»-Sitzung des Benutzers (logind bevorzugt die grafische vor einer SSH-Sitzung). `zen doctor` prüft das.
Folge: Jeder Prozess in Zenos Sitzung darf systemweite Netzprofile ändern, wie auf jedem Ubuntu-Desktop. Das gilt
auch für Benutzerdienste, die per SSH gestartet werden (`systemd-run --user …`): Sie bekommen ebenfalls die
grafische Sitzung, nur direkt in der SSH-Sitzung fragt NetworkManager nach dem Passwort. Einzelheiten und Folge in
`docs/sicherheit.md`.

## WPA3 und der WLAN-Chip

Der CYW43455 (Raspberry Pi 4/5, Compute Module 5) bricht WPA3 (SAE) mit Ubuntus Firmware 7.45.265 ab
(`status_code=16`, Zeitüberschreitung bei der Anmeldung). NetworkManager 1.54 versucht bei einem WPA2/WPA3-Mischnetz
immer SAE, sobald der Treiber es meldet, und das lässt sich pro Profil nicht abschalten. Deshalb schaltet zenOS
SAE im Treiber ab: `options brcmfmac feature_disable=0x2082000` (Bits 13 FWSUP, 19 SAE, 25 SAE_EXT; Raspberry Pi
OS setzt `0x282000` und vergisst Bit 25, raspberrypi/linux #7634). Danach verbinden Mischnetze über WPA2, reine
WPA3-Netze gehen nicht (das gehen sie mit diesem Chip ohnehin nicht). `zen netzwerk umstellen` zeigt das im Plan
an, bevor es umstellt. Ausweg für ein reines WPA3-Netz: ein USB-WLAN-Stick mit Treiber im Kernel; die Profile
gelten für jedes WLAN-Gerät (`match: {}`).

## Dateien am Gerät

| Was | Wo |
|---|---|
| Umgestellt (Marke und Kabel) | `/etc/netplan/90-zenos-netzwerk.yaml` (0600 root) |
| WLAN-Profile (Passwort im Klartext, wie bisher in netplan) | `/etc/netplan/90-NM-<uuid>.yaml` (0600 root), von zenOS übernommen oder von NetworkManager angelegt |
| Sicherung vor dem Umstieg (mit WLAN-Passwörtern, auch der nach `zurueck` verschobenen Profile) | `/var/lib/zenos/netplan-vorher/<zeit>/` (0700 root), bleibt liegen |
| WLAN-Land | `/etc/xdg/zenos/wlan-land` (`LAND=XX`) |
| WPA3 aus | `/etc/modprobe.d/zenos-brcmfmac.conf` |
| cloud-init ohne Netz | `/etc/cloud/cloud.cfg.d/99-zenos-netzwerk.cfg` |
| Marke fürs Image | `/var/lib/zenos/netzwerk-erststart` |

## Entscheidungen

- **Ausdrücklich umstellen statt im Update:** Netzwerk umstellen ist ein Rückfrage-Thema (CLAUDE.md, Regel 3), und
  die WPA3-Option ist eine eigene Entscheidung. `zen netzwerk umstellen` zeigt beides und fragt; wirksam erst
  nach dem Neustart, wenn Zeno am Gerät ist. Das Image stellt beim ersten Start selbst um.
- **Ein Profil je WLAN** statt nur den Renderer umzustellen (siehe Schritt 6). Nur `renderer: NetworkManager`
  global oder auf Typ-Ebene reicht ohnehin nicht: Der Imager schreibt `wifis: renderer: networkd`, und das gilt
  weiter für `wlan0`.
- **wait-online:** Verwaltet nur noch NetworkManager das Netz, wartete `systemd-networkd-wait-online` bis zu 2
  Minuten und endete als «failed». Ein Drop-in mit `ConditionPathExists=!/etc/netplan/90-zenos-netzwerk.yaml`
  überspringt es, solange umgestellt ist; `NetworkManager-wait-online` übernimmt.
- **Keine Konnektivitätsprüfung:** `network-manager-config-connectivity-ubuntu` fragte regelmässig bei
  `connectivity-check.ubuntu.com` nach (Leitplanke Telemetrie). Es kommt nur als Empfehlung und fehlt deshalb;
  `zen doctor` warnt, falls es doch installiert ist.
- **Kein nmcli:** Quickshell.Networking spricht D-Bus und deckt Suchen, Verbinden mit Passwort, Vergessen und WLAN
  an/aus ab. Es gibt keinen Prozess mit dem Passwort.

## Im Container geprüft (Oktober 2026)

- `test/einheiten/netzwerk.test.py` (12 Tests, braucht netplan): ein Profil je WLAN, Hex-PSK und SSID «0815»
  bleiben Text, zweiter Lauf ändert nichts, `plan` ändert nichts, Abbruch ohne Änderung bei `bonds`,
  Unternehmens-WLAN, mehreren Ländern, ohne NetworkManager und ohne `wpa_supplicant`, Rückweg Byte für Byte (auch
  mit später angelegtem Profil), erster Start einmal und ohne Änderung bei einem Fehlschlag (NetworkManager danach
  deaktiviert), `status` ohne Passwörter.
- `test/einheiten/wlan.test.mjs` (10 Tests, node): Signalstufen, Reihenfolge, Passwort-Prüfung, Texte (WPA3-Hinweis
  nicht nach «Passwort falsch?»), Netznamen mit Unsichtbarem, reiner Text in `WlanZeile.qml`.
- Ganzer Weg mit gerätegleichen netplan-Dateien (neutrale Namen, Kabel als `ethtest0`): `install.sh` installiert
  NetworkManager und deaktiviert ihn, zweiter Lauf 0 Änderungen; `zen netzwerk umstellen` ohne Terminal lehnt
  ab, mit «nein» bricht es ab, mit «umstellen» schreibt es drei Profile und `90-zenos-netzwerk.yaml`; danach
  `install.sh` zweimal 0 Änderungen. Nach `netplan generate` und dem Start von NetworkManager (statt Neustart)
  zeigt `nmcli` ein Profil je WLAN, `zen netzwerk status` und `zen doctor` melden den Stand. `zen netzwerk
  zurueck` stellt `50-cloud-init.yaml` und `60-wlan.yaml` Byte für Byte wieder her, deaktiviert NetworkManager
  und `zenos-wlan-land`, und `netplan generate` erzeugt wieder die Dateien für systemd-networkd.
- Start-Test (`scripts/pruefen.sh start`) mit und ohne laufenden NetworkManager: Rundgang mit 41 IPC-Aufrufen,
  darunter `leiste menue system`, `leiste menue wlan` und `leiste schliessen`, ohne Befund.
- Oberfläche in der Sitzung: ohne NetworkManager die Netzzeile mit Hinweis, mit NetworkManager lädt
  `WlanQuelle` (`bereit`, kein WLAN-Gerät im Container). Die Zustände mit WLAN mit einer Attrappe, hell und
  dunkel: verbunden, Liste, schwaches Signal, verbindet, Fehler, ohne Verbindung, WLAN aus, leere Liste,
  Passwortfeld (per Tastatur: Pfeile, Enter, zu kurz, «Verbinde …», «Passwort falsch?», Esc), Bildschirmfreigabe;
  Leiste mit Signalstufen.

## Am Gerät prüfen

- Vorher, nur lesen: `sudo sed -E 's/(password:).*/\1 …/' /etc/netplan/*.yaml` (nur `ethernets` und `wifis`?),
  `loginctl show-session $XDG_SESSION_ID -p Type -p Remote -p Active` in kitty (wayland, no, yes),
  `iw phy | grep -i 'SAE with AUTHENTICATE'` (Treiber meldet WPA3), `sudo lsinitrd | grep brcmfmac` (Treiber im
  initramfs?).
- Nach `zen update`: `systemctl is-enabled NetworkManager` = disabled, `zen netzwerk status`, `zen doctor`.
- `zen netzwerk umstellen`, dann `sudo reboot` am Gerät, an einem Ort mit bekanntem WLAN.
- Danach: `zen netzwerk status` (NetworkManager läuft, ein Profil je früherem WLAN, Land gesetzt, WPA3 im Treiber
  aus), `systemctl --failed` leer, `systemd-analyze blame | head` ohne 2-Minuten-Posten,
  `systemd-run --user --pipe --wait nmcli general permissions` (yes bei network-control, wifi.scan,
  enable-disable-wifi, settings.modify.system), auch mit offener SSH-Sitzung.
- Im Menü, hell und dunkel: Liste, neues Netz mit Passwort, falsches Passwort (danach kein Profil übrig:
  `ls /etc/netplan`), Vergessen (nur dessen Datei verschwindet), WLAN aus/an, Freigabe ohne Namen, Signal in der
  Leiste.
- `sudo systemctl restart NetworkManager`: zeigt das Menü danach weiter Netze? Sonst `systemctl --user restart
  zenos-shell`.
- Rückweg einmal üben: `zen netzwerk zurueck`, `sudo reboot`, wieder umstellen.
