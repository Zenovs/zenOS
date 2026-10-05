# Systemkennung · zenOS statt Ubuntu

Das System weist sich als zenOS aus (`ID=zenos`, `ID_LIKE="ubuntu debian"`), so wie Pop!_OS, Linux Mint und
elementary OS. Zeno hat das so entschieden (Variante A im Bauplan). Ubuntu-Marken verschwinden aus Name, Logo,
Kennung und Begrüssung. Die sachliche Herkunftsangabe «basiert auf Ubuntu» bleibt, ebenso alle Lizenz- und
Urheberhinweise. Vorarbeit war das Sicherheitsnetz in `docs/module/m11.md` («Sicherheitsnetz für eine eigene
Systemkennung», Phase 1): Ohne `51zenos-ubuntu-quellen` schnitte die Kennung zenOS alle Ubuntu-Sicherheitsupdates
lautlos ab.

## Was gebaut ist

- **`scripts/bin/zenos-kennung`** (Python, läuft als root): Unterbefehle `einrichten`, `erneuern`, `ubuntu`
  (Rückweg), `pruefen` und `erzeugen`. Die ausgeführte Kopie liegt root-eigen unter `/usr/local/sbin/zenos-kennung`
  (Modul 72). Einzelheiten im Kopf der Datei.
- **Umlenkungen statt Änderungen an base-files:** `/usr/lib/os-release`, `/etc/issue` und `/etc/legal` werden zuerst
  nach `<datei>.ubuntu` kopiert (Rechte und Zeit bleiben), dann mit
  `dpkg-divert --local --no-rename --divert <datei>.ubuntu --add <datei>` umgelenkt, danach schreibt das Programm die
  zenOS-Fassung atomar (temporäre Datei, `rename`). Updates von base-files landen so in `<datei>.ubuntu`.
  `/etc/os-release` bleibt Ubuntus Verweis auf `../usr/lib/os-release`.
- **`/usr/lib/os-release`**, zum Beispiel auf dev nach `v0.1.0-rc2`:

  ```
  PRETTY_NAME="zenOS 0.1.0-rc2-18-ge1ee578"
  NAME="zenOS"
  VERSION="0.1.0-rc2-18-ge1ee578 (basiert auf Ubuntu 26.04.1 LTS)"
  VERSION_ID="26.04"
  VERSION_CODENAME=resolute
  ID=zenos
  ID_LIKE="ubuntu debian"
  HOME_URL="https://github.com/Zenovs/zenOS"
  DOCUMENTATION_URL="https://github.com/Zenovs/zenOS/tree/main/docs"
  UBUNTU_CODENAME=resolute
  LOGO=zenos
  ZENOS_VERSION="0.1.0-rc2-18-ge1ee578"
  ```

  `VERSION_ID`, `VERSION_CODENAME` und `UBUNTU_CODENAME` kommen immer aus `os-release.ubuntu`, die Herkunft im Text aus
  dessen `PRETTY_NAME`.
- **`/etc/issue`** (Textkonsole): `\S \n \l` und eine Leerzeile. agetty setzt für `\S` den `PRETTY_NAME` ein, also
  «zenOS 0.1.0-rc2-18-ge1ee578 <rechner> tty1»; bei einer neuen Version bleibt die Datei gleich.
- **`/etc/legal`** (zeigt `pam_motd` einmal je Benutzer): freie Software und Firmware, Lizenzen unter
  `/usr/share/doc/*/copyright`, `/usr/local/share/doc/zenos/copyright` und `/usr/local/share/doc/quickshell/copyright`,
  Quellen in `/usr/local/share/doc/zenos/QUELLEN`, Markenhinweise in `RECHTLICHES` daneben, «basiert auf Ubuntu …
  nicht mit Canonical verbunden … weder unterstützt noch geprüft», ohne Gewährleistung. Die drei Dateien unter
  `/usr/local/share/doc/zenos/` legt `72-kennung` an (aus `LICENSE` und `system/doc/`), auch wenn die Kennung Ubuntu
  bleibt.
- **Begrüssung (motd):** `00-header` («Welcome to Ubuntu»), `10-help-text` (docs.ubuntu.com, Landscape, Ubuntu Pro),
  `91-contract-ua-esm-status` und `91-release-upgrade` werden mit `dpkg-statoverride --update --add root root 0644`
  stillgelegt (nur vorhandene). Dazu `/var/lib/update-notifier/hide-esm-in-motd` (Schalter von update-notifier, blendet
  die Werbung für ESM in «N updates can be applied» aus; der Text wird gleich neu geschrieben). Neu
  `/etc/update-motd.d/00-zenos`:

  ```
  zenOS 0.1.0-rc2-18-ge1ee578 · Basis Ubuntu 26.04.1 LTS · Kernel 7.0.0-1017-raspi
  Hilfe: zen hilfe · Zustand: zen doctor
  ```

  Aktiv bleiben, weil lokal und nützlich: `90-updates-available`, `92-unattended-upgrades`, `95-hwe-eol`,
  `98-reboot-required`, `98-fsck-at-reboot` und die Skripte des Pi (`90-pemmican`, `90-piboot-try`, `85-fwupd`,
  `97-overlayroot`). `50-motd-news` legt `70-sicherheit` still (siehe unten).
- **Verweise** (gehören keinem Paket): `/usr/share/python-apt/templates/zenos.info` → `ubuntu.info`,
  `zenos.mirrors` → `ubuntu.mirrors`, `/usr/share/distro-info/zenos.csv` → `ubuntu.csv`, nur wenn es die Ziele gibt.
  Ohne sie bricht `add-apt-repository` mit «NoDistroTemplateException … zenos/resolute» ab.
- **Logo:** `LOGO=zenos`, dazu `/usr/local/share/icons/hicolor/scalable/apps/zenos.svg` (das App-Icon der Bildmarke
  aus `assets/zeichen/zenos-app-icon.svg`). Die Ubuntu-Logos unter `/usr/share/pixmaps/` bleiben als Dateien von
  base-files liegen, nichts verweist mehr auf sie.
- **apt-Hook** `system/apt/60zenos-kennung` → `/etc/apt/apt.conf.d/`: `DPkg::Post-Invoke` ruft
  `zenos-kennung erneuern` nach jedem dpkg-Lauf von apt und unattended-upgrades, mit `|| true` und nur, wenn das
  Programm da ist. So folgt die Kennung einer neuen Punktversion oder einem Release-Upgrade von Ubuntu.
- **Modul `scripts/module/72-kennung.sh`** (nach 70-sicherheit, damit `51zenos-ubuntu-quellen` schon liegt; auch im
  Image-Modus):
  1. Programm und Hook installieren, aber nur, wenn `/usr/local/sbin` und alle Ordner darüber root gehören und nur
     für root schreibbar sind.
  2. `/usr/local/share/zenos/version` aus `git describe` von `/opt/zenos` schreiben (ohne «v» und «-dirty»).
  3. Logo ablegen.
  4. Vorab-Prüfung: die neue os-release mit `zenos-kennung erzeugen` in den Temp-Ordner, dann
     `LSB_OS_RELEASE=<neu> zenos-sicherheitsquelle`. Exit 0 → `zenos-kennung einrichten` (nur, was fehlt oder
     veraltet ist). Exit 1 → keine Umstellung und eine Warnung; gilt die Kennung zenOS schon, zurück auf Ubuntu ohne
     Merker. Exit 2 → keine erste Umstellung und eine Warnung; eine schon geltende Kennung zenOS wird nachgezogen.
     Hat Zeno mit `zenos-kennung ubuntu` zurückgestellt, stellt install.sh nicht um.
- **Angepasst:** `00-vorbereitung` und `zen doctor` (00-basis) nehmen Ubuntu 26.04 als Kennung oder als Basis an
  (`ID=zenos` mit `ubuntu` in `ID_LIKE`, `VERSION_ID` aus `os-release.ubuntu`; `system_unterstuetzt` in
  `scripts/lib/gemeinsam.sh`). `zen version` zeigt eine eigene Zeile «Basis Ubuntu 26.04.1 LTS» (statt «System …»);
  Einstellungen › System zeigt die Ausgabe von `zen version` unverändert an, also auch diese Zeile.
- **`image/bauen.sh`:** Nach `install.sh --image` neuer Schritt «Kennung und Sicherheitsquelle prüfen». Der Bau
  bricht ab, wenn die Umlenkung, `ID=zenos`, `lsb_release -cs` gleich dem Ubuntu-Codenamen, `51zenos-ubuntu-quellen`,
  `zenos-sicherheitsquelle` mit Exit 0 oder `zenos-kennung pruefen` fehlt, oder wenn `PRETTY_NAME` Ubuntu nennt. Die
  Prüfung `ID=ubuntu` am heruntergeladenen Ubuntu-Image bleibt.
- **`zen doctor`**, Abschnitt «Systemkennung» (`scripts/doctor.d/72-kennung.sh`): Programm vorhanden, nur für root
  schreibbar und gleich wie in `/opt/zenos`; Hook vorhanden und aktuell; `zenos-kennung pruefen` (Umlenkungen,
  os-release aktuell, Konsole, Begrüssung, Verweise); `lsb_release -cs` gleich `VERSION_CODENAME` aus
  `os-release.ubuntu`; `UBUNTU_CODENAME` genau einmal und ohne Anführungszeichen; Verweise mit Ziel; Hinweis bei einem
  ausstehenden Update von base-files; `apt-check` von update-notifier läuft ohne Ausnahme. Mit 70-sicherheit
  zusammen: Sicherheitsquelle erlaubt, und mit der Kennung zenOS ist eine fehlende `51zenos-ubuntu-quellen` ein Fehler.

## motd-news ohne Änderung am Conffile

`70-sicherheit` schrieb bisher `ENABLED=0` in `/etc/default/motd-news`, ein Conffile von motd-news-config (Quelle
base-files). Ein geändertes Conffile hält unattended-upgrades bei einem Paket-Update an (es überspringt Pakete, die
nachfragen würden). Neu: `systemctl mask` für `motd-news.timer` und `motd-news.service` (mit laufendem systemd ausser
im Image-Modus auch gleich angehalten) und `dpkg-statoverride … 0644` für `50-motd-news`. Das Conffile bleibt
unberührt; ein auf schon eingerichteten Geräten gesetztes `ENABLED=0` bleibt stehen und schadet nicht (keine
Rückänderung, sonst fragte dpkg bei der nächsten Version nach). `zen doctor`: Timer maskiert = ✓, sonst mit
`ENABLED=0` ein Hinweis, mit `ENABLED=1` eine Warnung; ein noch ausführbares `50-motd-news` ist ein Hinweis.

## Entscheidungen

- **Python statt Shell** für `zenos-kennung`: os-release wird gelesen, nicht mit `.` ausgeführt; Anführungszeichen
  und Escapes schreibt es nach os-release(5). Der Generator lässt sich ohne root und auf dem Mac testen, der ganze
  Ablauf mit `--wurzel` in einer Testwurzel (dpkg-divert und dpkg-statoverride haben `--root`).
- **Kopie unter `/usr/local/sbin`, nicht `/opt/zenos`:** `/opt/zenos` gehört zwar root, aber ein `zen rollback` auf
  einen Stand ohne Kennung nähme das Programm dort weg, während Umlenkungen und Hook blieben. Die Kopie bleibt (wie
  `51zenos-ubuntu-quellen`), der Hook zieht die Kennung weiter nach. Das Modul prüft vorher, dass niemand ausser root
  `/usr/local/sbin` oder einen Ordner darüber schreiben kann; `zen doctor` prüft dasselbe.
- **Sperre wie apt:** dpkg-divert und dpkg-statoverride nehmen in dpkg 1.23.7ubuntu1 keine Sperre (im Container geprüft: beide
  laufen, während ein anderer Prozess `lock-frontend` und `lock` hält). `einrichten` und `ubuntu` halten deshalb
  selbst `/var/lib/dpkg/lock-frontend` (warten höchstens 5 Minuten) und geben `DPKG_FRONTEND_LOCKED=1` weiter;
  `erneuern` nie, denn im Hook hält apt die Sperre schon.
- **Version ehrlich:** `zenos_version` liefert auf dev heute `v0.1.0-rc2-18-ge1ee578-dirty`. In die Kennung kommt
  `0.1.0-rc2-18-ge1ee578`: ohne «v» (wie im Dateinamen des Images) und ohne «-dirty» (nicht committete Änderungen
  zeigt `zen version`). Der Bauplan schlug «letzter Release-Tag» vor; das hiesse auf dev «0.1.0-rc2», obwohl der
  Stand 18 Commits weiter ist. Auf einem Tag (Image, `zen rollback v0.1.0`) steht genau «0.1.0». Ohne lesbare Version
  heisst es nur «zenOS».
- **Rückweg mit Merker:** `zenos-kennung ubuntu` schreibt `/var/lib/zenos/kennung` (`kennung=ubuntu`, `seit=…`), wie
  die bewusst ausgeschaltete Firewall. install.sh und `zen update` lassen die Kennung dann bei Ubuntu,
  `zenos-kennung einrichten` hebt den Merker auf. Dauerhaft bei Ubuntu bleiben heisst also nur:
  `sudo zenos-kennung ubuntu`. Der automatische Rückweg des Moduls (Vorab-Prüfung Exit 1) setzt keinen Merker
  (`--ohne-merker`): Der nächste Lauf prüft wieder und stellt um, sobald die Sicherheitsquelle erlaubt ist.
- **Exit 2 der Vorab-Prüfung:** «nicht prüfbar» heisst meist: keine Paketliste der Sicherheitsquelle (vor dem ersten
  `apt update`). Dann holt das Modul vor der ersten Umstellung einmal die Paketlisten (`apt-get update`, wie
  `pakete_sicherstellen` es ohnehin tut) und prüft noch einmal. Bleibt es bei «nicht prüfbar», keine Umstellung:
  Sicherheit geht vor dem Namen, der nächste Lauf versucht es wieder. Im Image liegen die Listen spätestens danach
  vor, und `bauen.sh` verlangt Exit 0. Eine schon geltende Kennung zenOS bleibt bei Exit 2 und wird nachgezogen (ein
  zeitweise fehlender Paketcache soll nicht hin und her schalten).
- **Gate auch ohne Änderung:** Die Vorab-Prüfung läuft bei jedem install.sh (rund 0,3 s), damit ein später
  dazugekommenes Problem (etwa eine fremde Datei in `apt.conf.d`, die `Allowed-Origins` leert) auffällt und die
  Kennung zurückgeht.
- **Logo unter `/usr/local/share`** statt `/usr/share/icons/hicolor` (Bauplan): wie Schriften und Starter von zenOS;
  `/usr/share` gehört den Paketen (und dessen Icon-Cache), und die Icon-Suche findet `/usr/local/share` über
  `XDG_DATA_DIRS` genauso. Als Logo dient das App-Icon (dunkle Fläche mit den zwei Steinen), dasselbe Bild wie das
  App-Icon `zenos` im Benutzerordner.
- **Nicht angefasst:** `/etc/lsb-release` (DISTRIB_ID=Ubuntu, liest lsb_release auf 26.04 nicht mehr; beschreibt
  ehrlich die Basis; ein Divert wäre ein weiteres Conffile), `/etc/issue.net` (ohne Banner in sshd unsichtbar, SSH ist
  tabu), Paketquellen, Schlüssel, `/etc/dpkg/origins/default`, Paketnamen, Kernel- und SSH-Kennungen sowie alle
  Copyright-Zeilen von Canonical. Kein Ubuntu-Paket wird entfernt, umbenannt oder neu gebaut.
- **apport:** Mit `ID=zenos` behandelt apport Ubuntu-Pakete nicht mehr als Pakete der Distribution
  (`is_distro_package` → False, Bauplan). `ubuntu-bug` meldet zenOS also nicht an Launchpad; das ist richtig so.
- **base-files und unattended-upgrades:** base-files kommt aus `-updates`, das unattended-upgrades ohnehin nicht
  installiert. Käme eine Version, die `/etc/issue` oder `/etc/legal` ändert, einmal über eine erlaubte Quelle
  (`-security`), liesse unattended-upgrades sie aus: Seine Prüfung auf Conffile-Rückfragen vergleicht die Datei am
  ursprünglichen Ort und kennt keine Umlenkung (im Container nachgestellt, siehe unten). Die übrigen Updates kommen
  trotzdem, der Lauf endet aber mit «upgrade result: False»; `zen doctor` meldet dann das ausstehende Update von
  base-files und nach drei Tagen den fehlenden erfolgreichen Lauf. `sudo apt upgrade` von Hand läuft ohne Rückfrage
  durch (dpkg kennt die Umlenkung). Das ist der Preis dafür, Konsole und `/etc/legal` umzubenennen; os-release ist
  kein Conffile und davon nicht betroffen.

## Rückweg

```
sudo zenos-kennung ubuntu
```

Entfernt die drei Umlenkungen und stellt die Ubuntu-Fassungen an ihren Platz zurück (`rename`, Byte für Byte die
Fassung, die dpkg zuletzt geschrieben hat), nimmt die eigenen statoverrides weg und setzt die Skripte wieder auf
0755, entfernt `00-zenos`, `hide-esm-in-motd` und die Verweise und schreibt den Merker. `51zenos-ubuntu-quellen`,
Hook, Programm, Logo und Versionsdatei bleiben; mit `ID=ubuntu` tun sie nichts. Zurück zu zenOS:
`sudo zenos-kennung einrichten` (oder danach `zen update`).

**`zen rollback` auf einen Stand vor der Kennung** (`v0.1.0-rc2` und älter): Die Kennung bleibt, denn Programm, Hook
und `51zenos-ubuntu-quellen` liegen ausserhalb von `/opt/zenos` und bleiben liegen. install.sh des alten Stands warnt
in 00-vorbereitung «gebaut für Ubuntu 26.04, gefunden: zenOS …» und läuft weiter. Die Version in os-release bleibt
dabei die des letzten Stands mit Kennung (der alte Stand schreibt `/usr/local/share/zenos/version` nicht); `zen
version` zeigt den echten Stand. Wer mit dem alten Stand ganz bei Ubuntu sein will: vorher
`sudo zenos-kennung ubuntu`.

## Release-Upgrade (26.04 → 28.04)

Noch nicht getestet. Bis dahin:

1. `sudo zenos-kennung ubuntu`
2. `sudo do-release-upgrade`
3. `sudo zenos-kennung einrichten`, dann `zen update` (install.sh prüft die Sicherheitsquelle mit dem neuen Codenamen)

Der Hook zieht `VERSION_CODENAME` nach, sobald base-files von 28.04 installiert ist; bliebe er stehen, erlaubte
unattended-upgrades weiter nur «resolute-security», und die Updates blieben lautlos aus. `zen doctor` (Codename wie
Ubuntu) fängt das ab. `91-release-upgrade` ist stillgelegt; eine neue LTS meldet zenOS heute nicht selbst.

## Im Container geprüft (Oktober 2026)

`zenos-test:installiert` (Ubuntu 26.04.1 arm64), dazu wie auf dem Pi update-notifier-common,
ubuntu-release-upgrader-core, ubuntu-pro-client, software-properties-common und motd-news-config.

- **install.sh zweimal** (als `tester`, Kennung vorher Ubuntu): erster Lauf ohne Warnung, in 72-kennung Programm,
  Hook, Version, Logo, drei Umlenkungen mit neuen Fassungen, vier statoverrides, `00-zenos`, `hide-esm-in-motd` und
  drei Verweise (in 70-sicherheit dazu motd-news maskiert und stillgelegt); zweiter Lauf `0 Änderungen`.
- **Vorher und nachher gleich:** `apt-get -s dist-upgrade` 12 Pakete, dieselbe Liste. `unattended-upgrade --dry-run
  --debug` vorher (Ubuntu, ohne 51) und nachher (zenOS) dieselben 8 Pakete (gstreamer1.0-plugins-good,
  libheif-plugin-aomdec, libheif1, libssl3t64, libxpm4, openssl, openssl-provider-legacy, python3-jwt); nachher stehen
  `o=Ubuntu,a=resolute-security` und `o=zenOS,…` in «Allowed origins», keine Meldung «Could not figure out
  development release». `zenos-sicherheitsquelle` → «erlaubt: … distro_id=zenOS», `apt-check` → `12;8`.
- **Anzeigen:** `lsb_release -a` → «Distributor ID: zenOS», «Description: zenOS 0.1.0-rc2-18-ge1ee578»,
  «Release: 26.04», «Codename: resolute»; `hostnamectl` → «Operating System: zenOS 0.1.0-rc2-18-ge1ee578»;
  `agetty --show-issue` (mit `script`) → «zenOS 0.1.0-rc2-18-ge1ee578 zenos-test tty1»;
  `run-parts --lsbsysinit --test /etc/update-motd.d` ohne 00-header, 10-help-text, 50-motd-news, 91-*; die Begrüssung
  beginnt mit «zenOS … · Basis Ubuntu 26.04.1 LTS · Kernel …», die ESM-Werbung fehlt, sobald update-notifier den Text
  neu schreibt (zenos-kennung stösst das an). `zen version` mit «Basis Ubuntu 26.04.1 LTS», `zen doctor` 0 Fehler
  (Abschnitt «Systemkennung» vier ✓, «motd-news aus (Timer maskiert)»).
- **`apt-get install --reinstall base-files`:** os-release, `/etc/issue`, `/etc/legal` unverändert, Modus 644 der
  stillgelegten Skripte bleibt, `dpkg --verify base-files` ohne Befund (bis auf die im Container fehlende Doku),
  `zenos-kennung pruefen` → eingerichtet.
- **Ubuntu-Werkzeuge mit `ID=zenos`:** `add-apt-repository -y -n "deb http://archive.example.invalid/ubuntu resolute
  main"` → Exit 0 (aptsources: `zenos resolute`), `pro status` läuft, `do-release-upgrade -c` meldet dasselbe wie mit
  der Kennung Ubuntu («There is no development version of an LTS available», Exit 1), `ubuntu-distro-info` und
  python3-distro-info laufen.
- **Ende-zu-Ende mit einem nachgebauten neueren base-files** (`14ubuntu6.4~zenostest2`, «26.04.2», als
  `resolute-security` in einer lokalen Quelle): Der echte Lauf von `unattended-upgrade` installiert die 8
  Sicherheitsupdates, lässt base-files aber aus («conffile prompt found for /etc/issue», «upgrade result: False»,
  Exit 1); siehe Entscheidung oben. `apt-get install base-files` von Hand danach ohne Rückfrage, der Hook schreibt
  `VERSION="… (basiert auf Ubuntu 26.04.2 LTS)"`, `/etc/issue` bleibt die zenOS-Fassung, `/etc/issue.ubuntu` hat
  «Ubuntu 26.04.2 LTS», `dpkg --verify` sauber. `dpkg -i` eines base-files mit Codename «zukunft» (ohne apt, also
  ohne Hook): `zen doctor` meldet ✗ «lsb_release meldet den Codenamen «resolute», Ubuntu ist bei «zukunft»» und
  «veraltet: /usr/lib/os-release»; `zenos-kennung erneuern` zieht nach, danach ✓.
- **Vorab-Prüfung:** Eine fremde Datei in `apt.conf.d`, die `Allowed-Origins` leert und nur
  `${distro_id}:${distro_codename}-security` erlaubt: Bei geltender Kennung warnt install.sh und stellt ohne Merker
  auf Ubuntu zurück (12 Änderungen); der nächste Lauf warnt «Kennung bleibt Ubuntu …» und ändert nichts. Datei weg →
  nächster Lauf stellt wieder um, danach `0 Änderungen`. Ohne die Paketlisten der Sicherheitsquelle (normaler Lauf)
  oder ohne alle Paketlisten (Image-Modus): «Paketlisten aktualisieren für die Vorab-Prüfung der Kennung», dann
  umgestellt; die ESM-Werbung ist danach aus dem Text von update-notifier verschwunden. Bei geltender Kennung ohne
  Paketliste: «… nicht prüfbar … Die Kennung zenOS bleibt», keine Änderung. Die Warnung für ein dauerhaftes «nicht
  prüfbar» (etwa ohne Netz) lief nur in einer früheren Fassung ohne den neuen Versuch.
- **Rückweg:** `zenos-kennung ubuntu` → `lsb_release -is` Ubuntu, os-release, issue und legal Byte für Byte wie die
  Ubuntu-Fassungen vorher, keine `.ubuntu`-Dateien und keine Umlenkungen mehr, nur noch der statoverride von
  `50-motd-news` (70-sicherheit), die vier Skripte wieder 0755, Verweise weg, die Begrüssung wieder «Welcome to Ubuntu»
  mit ESM-Hinweis, `dpkg --verify` sauber, `zenos-sicherheitsquelle` → «distro_id=Ubuntu». install.sh danach:
  «Kennung bleibt Ubuntu: bewusst Ubuntu seit …», `0 Änderungen`; `zen doctor` Hinweis. `zenos-kennung einrichten`
  stellt zurück und hebt den Merker auf.
- **Image-Modus** (`install.sh --image` als root im Container, danach der Prüfschritt `check_identity` aus
  `image/bauen.sh` mit `env -i` statt chroot): Kennung umgestellt, zweiter Lauf `0 Änderungen`, Prüfschritt ✓
  («Kennung: zenOS 0.1.0-rc2-18-ge1ee578 · Basis Ubuntu 26.04.1 LTS · Codename resolute», «Sicherheitsquelle:
  erlaubt …»); nach `zenos-kennung ubuntu --ohne-merker` bricht er ab («Umlenkung von /usr/lib/os-release fehlt»).
  Ein ganzer Image-Bau mit `bauen.sh` lief nicht (Download, Quickshell-Bau und xz dauern im Container rund eine
  Stunde).
- **Rollback:** install.sh aus einem Klon von `v0.1.0-rc2` über den neuen Stand: Kennung bleibt («zenOS
  0.1.0-rc2-18-ge1ee578», `zenos-kennung pruefen` → eingerichtet), Programm, Hook und 51 bleiben, eine Warnung aus
  00-vorbereitung des alten Stands. Zurück auf den neuen Stand, dann `0 Änderungen`.
- **Einheitentest** `test/einheiten/kennung.test.py`: 32 Tests (Erzeugen, Texte, Hook, Aufruf, Durchlauf in einer
  Testwurzel mit einrichten → erneuern → Release-Upgrade → ubuntu → einrichten, unterbrochener Rückweg, fremder
  statoverride, ohne 51, ohne update-notifier). Als root alle grün, als `tester` und auf dem Mac ohne den Durchlauf.
  `scripts/pruefen.sh` (ohne `start`, shellcheck und nodejs im Wegwerf-Container nachinstalliert): alles sauber.

## Am Gerät prüfen

- Nach `zen update`: Im Install-Log der Abschnitt 72-kennung mit den Umlenkungen, ohne Warnung; ein zweiter Lauf
  `0 Änderungen`. `zen doctor`: Abschnitt «Systemkennung» ohne Fehler, in «Sicherheit»
  «Ubuntu-Sicherheitsquelle erlaubt … distro_id=zenOS».
- Textkonsole (Ctrl+Alt+F2): «zenOS 0.1.0-… <rechner> tty1».
- Anmeldung per SSH: erste Zeile «zenOS … · Basis Ubuntu 26.04.1 LTS · Kernel …», keine Zeilen zu docs.ubuntu.com,
  Landscape oder Ubuntu Pro, «N updates can be applied» bleibt; beim ersten Mal der Text aus `/etc/legal`.
- `hostnamectl` → «Operating System: zenOS …»; `lsb_release -a` → «Distributor ID: zenOS», «Codename: resolute».
- Einstellungen › System: `zen version` mit «Basis Ubuntu 26.04.1 LTS».
- `sudo apt update && sudo apt upgrade` ohne Rückfrage; `zen apps status` (Chrome, VS Code, 1Password) unverändert.
- Nach 24 h: `/var/log/unattended-upgrades/unattended-upgrades.log` mit «Allowed origins … o=Ubuntu,a=resolute-security»
  und, falls Updates anstanden, mit Ubuntu-Paketen.
- Beim Start: Meldungen der initrd («Ubuntu» bis zum nächsten Kernel-Update möglich, das initrd wird nicht neu
  gebaut) und der erste Start eines Images mit und ohne Imager (cloud-init mit `ID=zenos`).
- Rückweg einmal ausprobieren: `sudo zenos-kennung ubuntu`, `lsb_release -is` → Ubuntu, `zen doctor` Hinweis
  «bewusst», dann `sudo zenos-kennung einrichten`.
