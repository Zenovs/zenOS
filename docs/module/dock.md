# Docks und Bildschirm über USB

Steckt Zeno ein USB-C-Dock ein und der Bildschirm daran bleibt dunkel, soll zenOS einmal klar sagen, warum und was
stattdessen geht. Bei einem DisplayLink-Gerät soll zenOS es erkennen und sagen, welcher Treiber fehlt. Installiert wird
dabei nie etwas.

## Wie Bild über USB-C kommt

- **USB-C-Dock mit DisplayPort Alt Mode:** Das Dock bekommt das Bild als DisplayPort direkt aus der USB-C-Buchse des
  Rechners und verteilt es auf seine Ausgänge (bei mehreren Bildschirmen oft über MST). Einen Treiber braucht es nicht,
  wohl aber eine Buchse, die DisplayPort liefert. Kann die Buchse das nicht, meldet das Dock ein **Billboard-Gerät**
  (USB-Klasse 0x11) und bleibt dunkel. USB, Netzwerk und Strom am Dock gehen trotzdem.
- **DisplayLink:** Ein Chip im Dock oder Adapter (Hersteller 17e9, heute Synaptics) bekommt das Bild als Daten über
  USB. Dafür braucht es einen Treiber: `udl` im Kernel für alte Chips (USB 2.0), sonst das Kernelmodul `evdi` und den
  proprietären DisplayLink-Treiber von Synaptics (`DisplayLinkManager`).

## Am Argon ONE UP

Das Compute Module 5 (BCM2712, wie der Pi 5) gibt Bild nur über HDMI aus. Einen DisplayPort-Ausgang hat der Chip
nicht, auch nicht an USB-C. Am Argon ONE UP ist `HDMI-A-2` das eingebaute Display und `HDMI-A-1` die HDMI-Buchse. Die
beiden USB-C-Buchsen führen nur USB 2.0 über den eingebauten Hub; ohne das GPIO-Modul hat eine davon gar keine Daten.

Am Gerät nachgesehen mit einem i-tec USB-C-Dock für drei Bildschirme (DisplayPort Alt Mode mit MST, kein DisplayLink):
Hubs, LAN (Realtek RTL8153, Treiber `r8152`) und die Geräte daran laufen mit 480 Mbit/s, für das Bild meldet sich ein
Billboard von Fresco Logic (`1d5c:7102`). Sein BOS-Deskriptor ist nur generisch ausgefüllt: SVID 0 und «Alt Mode
erfolgreich», obwohl kein Bild kommt. Dieses Dock gibt an diesem Rechner kein Bild aus, und kein Treiber ändert das.
Der Bildschirm gehört an die HDMI-Buchse, das Dock bleibt für Netzwerk und USB. An einem Rechner mit DisplayPort
an USB-C (etwa dem späteren x86-Bürorechner) geht dasselbe Dock ohne Treiber.

## Was gebaut ist

- **`scripts/bin/zenos-dock`** (Python, läuft als Benutzer): `melden` (Benutzerdienst), `pruefen` (für `zen doctor`)
  und `vergessen`. Einzelheiten im Kopf der Datei.
- **udev-Regel `system/udev/73-zenos-dock.rules`** nach `/etc/udev/rules.d/`: Billboards (als Gerät mit
  `bDeviceClass` 11 oder als Schnittstelle mit `bInterfaceClass` 11) und DisplayLink-Geräte (`idVendor` 17e9) bekommen
  nur `TAG+="systemd"` und `SYSTEMD_USER_WANTS=zenos-dock.service`. Keine Rechte, kein Treiber, nichts als root. Sie
  greift bei jedem Ereignis ausser `remove`, denn systemd führt ein Gerät nur, solange das letzte Ereignis die
  Markierung trägt.
- **Benutzerdienst `system/systemd/user/zenos-dock.service`** nach `/etc/systemd/user/`: `Type=oneshot`, gestartet
  von udev beim Einstecken und von `zenos-sitzung.target` beim Anmelden (ein Dock, das schon beim Start steckt). Nur in
  der Sitzung eines Menschen (`ConditionUser=!@system`, `ConditionEnvironment=WAYLAND_DISPLAY`), nicht für den Login.
- **Modul `scripts/module/84-dock.sh`:** installiert Regel und Einheit. Nach einer neuen oder geänderten Regel lädt es
  die Regeln neu und schickt nur Billboards und DisplayLink-Geräte noch einmal durch (`udevadm trigger --action=change`,
  nie `add`). So meldet sich ein schon eingestecktes Dock gleich. Keine Pakete.
- **`zen doctor`**, Abschnitt «Docks und Bildschirm über USB» (`scripts/doctor.d/84-dock.sh`): Regel und Einheit
  installiert, Bildausgänge, jedes Dock und DisplayLink-Gerät, Netzwerk über USB (Treiber und Kabel, ohne
  Schnittstellennamen: sie enthalten die MAC), schon gemeldete Befunde, ein gescheiterter letzter Lauf.

## Befunde und Mitteilungen

Entschieden wird an den Bildausgängen unter `/sys/class/drm`: Anschlüsse `DP-…` sind DisplayPort, `eDP-…` ein
eingebautes Display. Was das Billboard über seine Alt Modes sagt (SVID `ff01` DisplayPort, `8087` Thunderbolt), steht
nur im Text, denn manche Docks füllen den Deskriptor bloss generisch aus.

| Lage | `zen doctor` | Mitteilung (Absender zenOS, normal) |
|---|---|---|
| Billboard, kein DisplayPort-Ausgang (Pi 5, Compute Module 5) | Hinweis, mit freien HDMI-Ausgängen | «Dock: kein Bild über USB-C» – «Dieser Rechner gibt über USB-C kein Bild aus, daran ändert auch ein Treiber nichts. Schliess den Bildschirm an HDMI an. USB und Netzwerk am Dock gehen weiter.» |
| Billboard, DisplayPort-Ausgänge da, keiner verbunden | Warnung | «Dock: kein Bild an dieser Buchse» – andere USB-C-Buchse versuchen (DisplayPort- oder Thunderbolt-Zeichen) |
| Billboard, ein DisplayPort-Bildschirm verbunden | ok | keine |
| DisplayLink mit Kernel-Treiber `udl` | ok | keine |
| DisplayLink, `evdi` geladen und `DisplayLinkManager` läuft | Hinweis «unter labwc ungetestet» | keine |
| DisplayLink ohne Treiber | Hinweis | «DisplayLink-Gerät erkannt» – zenOS liefert den Treiber von Synaptics nicht mit und hat ihn unter labwc nicht geprüft |

- `melden` wartet 3 s, bis Dock und Bildschirme da sind, dann bis 60 s auf den Mitteilungsdienst (beim Anmelden
  startet die Oberfläche gerade erst). Jede Mitteilung kommt einmal je Gerät (`vid:pid`) und Befund, gemerkt in
  `~/.local/state/zenos/dock-meldungen.json` (0600, höchstens 50). Kommt sie nicht an, bleibt sie offen und der
  nächste Lauf versucht es wieder. `zenos-dock vergessen` löscht den Merker.
- Mitteilungen über `notify-send` mit Argumentliste (`--category=device`), nie über eine Shell.
- Im Journal (`journalctl --user -u zenos-dock`) und in `zen doctor` stehen Hersteller, Produkt und `vid:pid`, nie
  Seriennummern, Netzwerknamen oder Adressen.

## Entscheidungen

- **Kein Treiber, nur Erkennung.** Für ein Billboard-Dock am Pi gibt es keinen Treiber. Der DisplayLink-Treiber ist
  proprietär (nie im Image) und unter labwc nicht geprüft. Stand Oktober 2026: Synaptics liefert ihn in Version 6.3
  auch für aarch64 und Ubuntu 26.04, offiziell aber nur bis Kernel 6.15 (der Pi hat 7.0). `evdi-dkms` 1.14.15 liegt in
  Ubuntu universe. wlroots 0.19 hat keinen eigenen Code für evdi; andere Distributionen nutzen dafür einen Patch und
  `WLR_EVDI_RENDER_DEVICE`. Ein Angebot «Treiber installieren …» kommt erst, wenn ein DisplayLink-Gerät zum Testen da
  ist und das Bild unter labwc wirklich steht.
- **Ein kurzer Dienst statt eines Wächters.** udev startet `zenos-dock` nur, wenn ein passendes Gerät kommt. Kein
  Prozess läuft dauernd, die Oberfläche bleibt unberührt.
- **Einmal, nicht bei jedem Einstecken.** Wer das Dock täglich für Netzwerk nutzt, braucht die Erklärung nur einmal.
  `zen doctor` zeigt die Lage jederzeit.
- **Kein «ganzes Dock».** Auf dem Pi meldet `/sys` für alle USB-Geräte `removable=unknown`, und die Teile eines Docks
  haben verschiedene Container-IDs. Welche Geräte zum Dock gehören, lässt sich so nicht sicher sagen. Darum nennt die
  Mitteilung nur, was für jedes Dock gilt, und `zen doctor` listet Netzwerk über USB für sich.

## Am Gerät prüfen

- Dock einstecken (Bildschirm am Dock): Nach wenigen Sekunden kommt einmal «Dock: kein Bild über USB-C».
  `zen doctor` zeigt im Abschnitt «Docks und Bildschirm über USB» die Bildausgänge, das Billboard und das Netzwerk.
- Ab- und wieder einstecken, ab- und wieder anmelden: keine zweite Mitteilung.
- `/opt/zenos/scripts/bin/zenos-dock vergessen`, Dock neu einstecken: Die Mitteilung kommt wieder.
- `journalctl --user -u zenos-dock` nennt «gemeldet: USB-C-Dock (Billboard 1d5c:7102, …)».
- Bildschirm an `HDMI-A-1`: kanshi nimmt das passende Profil (`docs/module/m9.md`).

## Rückweg

Ein `zen rollback` auf einen Stand ohne dieses Modul lässt Regel und Einheit liegen. Das ist harmlos: Ohne
`/opt/zenos/scripts/bin/zenos-dock` startet der Dienst nicht (`ConditionFileIsExecutable`). Von Hand entfernen:
`sudo rm /etc/udev/rules.d/73-zenos-dock.rules /etc/systemd/user/zenos-dock.service`, dann
`sudo udevadm control --reload`.
