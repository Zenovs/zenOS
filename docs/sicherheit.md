# Sicherheit

Grundsatz 1: Sicherheit ist Standard und geht vor Design und Bequemlichkeit. Sie wird übernommen, nicht selbst erfunden.

## Unterbau

- Nur LTS-Versionen von Ubuntu. Sicherheitsupdates laufen automatisch (`unattended-upgrades`). Die übrigen
  Paket-Updates innerhalb von Ubuntu 26.04 LTS bringt `zen update` als zweiten Schritt (Abschnitt «Basis-Updates»
  unten); ein Wechsel der Hauptversion ist gesperrt.
  - **Ubuntu-Quellen fest erlaubt:** Die Vorgabe des Pakets (`50unattended-upgrades`) nennt die Ubuntu-Quellen nur
    über `${distro_id}`, etwa `${distro_id}:${distro_codename}-security`. `${distro_id}` kommt aus `lsb_release -is`,
    also aus ID und NAME in `/etc/os-release`. Meldet os-release einmal eine andere Kennung als Ubuntu (etwa «zenOS»), erlaubte
    unattended-upgrades keine Ubuntu-Quelle mehr, spielte kein einziges Sicherheitsupdate ein und meldete trotzdem
    Erfolg (im Container nachgestellt: 0 statt 8 Pakete, darunter openssl). Deshalb erlaubt
    `/etc/apt/apt.conf.d/51zenos-ubuntu-quellen` (Quelle `system/apt/`) die vier Ubuntu-Quellen der Vorgabe mit dem
    festen Origin «Ubuntu», unabhängig von os-release. Die Datei bleibt auch bei `zen rollback` auf einen älteren
    Stand liegen (install.sh entfernt keine Dateien, die es nicht kennt). Dazu `DevRelease "false"`: zenOS läuft nur
    auf veröffentlichten LTS-Versionen, und mit einer anderen Kennung warnte jeder Lauf, weil distro-info sie nicht
    kennt.
  - **Prüfung mit der Logik von unattended-upgrades:** `scripts/bin/zenos-sicherheitsquelle` lädt
    `/usr/bin/unattended-upgrade` als Modul und fragt dessen eigene Funktionen, ob die Paketlisten von «Ubuntu
    <codename>-security» erlaubt sind (nur lesend, ohne Root-Rechte). `zen doctor` meldet «nicht erlaubt» als Fehler.
    Eine andere os-release lässt sich vorab prüfen, bevor sie gilt:
    `LSB_OS_RELEASE=<datei> /opt/zenos/scripts/bin/zenos-sicherheitsquelle`.
  - **Systemkennung zenOS nur mit Nachweis:** Seit `72-kennung` meldet os-release `ID=zenos`. Vor jeder Umstellung
    prüft install.sh die neue os-release mit `zenos-sicherheitsquelle`; ohne Nachweis bleibt die Kennung Ubuntu, und
    liesse unattended-upgrades die Ubuntu-Sicherheitsquelle mit zenOS einmal nicht mehr zu, stellt install.sh auf
    Ubuntu zurück. `image/bauen.sh` baut kein Image ohne diesen Nachweis. Ein apt-Hook übernimmt nach jedem apt-Lauf
    die Codenamen von Ubuntu (`docs/module/kennung.md`). Das Programm dafür führt root aus (auch im Hook); es liegt
    deshalb als root-eigene Kopie unter `/usr/local/sbin`, und `zen doctor` prüft, dass niemand sonst es ändern kann.
  - **Schutz vor autoremove:** Pakete, die zenOS braucht, aber Ubuntu schon über ein Metapaket mitgebracht hat (ufw,
    unattended-upgrades, jq, polkitd …), führt apt als «automatisch installiert». Fiele das Metapaket weg, entfernte
    `apt autoremove` sie mit. install.sh markiert deshalb alle Pakete aus `scripts/pakete/*.txt` (ausser den
    Build-Abhängigkeiten von Quickshell) als manuell installiert; `zen doctor` warnt, wenn ufw oder
    unattended-upgrades wieder «automatisch» sind.
- Ubuntu Server holt ab Werk Nachrichten, ohne dass jemand etwas tut. zenOS schaltet beide ab, ohne Conffiles von
  Paketen zu ändern (`scripts/module/70-sicherheit.sh`, `zen doctor` prüft es):
  - **motd-news** (Quelle base-files, Einstellung in `motd-news-config`): Ein Timer ruft zweimal täglich
    `motd.ubuntu.com` auf und schickt im User-Agent Ubuntu-Version, Kernel, Architektur und `cloud_id` mit. zenOS
    maskiert `motd-news.timer` und `motd-news.service` und legt `/etc/update-motd.d/50-motd-news` mit
    `dpkg-statoverride … root root 0644` still. `/etc/default/motd-news` bleibt unberührt (ein geändertes Conffile
    hielte unattended-upgrades bei einem Update an); ein früher gesetztes `ENABLED=0` bleibt stehen.
  - **apt-news** (`ubuntu-pro-client`): holt bei `apt update` höchstens einmal täglich
    `motd.ubuntu.com/aptnews.json`. zenOS setzt `pro config set apt_news=false`, nur wenn der Client installiert ist.
  - Rückgängig: `sudo systemctl unmask motd-news.timer motd-news.service`,
    `sudo dpkg-statoverride --remove /etc/update-motd.d/50-motd-news` mit
    `sudo chmod 755 /etc/update-motd.d/50-motd-news` (und `ENABLED=1`, falls dort 0 steht) bzw.
    `sudo pro config set apt_news=true`. `install.sh`
    schaltet beides beim nächsten Lauf wieder ab; dauerhaft nur, wenn `_sicherheit_nachrichten` aus
    `modul_system` in `scripts/module/70-sicherheit.sh` entfernt wird.
  - Es bleiben die Verbindungen, die Updates holen: der signierte Kanal von zenOS (unten), apt (auch die
    Basis-Updates über `zenos-basis`, `docs/image-und-releases.md`) und `unattended-upgrades` und
    `esm-cache` von `ubuntu-pro-client` (snapd nur, solange eigene Snaps es halten, siehe unten). Dieser fragt bei `apt update` `contracts.canonical.com` nach verfügbaren
    Diensten (mit Architektur, Serie, Kernel und Virtualisierung, das Ergebnis wird zwischengespeichert) und lädt
    Paketlisten von `esm.ubuntu.com`. Ob er auch abgeschaltet werden soll, ist offen (`docs/module/m11.md`).
  - `apport` sammelt Absturzberichte nur lokal; gesendet wird erst mit `ubuntu-bug` (whoopsie gehört nicht zu
    Ubuntu Server).
  - **Neue Ubuntu-Versionen:** Die Begrüssung (`91-release-upgrade`, auch `update-notifier-motd.timer`) und
    `do-release-upgrade` fragten `changelogs.ubuntu.com` nach einer neuen Version. zenOS setzt `Prompt=never` über den
    Drop-in `/etc/update-manager/release-upgrades.d/zenos.cfg` (`scripts/module/71-basis.sh`, die Conffile
    `/etc/update-manager/release-upgrades` bleibt unberührt); danach fragt keiner mehr, und `do-release-upgrade` lehnt
    ab. Ein Wechsel der Ubuntu-Basis ist eine neue zenOS-Hauptversion mit neuem Image (`docs/image-und-releases.md`,
    «Basiswechsel»). Rückgängig: die Datei löschen; install.sh legt sie beim nächsten Lauf wieder an.
- **Automatische Verbindung des Kanals (Regel 8, Entscheid Zeno: ab Werk an):** `zenos-kanal.timer` holt 10–20
  Minuten nach dem Start und danach alle 6 Stunden über `zenos-kanal-holen.service` (flüchtiger Systembenutzer ohne
  Rechte, Sandbox) die Tags `v*` und den Branch `dev` von origin, also `github.com` (die https-Adresse aus
  `/opt/zenos/.git/config`). Das ist ein gewöhnlicher `git fetch` ohne Zugangsdaten: GitHub sieht die IP-Adresse, die
  Zeit und die git-Version im User-Agent, sonst nichts über das Gerät; gesendet wird nichts. Installiert wird danach
  nur Gültiges zum eingestellten Zeitpunkt (unten, «Signierte Releases»). Das gilt auch für ein frisch geflashtes
  Image: Es folgt ab dem ersten Start dem Kanal seines Tags (`stabil` oder `vorschau`). Ausschalten:
  `sudo zen kanal automatik aus` (Timer aus, `install.sh` lässt sie aus); `zen update` holt dann nur noch von Hand.
- **Automatische Verbindung der Basis-Updates (Regel 8, Entscheid Zeno: ab Werk an):** `zenos-basis-automatik.timer`
  startet 30–40 Minuten nach dem Start und danach alle 6 Stunden `apt-get update` (`zenos-basis-pruefen.service`):
  dieselben Paketquellen, die apt-daily ohnehin täglich fragt (Ubuntu-Spiegel, die Herstellerquellen, über esm-cache
  auch contracts.canonical.com), nur öfter; gesendet wird nichts über das Gerät. Installiert wird danach nur eine Liste
  ohne Kernel, Firmware, Bootloader und Entfernungen, zum Zeitpunkt des Kanals, nur am Netzteil oder ab 50 % und nie,
  solange jemand per SSH angemeldet ist. Derselbe Notschalter `sudo zen kanal automatik aus` schaltet auch diese Timer
  aus; `zen update` prüft dann nur noch von Hand.
- **Ohne snapd und landscape-common** (Regel 8, `scripts/module/22-aufraeumen.sh`): snapd ist Store-Software, die von
  selbst ins Netz geht, deshalb entfernt zenOS es samt landscape-common (nur die Marke Landscape, ohne Funktion) und
  sperrt snapd mit `/etc/apt/preferences.d/zenos-ohne-snapd` (Priorität -10), damit apt es nie als Empfehlung
  zurückbringt. Entfernt wird nur, was apt als automatisch installiert führt, und nie mehr als diese beiden samt ihren
  eigenen Teilen (vorher ein Probelauf). Sind eigene Snaps installiert, bleibt snapd mit einer Warnung; `~/snap` fasst
  zenOS nie an. Einzelheiten und Rückweg in `docs/module/m11.md`.
- Die Firewall (`ufw`) ist standardmässig an. Ausschalten geht nur bewusst und nur mit Passwort (siehe
  «Firewall» unten). SSH nur mit Schlüssel ist das Ziel; zenOS ändert die SSH-Konfiguration nicht.
- Festplattenverschlüsselung: auf dem Bürorechner Pflicht. Auf dem Pi ist sie das Ziel; in 0.1 noch nicht umgesetzt (offen).
- Secure Boot: auf dem Bürorechner aktiv. Auf dem Pi bewusst nicht, weil dort Schlüssel dauerhaft in den Chip geschrieben werden.
- Backups sollen automatisch und verschlüsselt auf einen eigenen Server oder ein NAS laufen (Ziel, in 0.1 noch nicht umgesetzt).
  Bis dahin sichert man vor einem Wechsel der Ubuntu-Basis von Hand auf einen eigenen Datenträger, nie auf ein Ziel im
  Netz (`docs/image-und-releases.md`, «Basiswechsel»).

## Firewall

Der Laptop ist unterwegs in fremden WLANs. Deshalb ist die Firewall ab Werk an und bleibt es, bis Zeno sie
bewusst ausschaltet.

**Regeln** (`scripts/module/70-sicherheit.sh`, ufw von Ubuntu):

- Eingehend verweigern, ausgehend erlauben, weitergeleitet verweigern. IPv4 und IPv6.
- SSH (22/tcp) nur aus lokalen Netzen: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, fe80::/10, fd00::/8. Mit
  `limit`: Je Adresse lässt ufw in 30 s fünf neue Verbindungen zu und weist die sechste ab (gegen Durchprobieren;
  im Container gemessen). Eine Verbindung, die beim Einschalten schon läuft, zählt dabei einmal mit. Wer viele
  SSH-Verbindungen kurz nacheinander öffnet (Skripte, manche Editoren), nutzt auf dem Mac besser `ControlMaster`.
- Was ufw ab Werk durchlässt (`/etc/ufw/before*.rules`), bleibt: bestehende Verbindungen, DHCP (v4 und v6), mDNS
  (`.local`-Namen), UPnP-Suche, ICMP und die IPv6-Nachbarsuche. Eigene Regeln (`sudo ufw allow …`) bleiben.
- SSH über ein VPN (z. B. Tailscale aus 100.64.0.0/10) oder aus dem Internet kommt nicht durch. Das gilt auch für
  öffentliche IPv6-Adressen im eigenen Netz: Löst der Name des Geräts auf dem Mac auch zu einer solchen auf (möglich,
  sobald das Netz IPv6 hat), verwirft die Firewall den Versuch still, und `ssh` wartet rund eine Minute, bevor es
  IPv4 nimmt (Entscheidung offen, `docs/module/m11.md`).

**Standardmässig an:** `install.sh` (auch bei `zen update`) legt zuerst die SSH-Regeln an und schaltet erst dann
ein, über den Helfer `scripts/bin/zenos-firewall standard`. Der Helfer prüft vorher, ob jede laufende
SSH-Verbindung erlaubt bleibt (`ss`), ob sshd nur auf Port 22 läuft und ob alle SSH-Regeln da sind; sonst bleibt die
Firewall aus und `install.sh` warnt. Bestehende Verbindungen laufen beim Einschalten weiter (im Container mit einer
offenen SSH-Verbindung geprüft). Im Image-Modus setzt `install.sh` nur `ENABLED=yes`; `ufw.service` lädt die Regeln
beim ersten Start, vor dem Netz.

**Bewusst ausschalten:** über den Schalter «Firewall» in den Einstellungen (System) oder mit
`zen firewall deaktivieren`. Dann steht in `/var/lib/zenos/firewall` (root, 0644) `zustand=aus` mit Zeitpunkt, und
`install.sh` und `zen update` lassen die Firewall aus. Wieder einschalten (Schalter oder `zen firewall aktivieren`)
schreibt `zustand=an`. Fehlt die Datei, gilt der Standard: an. Ein direktes `sudo ufw disable` hält nur bis zum
nächsten `zen update`. Jeder Wechsel über den Helfer steht im Journal (`journalctl -t zenos-firewall`), mit dem Weg
(Einstellungen über pkexec oder sudo). `zen doctor` warnt, solange die Firewall aus ist.

**Schalter in den Einstellungen:** Die Oberfläche startet `pkexec /opt/zenos/scripts/bin/zenos-firewall ein|aus`
(Argumentliste, keine Shell). Die polkit-Aktionen in `system/polkit/org.zenos.firewall.policy`
(→ `/usr/share/polkit-1/actions/`):

| Aktion | aktive Sitzung am Gerät | inaktive Sitzung | sonst (z. B. SSH) |
|---|---|---|---|
| `org.zenos.firewall.einschalten` | ja, ohne Passwort | nein | nein |
| `org.zenos.firewall.ausschalten` | nur mit Passwort (`auth_admin`), jedes Mal | nein | nein |

`auth_admin` statt `auth_admin_keep`: polkit merkt sich die Anmeldung nicht, jedes Ausschalten fragt neu. Aus einer
SSH-Sitzung geht der Schalter nicht; dort gilt `zen firewall` mit sudo. Grenze: Programme der systemd-Benutzerinstanz
(dort läuft auch die Oberfläche) ordnet polkit der Sitzung am Gerät zu, auch wenn sie aus SSH mit
`systemd-run --user` gestartet wurden. Dann geht Einschalten ohne Passwort, und Ausschalten öffnet den Dialog am
Gerät; das Passwort muss trotzdem dort eingetippt werden. Der Helfer läuft als root, nimmt nur
`ein`, `aus`, `standard` oder `pruefen` an, hat einen festen `PATH` und lädt seine gemeinsamen Teile
(`scripts/lib/firewall.sh`) nur, wenn sie root gehören und nur für root schreibbar sind. Es läuft immer nur ein
Wechsel zugleich (`flock` auf `/run/zenos-firewall.lock`), damit sich Schalter, `zen firewall` und `install.sh` nicht
überholen. `pkexec` ist dafür installiert (Paket von Ubuntu); es ist ein setuid-Programm und vergrössert die
Angriffsfläche etwas.

**Lüfter im System-Menü:** Die Oberfläche startet `pkexec /opt/zenos/scripts/bin/zenos-luefter auto|1|2|3|4`
(Argumentliste, keine Shell). Die polkit-Aktion in `system/polkit/org.zenos.luefter.policy` (→
`/usr/share/polkit-1/actions/`, Modul `80-argon`):

| Aktion | aktive Sitzung am Gerät | inaktive Sitzung | sonst (z. B. SSH) |
|---|---|---|---|
| `org.zenos.luefter.setzen` | ja, ohne Passwort | nein | nein |

Ohne Passwort, weil die Wahl harmlos ist: Eine Mindeststufe macht den Lüfter höchstens lauter, nie leiser als
automatisch, und die Leitplanken stehen im Code von `zenos-argon`, nicht im Wunsch. Eine Passwortfrage für «Lüfter auf
Stufe 2» wäre Lärm und gewöhnte daran, das Passwort ohne Lesen einzutippen. Die Aktion hat keine `exec.argv1`-Angabe
(sie gilt für jeden Aufruf des Helfers); der Helfer selbst nimmt nur `auto`, `1` bis `4` und `status` an, hat einen
festen `PATH`, schreibt nur `/var/lib/zenos/luefter` (atomar, 0644) und trägt jeden Wechsel ins Journal ein
(`journalctl -t zenos-luefter`, mit Weg und uid). Aus SSH geht es mit `zen luefter` und sudo. Für Programme der
systemd-Benutzerinstanz gilt dieselbe Grenze wie bei der Firewall: polkit ordnet sie der Sitzung am Gerät zu.

**Updates in den Einstellungen** (System › Updates): Die Oberfläche startet
`pkexec /opt/zenos/scripts/bin/zenos-kanal-bedienen pruefen|installieren ZIEL|zustimmen OBJEKT|zeitpunkt …`, für die
Ubuntu-Basis `basis-pruefen|basis-installieren HASH|basis-installieren-zustimmen HASH` (Argumentliste, keine Shell).
Die polkit-Aktionen in `system/polkit/org.zenos.kanal.policy` (→ `/usr/share/polkit-1/actions/`, Modul `14-kanal`):

| Aktion | jeder Prozess des Benutzers, solange seine Sitzung am Gerät aktiv ist (auch gesperrt) | inaktive Sitzung | ohne Sitzung am Gerät |
|---|---|---|---|
| `org.zenos.kanal.pruefen` | ja, ohne Passwort | nein | nein |
| `org.zenos.kanal.installieren` | ja, ohne Passwort | nein | nein |
| `org.zenos.kanal.zeitpunkt` | ja, ohne Passwort | nein | nein |
| `org.zenos.kanal.zustimmen` | nur mit Passwort (`auth_admin`), jedes Mal | nein | nein |
| `org.zenos.kanal.basis-pruefen` | ja, ohne Passwort | nein | nein |
| `org.zenos.kanal.basis-installieren` | ja, ohne Passwort | nein | nein |
| `org.zenos.kanal.basis-zustimmen` (`basis-installieren-zustimmen`) | nur mit Passwort (`auth_admin`), jedes Mal | nein | nein |

«Aktive Sitzung am Gerät» heisst nicht «nur die Oberfläche»: logind lässt die Sitzung auch bei gesperrtem Bildschirm
aktiv, und polkit ordnet Prozesse des Benutzerdienstes (systemd `--user`) dieser Sitzung zu. Wer per SSH als derselbe
Benutzer angemeldet ist (gestohlener Schlüssel, Code in einer tmux-Sitzung), erreicht die Aktionen ohne Passwort über
`systemd-run` im Benutzerdienst und `pkexec`, solange die Sitzung am Gerät aktiv ist (Prüfung, selbst nachgestellt).
Direkt aus SSH ohne diesen Umweg verweigert pkexec (Exit 127). Was das öffnet, ist begrenzt: prüfen, den angezeigten,
schon geprüften und signierten Stand installieren, die geprüfte Paketliste der Ubuntu-Basis ohne Kernel, Firmware,
Bootloader und Entfernungen installieren und den Zeitpunkt setzen, also die Automatik auf «von Hand» stellen oder
sie auf «jederzeit» vorziehen. Eine Änderung des Zeitpunkts, die nicht aus den Einstellungen kam, meldet
die Oberfläche deshalb als Mitteilung mit dem Weg (pkexec oder sudo, uid). Eine Schleife mit «prüfen» kann die
Automatik aufhalten, nichts installieren. Den Aufrufer an der cgroup von `zenos-shell.service` festzumachen, wäre
nicht dicht und unterbleibt. Das Abschalten der Automatik («von Hand») bleibt nach Zenos Entscheid ohne Passwort.

- **Ohne Passwort** (Entscheid Zeno): «Jetzt prüfen» holt und prüft nur. «Jetzt installieren» startet
  `zenos-kanal-jetzt@ZIEL.service`: wie `zen update`, aber ohne Frage und ohne neues Holen, nur für genau den Stand,
  den die Einstellungen zeigten (sein Tag-Objekt, auf dev der Commit). Installiert wird nur ein gültig signierter,
  schon geprüfter Stand, der kein «ja» braucht; was eines bräuchte (unsigniert, Firewall, Netz, Boot, gesperrt,
  Rückschritt) oder ein anderes Ziel wäre, bleibt liegen. Ein Angreifer mit Zugriff auf die Sitzung gewinnt damit nichts, was nicht ohnehin signiert ist. Der
  Zeitpunkt nimmt nur `sperre`, `fenster VON BIS` (HH:MM, streng geprüft, mindestens eine Stunde), `jederzeit` und
  `hand` an; Signatur und Rückfrage gelten bei jeder Wahl, und auf `dev` kommt nie etwas automatisch. Er gilt für das
  ganze Gerät, weil die Automatik als root ihn liest.
- **Mit Passwort:** «Zustimmen …» erscheint nur, wenn ein gültig signierter Stand Firewall, Netz oder Boot ändert. Es
  startet `zenos-kanal-zustimmen@OBJEKT.service`: das «ja» für genau das Tag-Objekt, das die Einstellungen zeigten,
  ohne neues Holen. Nennt die Prüfung inzwischen ein anderes Objekt, geschieht nichts. Unsigniertes, `dev` und
  Rollbacks bleiben beim Terminal (`zen update`, `zen rollback` mit getipptem «ja»); das prüft zenos-kanal selbst
  (`nur_signiert` im Wunsch), nicht erst die Oberfläche.
- **Ubuntu-Basis** (Entscheid Zeno, Oktober 2026): «Jetzt prüfen» (`basis-pruefen`) startet
  `zenos-basis-pruefen.service` (`apt-get update`, Auswertung, installiert nichts; ein unterbrochenes dpkg holt es
  vorher mit `dpkg --configure -a` nach, wie unattended-upgrades täglich: nur was schon entpackt war). «Jetzt installieren»
  (`basis-installieren HASH`, ohne Passwort) installiert genau die angezeigte Liste: HASH (40 Zeichen `0-9a-f`) muss
  zur letzten Prüfung und zu einer Auswertung von jetzt passen, ohne neues `apt-get update`, sonst Exit 3. Enthält die
  Liste Kernel, Firmware, Bootloader oder Entfernungen, lehnt die Unit ab (Exit 10); dafür gibt es «Mit Passwort
  installieren» (`basis-installieren-zustimmen HASH`, `auth_admin` bei jedem Aufruf). Ohne Passwort, weil die Pakete
  von Ubuntu bzw. den Herstellern signiert und von apt geprüft sind und dieselben auch über `zen update` und die
  Automatik kämen; wer über den Umweg `systemd-run` an `allow_active` kommt, kann so nur früher installieren, was
  ohnehin ansteht. Ein geschütztes Paket entfernt zenOS nie, auch nicht mit Passwort.
- Die Arbeit machen Units, nicht der Helfer: Lädt die Oberfläche neu oder endet die Sitzung, läuft die Installation zu
  Ende. Der Helfer hat einen festen `PATH`, nimmt nur diese Wörter an (das Objekt nur als 40 Zeichen `0-9a-f`) und
  trägt jeden Aufruf ins Journal ein (`journalctl -t zenos-kanal-bedienen`, mit Weg und uid; der Zeitpunkt unter
  `-t zenos-kanal`). Für Programme der systemd-Benutzerinstanz gilt dieselbe Grenze wie bei der Firewall.

## polkit-Agent

Die Oberfläche ist der polkit-Agent der Sitzung (`shell/polkit/Polkit.qml`, `Quickshell.Services.Polkit`). Er
zeigt den Passwortdialog, wenn ein Programm Rechte verlangt, die polkit nur nach einer Anmeldung gibt: den Schalter
«Firewall», später auch andere (etwa NetworkManager).

- **Was er sieht:** die Nachricht und die Kennung der Aktion (aus den Dateien unter `/usr/share/polkit-1/actions/`,
  die nur root ändern kann), die Konten, die bestätigen dürfen (bei Ubuntu die Gruppe `sudo`; vorgewählt ist das
  eigene) und die Frage von PAM.
- **Was er weitergibt:** das Passwort, nur an polkit (`AuthFlow.submit`). polkit prüft es in einem eigenen Prozess
  über PAM (`polkit-agent-helper-1`, Dienst `polkit-1`); zenOS erfährt nur «stimmt» oder «stimmt nicht». Das Feld
  wird beim Weiterreichen geleert, samt Rückgängig-Verlauf des Textfelds. Das Passwort steht in keiner Eigenschaft,
  wird nicht gespeichert und nie protokolliert.
- **Sperre:** Während der Sperre gibt es keine Dialoge. Eine offene Anfrage bricht beim Sperren ab, eine neue
  während der Sperre sofort; das Programm erfährt «abgebrochen». Begründung: Hinter der Sperre sieht sie niemand,
  und eine Passwortfrage gleich nach dem Entsperren verleitet dazu, das Passwort aus Gewohnheit ein zweites Mal
  einzutippen, ohne zu lesen, wofür.
- Ein Klick neben den Dialog bricht nicht ab; Esc oder «Abbrechen» schon.
- **Eine Fläche zur Zeit:** Solange der Dialog fragt, öffnen Befehlsfeld, Zentrale, Modus- und Zustand-Wahl und
  Fensterübersicht nicht, auch nicht per Wischen, Tastenkürzel oder IPC (`Oberflaeche.polkitOffen`). Sonst nähme eine
  zweite exklusive Fläche dem Dialog die Tastatur, und der Rest des Passworts landete dort, in der Übersicht lesbar im
  Filter. Ist eine von ihnen schon offen, wenn polkit fragt, schliesst sie.

## Oberfläche

- Der Sperrbildschirm nutzt `ext-session-lock`. Stürzt die Oberfläche ab, bleibt der Bildschirm gesperrt.
- Die Anmeldung läuft über PAM. zenOS verarbeitet nie selbst Passwörter. Auch der polkit-Dialog reicht das
  Passwort nur an polkit weiter (siehe «polkit-Agent»).
- Automatische Sperre bei Inaktivität und Standby. Sie ist nicht abschaltbar, und ein Programm, das den Leerlauf
  hemmt (Video), hält sie höchstens 60 Minuten ohne Eingabe auf (Abschnitt «Energie»).
- Bei Bildschirmfreigabe werden Mitteilungsinhalte immer verborgen.
- Das Befehlsfeld startet Prozesse mit Argument-Listen, nie über `sh -c`.
- **Fensterübersicht und Schreibtisch:** Der Filtertext der Übersicht wird nur mit App-Namen, Titeln und
  App-Kennungen verglichen und erreicht nie einen Prozess. Beide wirken nur über `wlr-foreign-toplevel`
  (`activate`, `minimized`), ohne Shell. Super+Tab und Super+H rufen `zenos-ipc` mit fester Argumentliste auf, ohne
  `allowWhenLocked`. Während Sperre und Einrichtung öffnet die Übersicht nie, Super+H und das Wischen wirken nicht,
  und das Sperren schliesst die Übersicht (ext-session-lock liegt ohnehin über allem). Während einer Freigabe sind
  die Fenstertitel verborgen und werden nicht durchsucht, auch in `zenos-ipc uebersicht fenster`; das ist Vorsicht
  wie «Netzname verborgen», keine neue Leitplanke. Öffnet die Übersicht, schliesst ein Menü der Leiste (samt
  WLAN-Passwortfeld), und solange polkit nach dem Passwort fragt, öffnet sie nicht. Nach dem Ausblenden ist der
  Filter leer; Getipptes bleibt nicht bis zum nächsten Öffnen stehen. Wird ein Bildschirm ab- oder angesteckt,
  schliesst sie: Ohne ihren Bildschirm bliebe sie ohne Tastatur offen, und Getipptes ginge ungesehen an das Fenster
  dahinter (etwa als Befehl in kitty).
- Die Nutzungsstatistik des Befehlsfelds speichert nur Desktop-IDs, Zähler und die Reihenfolge der zuletzt genutzten
  Apps, keine Zeiten und keine Fenstertitel (`~/.local/share/zenos/`, nur für den Benutzer lesbar).
- Eine Zwischenablage-Historie, falls sie kommt, ignoriert 1Password und löscht sich selbst.

## Energie

Bildschirm aus, Ausschalten nach langer Sperre und die Ein/Aus-Taste (`docs/module/energie.md`). Grundsatz: Energie
sparen darf die Sperre nie schwächen.

- **Dunkel heisst gesperrt:** `zenos-bildschirm aus` ruft immer zuerst `zen lock` auf (das kehrt erst bei
  bestätigter Sperre zurück) und schaltet nur dann ab. Schlägt die Sperre fehl, bleibt der Bildschirm an, der Grund
  steht im Journal. Ungesperrt nimmt die Sperre keine Meldung «aus» an, und unmittelbar vor dem Abschalten muss die
  erreichbare Sperre «aus» quittieren (sonst bleibt er an; nur ohne Oberfläche, bei der Notfall-Sperre, ohne
  Quittung). Entsperren schaltet den Bildschirm immer an, auch nach einem Neustart der Oberfläche im Dunkeln. Damit
  ist auch die Reihenfolge der swayidle-Timeouts kein Risiko.
- **Nichts verzögert die automatische Sperre:** Es gibt keinen neuen Idle-Hemmer, der Timeout der Sperre bleibt
  1–15 Minuten. Bildschirm aus und Ausschalten zählen erst ab der Sperre. zenos-idle startet nach einem Update nur
  gesperrt neu (ein Neustart beginnt die Leerlaufzeit von vorn). Neu: Auch ein Idle-Hemmer (Video) hält die Sperre
  höchstens 60 Minuten ohne Eingabe auf. Diese Höchstdauer zählt in der Oberfläche (IdleMonitor): Ein Neustart der
  Oberfläche beginnt sie von vorn, ohne Oberfläche gilt sie nicht (swayidle beachtet Hemmer). Ebenso sperrt das
  Zuklappen über die Oberfläche; läuft sie nicht, sperrt zenos-idle bei einem neuen Wechsel zu «zu». Die Grenzen
  stehen eingefroren in `LEITPLANKEN`, ein Zustand kann die Energie-Schlüssel nicht setzen (`GESPERRT`), und Tests
  gleichen die Kopien in den Shell-Helfern ab.
- **Wecktaste:** Die Taste, die einen dunklen Bildschirm weckt, landet nicht im Passwortfeld (vorher ergab sie einen
  Fehlversuch bei PAM). Verworfen wird genau eine Taste, nie mehr, damit ein hängender Zustand nie die
  Passworteingabe blockiert, und nur bis 300 ms nach dem Wecken (weckt die Maus, kommt das Passwort ganz an). Während
  der sichtbaren Vorwarnung wird nichts verworfen. Wird die Wecktaste gehalten (über 600 ms wiederholt sie der
  Client), verwirft das Passwortfeld auch ihre Wiederholungen, bis sie losgelassen wird: Ein gehaltenes Return
  prüft kein halbes Passwort, auch nicht, wenn dabei Shift, Ctrl, Alt, AltGr oder Super gedrückt wird (sie
  wiederholen sich nicht und übernehmen die Wiederholung nicht), es gibt keinen Fehlversuch. Nie eine andere Taste:
  Verworfen werden nur Wiederholungen genau dieser Taste, jede andere Taste kommt an; das Loslassen, ein neuer Druck
  derselben Taste und die Wiederholung einer anderen beenden es (`wecktasteSperre` in `shell/dienste/energie.js`,
  dieselbe Logik wie am Login). Es entsteht kein neuer Weg zu PAM: zenOS verwirft nur Tasten, bevor sie das Feld
  erreichen, das Passwort geht wie bisher nur über `PamContext` an PAM (`docs/module/energie.md`, «Gehaltene
  Wecktaste in der Sperre»).
- **Login-Bildschirm dunkel nach 1 Minute** (Zenos Entscheid vom 06.10.2026, `shell/greeter/Bildschirm.qml`): Dort
  ist niemand angemeldet, deshalb geht der Bildschirm ohne Sperre aus. Das ist die einzige Ausnahme von «dunkel heisst
  gesperrt», und sie steht nur in der Oberfläche des Logins (Benutzer `_greetd`, eigenes labwc), nicht in
  `zenos-bildschirm`, IPC oder `zen energie`. Keine neuen Rechte: `_greetd` schaltet mit wlopm nur die Ausgänge
  seines eigenen labwc (Argumentliste mit Zeitlimit, keine Shell). Die erste Taste, der erste Klick oder die erste
  Berührung weckt nur und wird verworfen (genau eine Eingabe), sie erreicht weder das Passwortfeld noch einen Knopf.
  Wird sie gehalten, verwirft das Formular auch ihre Wiederholungen, bis sie losgelassen wird, auch mit Shift, Ctrl,
  Alt, AltGr oder Super dazu; jede andere Taste kommt an. Ein neuer Bildschirm (angesteckt) weckt ohne Wecktaste,
  damit auf einem hellen Bildschirm kein Zeichen verloren geht. Das Passwort geht weiter nur über greetd an PAM. Was
  scheitert, lässt den Bildschirm an; geht ein sicher dunkler Bildschirm nicht mehr an, startet der Login neu
  (greetd). Ein kurzer Druck auf die Ein/Aus-Taste schaltet dort wie bisher aus (logind), auch wenn es dunkel ist.
- **Keine Shell:** Helfer und Aufrufe aus der Oberfläche nutzen Argumentlisten, IPC und Helfer nehmen nur feste
  Wörter an. swayidle führt seine Befehle über `sh -c` aus; zenos-idle gibt ihm deshalb nur feste, per Muster
  geprüfte Pfade mit festen Wörtern (`sperrbefehl`, `bildschirmbefehl`).
- **Ausschalten nach langer Sperre** nur mit `systemctl --no-ask-password poweroff --check-inhibitors=yes` (polkit:
  `power-off` in der aktiven Sitzung ohne Passwort), nie neu starten, nie `-i` oder `--force` (Hemmer übergehen
  bräuchte `auth_admin_keep`). `zenos-energie` prüft vorher selbst: Vorwarnung sichtbar, Marker aus diesem Start,
  60 s bis 5 Min. alt nach Laufzeit (ein Sprung der Uhr verkürzt nichts) und nur einmal gültig, verbraucht erst
  unmittelbar vor dem Ausschalten (eine Eingabe bricht bis zuletzt ab), gesperrt, keine Fern-Sitzung (logind
  `Remote=yes`) und keine SSH-Verbindung, kein tmux- oder screen-Server, keine Installation (Sperre von `install.sh`,
  nur lesend geöffnet und kurz geteilt gesperrt; keine laufende Unit `zenos-kanal-*` oder `zenos-basis-*`, laut
  systemd, denn die Sperren des Kanals sieht ein Benutzer nicht), kein apt oder dpkg, keine automatischen Updates, kein Block-Hemmer
  «shutdown», logind erlaubt es ohne Passwort (`CanPowerOff`). Was sich nicht prüfen lässt, gilt als blockiert. Jeder
  Entscheid steht mit Grund im Journal (`journalctl -t zenos-energie`). Fällt die Oberfläche aus, wird nicht
  ausgeschaltet. Am Login-Bildschirm gilt dasselbe (fest nach 30 Min. im Akkubetrieb, `shell/greeter/Leerlauf.qml`),
  statt «gesperrt» darf keine andere Sitzung offen sein.
- **Ein/Aus-Taste:** Den Hemmer «handle-power-key» darf nur die aktive Sitzung nehmen (polkit
  `inhibit-handle-power-key`: `allow_active yes`), er endet mit zenos-idle. Ohne zenos-idle (Login-Bildschirm, erste
  Sekunden nach dem Anmelden, 1 s zwischen zwei Läufen) schaltet ein kurzer Druck wie bei logind üblich sofort aus,
  ohne Vorwarnung und Wächter. Weil der Hemmer im Benutzerdienst läuft, zählt logind ihn vermutlich auch auf einer
  Textkonsole, solange die grafische Sitzung im Hintergrund läuft (dort bewirkt ein kurzer Druck dann nichts; am Gerät
  zu prüfen). Kein Drop-in in `logind.conf`, kein Eingriff ins System. Halten schaltet weiter hart aus.
- **Deckel und leerer Akku** (Argon ONE UP): Abschnitt «Hardware (Argon ONE)».
- **Keine Telemetrie:** Zustände bleiben lokal (`$XDG_RUNTIME_DIR/zenos`, `/run/zenos`,
  `~/.local/state/zenos/energie.json` mit Zeit, Minuten und Art des letzten Ausschaltens). Nichts verlässt den
  Rechner.

## Netz (NetworkManager)

Das WLAN-Menü oben rechts ist nur eine Oberfläche für den NetworkManager von Ubuntu; einen eigenen Netzwerk-Stack
hat zenOS nicht. Einzelheiten in `docs/module/netzwerk.md`.

- **Umstellen nur ausdrücklich:** `zen update` installiert NetworkManager, lässt ihn aber aus. Erst
  `zen netzwerk umstellen` stellt um, nach einem Plan und der Eingabe «umstellen», wirksam mit dem nächsten
  Neustart (CLAUDE.md, Regel 3). Zurück geht es ohne Netz mit `zen netzwerk zurueck`.
- **WLAN-Passwörter** speichert NetworkManager wie bisher netplan: im Klartext in `/etc/netplan/90-NM-<uuid>.yaml`,
  nur für root lesbar (0600). zenOS liest und schreibt sie nicht selbst. Das Passwortfeld im Menü gibt das
  Passwort nur über D-Bus an NetworkManager weiter (nie in eine Kommandozeile, ein Protokoll oder eine
  zenOS-Datei) und leert sich danach. Ein Profil, das ein abgebrochener oder gescheiterter erster Versuch angelegt
  hat, vergisst das Menü wieder. `zen doctor` warnt, wenn eine Datei unter `/etc/netplan` mehr als root lesen darf.
- **Sicherungen enthalten Passwörter:** `zen netzwerk umstellen` sichert die bisherigen netplan-Dateien samt
  WLAN-Passwörtern nach `/var/lib/zenos/netplan-vorher/<zeit>/`, und `zen netzwerk zurueck` legt dort auch die
  Profile von NetworkManager ab (`nachher-<zeit>/`), also auch Passwörter von Netzen, die im Menü längst vergessen
  sind. Nur root kann sie lesen (Ordner 0700, Dateien 0600). zenOS räumt sie nicht selbst weg; wer sie nicht mehr
  braucht, löscht sie mit `sudo rm -r /var/lib/zenos/netplan-vorher/<zeit>` (danach geht `zurueck` nicht mehr).
- **Offene Netze nur auf Klick:** Verbindet Zeno ein neues offenes Netz (auch OWE), bekommt sein Profil gleich
  «autoconnect: nein». Sonst verbände sich NetworkManager später überall von selbst mit jedem Zugangspunkt
  gleichen Namens («Free WiFi», Hotel), auch mit einem nachgemachten.
- **Netznamen sind fremder Text:** Der Name eines Netzes kommt ungeprüft aus der Luft. Das Menü zeigt ihn nur als
  reinen Text (keine Auszeichnungen, keine Bilder) und macht Unsichtbares darin sichtbar («�»), damit ein
  nachgemachtes Netz nicht genau wie ein bekanntes aussieht.
- **Rechte:** keine eigene polkit-Regel. Ubuntus Regel erlaubt lokalen, aktiven Sitzungen von Mitgliedern der
  Gruppe `sudo` (oder `netdev`), Netzprofile anzulegen, zu ändern und zu löschen. Suchen und Verbinden erlaubt
  NetworkManager jeder lokalen Sitzung, auch einer inaktiven, WLAN an/aus jeder aktiven (Vorgaben der
  NetworkManager-Policy, im Container nachgelesen). Damit darf jeder Prozess in Zenos Sitzung
  Netzprofile ändern, wie auf jedem Ubuntu-Desktop. Das gilt auch für Prozesse ohne eigene Sitzung, etwa
  Benutzerdienste: polkit nimmt für sie Zenos grafische Sitzung. Direkt in einer SSH-Sitzung verlangt
  NetworkManager das Passwort, über die Benutzerinstanz (`systemd-run --user …`) aber nicht. Wer sich als Zeno per
  SSH anmeldet, etwa mit einem gestohlenen Schlüssel, kann also ohne sudo-Passwort Netzprofile anlegen oder ändern
  (DNS, Routen), solange Zeno grafisch angemeldet ist. Eine engere Regel liesse sich unter einem Benutzer kaum
  nach Aufrufer unterscheiden; der Schutz ist der SSH-Schlüssel selbst.
- **Keine Konnektivitätsprüfung:** Ubuntus Paket dafür (`network-manager-config-connectivity-ubuntu`) fragte
  regelmässig bei `connectivity-check.ubuntu.com` nach. zenOS installiert NetworkManager ohne Empfehlungen, also
  ohne dieses Paket; `zen doctor` warnt, falls es doch da ist.
- **WPA3 aus (Raspberry Pi):** Der WLAN-Chip bricht WPA3 ab, und NetworkManager versuchte es bei WPA2/WPA3-
  Mischnetzen trotzdem. `zen netzwerk umstellen` schaltet WPA3 deshalb im Treiber ab
  (`/etc/modprobe.d/zenos-brcmfmac.conf`) und sagt es vorher im Plan. Mischnetze verbinden dann über WPA2-PSK. Das
  ist schwächer als WPA3: Wer die Anmeldung mitschneidet, kann das Passwort offline raten. Ein langes, zufälliges
  WLAN-Passwort hält das aus. Reine WPA3-Netze gehen mit diesem Chip ohnehin nicht.
- **Leitplanken:** Während einer Bildschirmfreigabe zeigt das Menü keine Netznamen (sie verraten Orte). Während
  der Sperre sind die Menüs der Leiste zu.

## Hardware (Argon ONE)

Schreibzugriffe auf Hardware gibt es nur im Systemdienst `zenos-argon` (Einzelheiten in `docs/module/m13.md`). Er
läuft als root, aber gehärtet: nur I2C- und GPIO-Geräte, kein Netz, System nur lesbar, geschrieben wird nur
`/run/zenos` und unter `/sys` nur `/sys/devices/virtual/thermal` (Thermal-Zonen und Kühler, für die Mindeststufe des
Lüfters; `ReadWritePaths` als Ausnahme von `ProtectKernelTunables`, im Container mit der vollen Härtung geprüft: der
Rest von `/sys` bleibt nur lesbar). Firmware-Einstellungen (`/boot/firmware/config.txt`, EEPROM) fasst zenOS nie an.

- **Argon ONE V3 (Pi 5):** Lüfterwert über I2C an 0x1a und beim Ausschalten das Abschaltsignal an die Platine.
- **Argon ONE UP (Compute Module 5): Akku-Messchip CW2217 an 0x64.** Ab Werk schläft der Chip und hat kein
  Akkuprofil, er meldet dann 0 %. zenOS weckt ihn und schreibt Argons Akkuprofil hinein, genau wie Argons eigene
  Software, aber erst nach Zenos ausdrücklicher Freigabe: `zen akku freigeben` erklärt den Schreibzugriff und legt
  nach der Eingabe «freigeben» `/etc/xdg/zenos/argon-akkuprofil` an (nur root kann das). Ohne diese Datei liest
  zenos-argon den Chip nur; `zen update` allein schreibt nie in den Chip. `zen akku sperren` nimmt die Freigabe
  zurück. Auch mit Freigabe gilt:
  - nur die Register, die auch Argon beschreibt: 0x08 (Steuerung: wecken, schlafen legen, aktivieren), 0x0A
    (Interrupts aus), 0x0B (Profil geladen) und 0x10–0x5F (Argons Profil, 80 Byte, im Code fest hinterlegt);
  - nur wenn nötig: Erst wird gelesen; ist der Chip aktiv und das Profil gleich, schreibt zenOS nichts. Höchstens
    dreimal pro Stunde, mit wachsender Pause nach Fehlern;
  - kein Absuchen des Busses und keine anderen Adressen (die Erkennung liest nur die Chip-ID an 0x64);
  - nichts, solange Argons eigener Dienst (`argononeupd.service`) aktiviert ist.

  Risiko: gering. Der Chip misst nur, er steuert weder Laden noch Strom noch das Abschalten. Ein falsches Profil
  ergäbe höchstens falsche Prozentwerte; ein erneutes Laden behebt es.
- **Argon ONE UP: Deckel an GPIO27, nur lesend.** zenos-argon fordert die Leitung als Eingang mit Pull-up und beiden
  Flanken an (wie Argons Software) und gibt sie beim Beenden frei. Es schreibt keinen Pegel, kein I2C, keine Firmware,
  kein `config.txt`. Der Wechsel geht über `/run/zenos/geraet.json` (nicht vertraulich) an die Oberfläche, die beim
  Zuklappen sofort sperrt (Leitplanke, nicht abschaltbar) und erst danach den Bildschirm ausschaltet.
- **Argon ONE UP: Ausschalten bei leerem Akku.** zenos-argon schaltet bei 3 % mit `systemctl poweroff` aus
  (`CAP_SYS_BOOT`, wie der Power-Button des V3), nie neu und nie mit `--force`. Nur bei sicherem Messwert und sicherem
  Entladen, drei Messungen hintereinander, 60 s Vorwarnung; ein unsicherer oder fehlender Messwert führt nie zum
  Ausschalten, schon eine Messung «lädt» bricht ab. Läuft `dpkg` oder `install.sh`, wartet es höchstens 5 Min.
  Vorher meldet `wall` es allen offenen Terminals: Dafür darf der Dienst nur schreibend auf Pseudo-Terminals und
  Konsolen (`DeviceAllow=char-pts w`, `char-tty w`, Gruppe `tty` wie `wall` selbst), sonst bleibt er gehärtet.
  Gelesen wird dafür nur `/proc/*/comm`, die Sperren `/run/lock/zenos-install.lock` und
  `/run/zenos-sperre/install.lock` (install.sh als root, etwa vom Kanal; lesend geöffnet, kurz geteilt gesperrt) und
  ob `/run/zenos-kanal` besteht (der Kanal installiert, auch zwischen den Läufen von install.sh). Die Grenze steht im
  Code (`CRITICAL_PERCENT`, gespiegelt aus `LEITPLANKEN.akkuAusschaltenProzent`).
- **Lüfter einstellen (Mindeststufe).** Standard ist «auto»: Am Compute Module 5 regelt der Kernel (`step_wise`)
  allein, zenOS liest nur. Wählt Zeno eine Mindeststufe 1–4 (System-Menü oder `zen luefter`), stellt zenos-argon die
  Thermal-Zone des Lüfters auf den Regler `user_space` und setzt alle 2 s die Stufe selbst. Beim Argon ONE V3 hebt
  die Mindeststufe die Kurve auf 30 / 50 / 70 / 100 % an. Leitplanken im Code, nicht abschaltbar:
  - nie weniger Kühlung als automatisch: Stufe = max(Mindeststufe, Stufe des Kernels), die Stufe des Kernels aus
    Temperatur und Trip-Punkten der Zone mit Hysterese nachgerechnet;
  - ab 80 °C und wenn die Temperatur nicht lesbar ist, volle Stufe;
  - bei «auto», beim Beenden des Dienstes und nach jedem Schreibfehler regelt wieder der Kernel (`step_wise`), mit
    einer Stufe nicht unter der automatischen und nicht unter der beim Übernehmen (sonst hielte `step_wise` den Lüfter
    bei steigender Temperatur zu tief, `docs/module/m13.md`); endet der Dienst hart (Absturz, SIGKILL), stellt
    `ExecStopPost` (`zenos-argon --luefter-kernel`) den Regler zurück; hängt er, beendet ihn der Watchdog von systemd
    nach 30 s ohne Lebenszeichen (dann ebenso `ExecStopPost`); ein Neustart des Dienstes räumt einen verwaisten
    `user_space` zuerst auf;
  - übernommen wird nur eine Zone, die genau so am Lüfter hängt, wie zenos-argon nachrechnet (nur der Lüfter als
    Kühler, je aktiver Trip-Punkt eine Stufe). Zonen mit passiven Trip-Punkten (der Kernel drosselt dort die CPU) oder
    weiteren Kühlern übernimmt zenOS nicht, `user_space` hielte sie an. Die kritische Grenze (110 °C, Abschalten)
    behandelt der Kernel unabhängig vom Regler weiter.

  Ein «aus» gibt es nicht. Den Wunsch schreibt nur der Helfer `zenos-luefter` nach `/var/lib/zenos/luefter` (root,
  0644). Ein ungültiger Inhalt gilt als «auto».

## Gesten (Touchpad)

Wischen mit drei Fingern öffnet und schliesst die Fensterübersicht. labwc 0.9.3 bindet keine Gesten, deshalb liest
der Systemdienst `zenos-gesten` (`scripts/bin/zenos-gesten`, Modul `82-gesten`) die Touchpads mit. Grundsatz: Die
Sitzung bekommt keinerlei Rechte an `/dev/input`, und niemand kommt in die Gruppe `input`. Mit dieser Gruppe könnte
jeder Prozess der Sitzung die Tastatur und damit Passwörter mitlesen. Deshalb fallen libinput-gestures und fusuma
weg (beide brauchen die Gruppe `input` und fehlen in Ubuntu 26.04).

- **Eigener Benutzer:** `zenos-gesten` über systemd-sysusers, gesperrt, ohne Anmeldung, ohne Home und ohne weitere
  Gruppen. Niemand sonst ist in der Gruppe `zenos-gesten`; `zen doctor` meldet Mitglieder als Fehler, ebenso eine
  Sitzung in `input` oder `zenos-gesten`. Der Dienst läuft nie als root, auch der Messmodus nicht.
- **Nur reine Touchpads, nur lesen:** Die udev-Regel `72-zenos-gesten.rules` greift nur bei `ID_INPUT_TOUCHPAD=1`
  ohne `ID_INPUT_KEY` und ohne `ID_INPUT_KEYBOARD`. Dann gehört der Knoten `root:zenos-gesten` mit 0640 statt
  `root:input` mit 0660: Der Dienst darf lesen, schreiben nur root. Ein Touchpad, das auf demselben Knoten Tasten
  meldet, bleibt `root:input` und für den Dienst gesperrt (kein Wischen, Super+Tab geht). labwc öffnet die Geräte
  über logind als root und ist von den Rechten nicht betroffen (im Container mit einer Sitzung auf seat0 belegt, am
  Pi zu bestätigen). Sonst nutzt in zenOS nichts die Gruppe `input`.
- **Kein uaccess, keine ACL, kein Schreibrecht:** Schreibrecht auf einen Touchpad-Knoten reichte im Container, um
  Klicks in die Wayland-Sitzung einzuspeisen. Deshalb bekommt die Sitzung gar nichts und der Dienst nur Leserecht.
- **Tastaturen zweifach ausgeschlossen, unabhängig voneinander:**
  1. Die udev-Regel gibt die Gruppe nur reinen Touchpads; nur dann darf der Dienst den Knoten überhaupt öffnen.
  2. Der Dienst fragt nach dem Öffnen selbst den Kernel (`EVIOCGBIT`, nur lesend) statt udev: Meldet der Knoten eine
     Taste (dieselben `KEY_*`-Bereiche wie `ID_INPUT_KEY` in udev) oder fehlen Finger (`BTN_TOOL_FINGER`) oder
     Mehrfinger-Slots (`ABS_MT_SLOT`), schliesst `open_restricted` ihn sofort mit EACCES und meldet es im Journal.
     Gibt eine fremde Regel, eine hwdb-Überschreibung oder ein Bedienfehler einer Tastatur die Gruppe, liest der Dienst
     sie trotzdem nicht (im Container belegt); `zen doctor` meldet den Knoten als Fehler.

  `open_restricted` öffnet zudem nur Knoten von `root:zenos-gesten` und nur mit `O_RDONLY`. Das ist keine eigene
  Schicht, denn die Gruppe setzt dieselbe Regel. `DeviceAllow=char-input r` begrenzt nur auf Eingabegeräte und Lesen,
  Tastaturen schliesst es nicht aus. Ein Touchpad, das libinput ohne Gesten führt (etwa mit nur einem Slot), schliesst
  der Dienst gleich wieder. Er greift kein Gerät (kein `EVIOCGRAB`), labwc bekommt jede Bewegung unverändert.
- **Härtung** (`system/systemd/system/zenos-gesten.service`): `User=zenos-gesten`, leeres `CapabilityBoundingSet`,
  `NoNewPrivileges`, `DevicePolicy=closed` mit `DeviceAllow=char-input r`, `ProtectSystem=strict`, `ProtectHome`,
  `PrivateTmp`, `PrivateIPC`, `PrivateUsers=identity`, `/dev/shm` und `/var/log` unzugänglich, `IPAddressDeny=any`,
  `RestrictAddressFamilies=AF_UNIX AF_NETLINK`, Schutz von Kernel, Uhr und Protokollen, `MemoryDenyWriteExecute`,
  `SystemCallFilter=@system-service ~@privileged @resources`, `python3 -I`. Geschrieben wird nur
  `/run/zenos-gesten`. `PrivateUsers=identity` statt `yes`: Mit `yes` sähe der Dienst jeden anderen Benutzer am
  Socket als nobody und könnte nicht prüfen, wer liest. Ohne `PrivateNetwork`: udev meldet neue Geräte über netlink
  nur im Netz-Namensraum des Systems, mit `PrivateNetwork` fände der Dienst ein Touchpad nach dem Aufwachen nicht
  wieder (im Container belegt). Ins Netz kommt er trotzdem nicht (nur Unix-Sockets und netlink, keine IP-Adresse).
  `systemd-analyze security` bewertet ihn im Container mit 0.8 (offen bleiben `PrivateNetwork`, `PrivateDevices` wegen
  `/dev/input` und `AF_NETLINK`). Die Einheit hat kein `[Install]`: udev startet sie, sobald es ein reines Touchpad
  gibt; ohne Touchpad (Bürorechner) läuft er nie.
- **Ausgabe:** Der Socket `/run/zenos-gesten/gesten.sock` bekommt je Geste genau eine Zeile «oben» oder «unten»,
  sonst nichts. Der Dienst liest nie von seinen Klienten (ihre Richtung ist zu). Verbinden darf jeder (0666), bleiben
  nur der Benutzer, der an seat0 gerade aktiv ist: Der Dienst fragt den Kernel nach der uid am anderen Ende
  (`SO_PEERCRED`) und vergleicht sie mit `sd_seat_get_active` aus libsystemd. Ist an seat0 niemand aktiv, nimmt er
  nur gewöhnliche Benutzer an (uid 1000 bis 60000), nie root, Systemdienste, DynamicUser oder nobody. Alle anderen
  trennt er sofort, sie bekommen keine einzige Geste. Je Benutzer höchstens 2 Verbindungen; eine dritte verdrängt
  dessen älteste, nie die eines anderen. Insgesamt höchstens 8, darüber geht der Neue gleich wieder. So kann kein
  anderes Konto die Oberfläche hinausdrängen oder mitlesen, wann jemand am Gerät ist (im Container belegt: nobody
  flutet, die Oberfläche bekommt jede Geste). Wer nicht liest, fliegt. Die Oberfläche nimmt nur genau diese zwei
  Wörter an und ignoriert sie während Sperre und Einrichtung. Restrisiko: Ein lokales Konto kann den Dienst mit
  `connect` und `close` in einer Schleife beschäftigen (Rechenzeit), aber nicht blockieren.
- **Datenschutz:** Im Journal stehen nur Start, Touchpads dazu und weg und Fehler, keine einzelnen Gesten, keine
  Positionen, keine Gerätenamen. Der Messmodus (`--messen`, von Hand mit `sudo -u zenos-gesten …`) gibt je Geste nur
  Fingerzahl und die Summe der Bewegung aus, keine Positionen. Kein Netz, keine Telemetrie.
- **Restrisiko:** Ein kompromittierter Dienst könnte die Lage der Finger auf dem Touchpad lesen und mit verändernden
  ioctl auf den nur lesend geöffneten Knoten eingreifen, denn evdev prüft dafür kein Schreibrecht:
  - `EVIOCGRAB` blockiert das Touchpad. Dann geht es nicht mehr; Tastatur, Maus und SSH gehen weiter.
  - `EVIOCSABS` verstellt Achsbereiche und Auflösung des Touchpads im Kernel, für alle Leser einschliesslich labwc,
    bis das Gerät neu erscheint (Zeiger und Gesten verhalten sich dann falsch; im Container belegt und
    zurückgesetzt).
  - `EVIOCSKEYCODE` kann auf echten HID-Touchpads die Belegung der Klicktasten umschreiben (auf dem virtuellen Gerät
    im Container nicht möglich, am Gerät ungeprüft).

  Tastendrücke kann er nicht lesen, und ins Netz kommt er nicht. Dagegen helfen der Sandkasten, der kleine Code, der
  selbst nur `EVIOCGBIT` (lesend) aufruft, und dass er von aussen nichts annimmt ausser den Ereignissen von libinput.
  Ein seccomp-Filter, der `ioctl` nur mit lesenden Nummern erlaubt, ginge noch weiter; systemd kann Argumente nicht
  filtern, deshalb steht er aus (`docs/module/m9.md`, «Befunde der Sicherheitsprüfung»).
- **Pakete:** keine neuen. libinput (`libinput.so.10`) kommt schon mit labwc, python3 und systemd sind da.
- **Rückweg:** `sudo touch /etc/xdg/zenos/gesten-aus`, dann `/opt/zenos/scripts/install.sh`: Das Modul stoppt den
  Dienst (auch mitten im Neustart), beendet übrige Prozesse von `zenos-gesten` (etwa den Messmodus), entfernt Regel,
  Einheit und sysusers-Datei, gibt die Touchpads zurück (`root:input` 0660 wie ohne Regel) und löscht Benutzer und
  Gruppe. Gelingt das Löschen nicht, warnt es nur und versucht es beim nächsten Lauf wieder; `zen doctor` prüft, dass
  nichts liegen bleibt. Ohne die Datei richtet der
  nächste Lauf alles wieder ein. Ein `zen rollback` auf einen Stand ohne dieses Modul lässt Regel, Einheit und
  Benutzer liegen, harmlos: Ohne `/opt/zenos/scripts/bin/zenos-gesten` startet der Dienst nicht, und die Touchpads
  liest dann niemand ausser labwc.

## 1Password

- Passwörter, Karten und Schlüssel liegen nur in 1Password.
- Der SSH-Agent von 1Password authentifiziert Git und SSH. Er funktioniert nicht mit Snap- oder Flatpak-Installationen, deshalb wird 1Password direkt installiert.
- API-Schlüssel, etwa für Claude, holt zenOS später zur Laufzeit über die Kommandozeile `op` (in 0.1 installiert,
  aber noch von keiner Funktion genutzt).
- Sperrt zenOS den Bildschirm, sperrt sich 1Password mit.

## Chrome-Richtlinien

Datei: `system/chrome/policies/zenos.json`, wird nach `/etc/opt/chrome/policies/managed/` kopiert.

```json
{
  "HttpsOnlyMode": "force_enabled",
  "SafeBrowsingProtectionLevel": 2,
  "PasswordManagerEnabled": false,
  "AutofillCreditCardEnabled": false,
  "AutofillSettings": [{"url_pattern": "*", "blocked_types": ["payments"]}],
  "BlockThirdPartyCookies": true,
  "ExtensionInstallBlocklist": ["*"],
  "ExtensionInstallAllowlist": ["aeblfdkhhhdcdjpifhhbdiojplfjncoa"],
  "ExtensionInstallForcelist": ["aeblfdkhhhdcdjpifhhbdiojplfjncoa;https://clients2.google.com/service/update2/crx"]
}
```

`aeblfdkhhhdcdjpifhhbdiojplfjncoa` ist die 1Password-Erweiterung («1Password – Password Manager»), geprüft über den
Update-Dienst des Chrome Web Store (September 2026).

Dazu kommen fünf Abschaltungen von Telemetrie: `MetricsReportingEnabled`, `UrlKeyedAnonymizedDataCollectionEnabled`,
`DomainReliabilityAllowed`, `FeedbackSurveysEnabled` und `SafeBrowsingSurveysEnabled`, alle `false`.

**Kreditkarten im Autofill aus, mit zwei Richtlinien.** Karten liegen nur in 1Password, Chrome soll sie weder
vorschlagen noch zum Speichern anbieten. Laut Googles Richtlinienliste (Stand 07.10.2026, Quellen unten):

- `AutofillCreditCardEnabled` ist «deprecated in M156, please use AutofillSettings instead». Google nennt dort
  selbst den Ersatz für `false`: `AutofillSettings` mit `"url_pattern"` `"*"` und `"blocked_types"` `["payments"]`.
- `AutofillSettings` gibt es ab Chrome 154 (`chrome.*:154-`). Es ist eine Liste von Einträgen mit `url_pattern`
  und `blocked_types`; `payments` sperrt Vorschläge und das Speichern von Kreditkarten und Zahlungsmethoden, `*`
  passt auf jede Adresse. Die Richtlinie kann nur sperren, nicht erlauben; sie hebt die alte also nie auf.
- `AutofillCreditCardEnabled` bleibt drin, weil Chrome es noch auswertet: In der Liste steht es mit
  `chrome.*:63-`, ohne letzte Version. Es deckt Chrome vor 154 ab; ab 154 gelten beide, in dieselbe Richtung.
  Google rät von veralteten Richtlinien ab, «because they will be removed in future releases», und von entfernten
  erst recht, weil sie Fehler in Chrome auslösen können. Sobald die Liste eine letzte Version nennt
  (`chrome.*:63-<Version>`), fliegt die alte Richtlinie hier und in `system/chrome/policies/zenos.json` raus.
- Chrome stable unter Linux war am 08.10.2026 Version 155 (Version History API von Google). Ab 156 kann
  `chrome://policy` die alte Richtlinie als veraltet markieren; das ist erwartet und kein Fehler.

`test/einheiten/chrome-richtlinie.test.py` prüft das Format von `AutofillSettings` gegen das Schema aus Googles
Liste und dass der Block oben und die Telemetrie-Abschaltungen genau der Datei entsprechen.

Quellen: Richtlinienliste <https://chromeenterprise.google/policies/#AutofillSettings> und
<https://chromeenterprise.google/policies/#AutofillCreditCardEnabled> (maschinenlesbar:
<https://chromeenterprise.google/static/json/policy_templates_en-US.json>), veraltete Richtlinien
<https://support.google.com/chrome/a/answer/7643500>, Versionen
<https://versionhistory.googleapis.com/v1/chrome/platforms/linux/channels/stable/versions>.

Mit Maschinenrichtlinien schaltet Chrome «Sicheres DNS verwenden» (DNS-over-HTTPS) von selbst ab, der Schalter in den
Einstellungen ist gesperrt. Eine Richtlinie `DnsOverHttpsMode` würde es festlegen (`automatic` oder `secure`, für
`secure` mit einem Server in `DnsOverHttpsTemplates`), der Schalter bliebe aber ebenfalls gesperrt. Offene
Entscheidung für Zeno; bis dahin gilt die Vorgabe von Chrome (aus).

**Offene Entscheidung (Zeno): Safe Browsing Stufe 2 oder 1.** Stufe 2 (erweitert, wie oben) schickt Adressen in
Echtzeit sowie Proben von Seiten und Downloads an Google. Sie schliesst die erweiterte Berichterstattung ein, die
sich dann per Richtlinie nicht abschalten lässt. Das steht im Zielkonflikt mit der Leitplanke «keine Telemetrie»,
wird aber von Grundsatz 1 (Sicherheit) gestützt. Stufe 1 (Standard) gleicht Adressen über gekürzte Hash-Präfixe ab
und schickt keine Proben; dazu gehörte `"SafeBrowsingExtendedReportingEnabled": false`. Bis zur Entscheidung gilt
Stufe 2. Danach werden dieser Abschnitt und `system/chrome/policies/zenos.json` gemeinsam angepasst.

## VS Code-Richtlinie

Datei: `system/vscode/policy.json`, wird nach `/etc/vscode/policy.json` kopiert (root, 0644, Ordner nur für root
schreibbar). Wie die Chrome-Richtlinie liegt sie auch ohne VS Code und im Image bereit; sie ist nur Konfiguration.

```json
{
  "TelemetryLevel": "off"
}
```

VS Code liest diese Datei unter Linux ab Version 1.106. `off` schaltet Nutzungsdaten, Fehlerberichte und
Absturzberichte ab, dazu A/B-Experimente. Der Wert ist gesperrt: Die Einstellungen zeigen
`telemetry.telemetryLevel` als von der Organisation verwaltet, eine eigene Einstellung ändert nichts. Erweiterungen
anderer Anbieter halten sich nicht alle daran. Bewusst nicht gesetzt: `EnableFeedback` (Problembericht und Umfrage
senden nur auf Aktion) und `UpdateMode` (Updates kommen über apt, die Prüfung auf neue Versionen ist keine
Telemetrie).

## Terminal

- Bei gefährlichen Befehlen wie `rm -rf` auf Systemordnern, `curl … | sh` oder Rechte-Änderungen fragt zenOS einmal nach. «Abbrechen» ist die Vorauswahl.
- Terminal-Ausgaben verlassen den Rechner nie automatisch. «Fehler erklären» mit Claude kommt erst «Danach»; es wird eine ausdrückliche Aktion brauchen und vorher zeigen, was gesendet wird.

## Repo und Releases

- Keine Geheimnisse und keine persönlichen Daten im Repo. gitleaks läuft als Pre-Commit-Hook und in GitHub Actions.
- GitHub nur mit 2FA. Das Repo ist das System: Wer das Konto übernimmt, kann Code auf GitHub bringen; auf die Geräte
  kommt über den Kanal nur, was Zenos Release-Schlüssel signiert hat (siehe «Signierte Releases»).
- **Regeln auf GitHub** (stellt Zeno selbst ein, ANLEITUNG G): Rulesets für die Tags `v*` und `vertrauen/*` (nicht
  verschieben, nicht löschen, kein Force-Push, Ausnahme nur für Admins), auf `dev` und `main` kein Force-Push und kein
  Löschen, Immutable Releases. Sie sind eine zweite Schicht: Ein Token mit Schreibrecht kann damit keinen Tag mehr
  verschieben, und ein veröffentlichtes Release bleibt, wie es ist.
- Releases enthalten `SHA256SUMS` und eine Herkunftsbestätigung von GitHub (Artifact Attestation über Sigstore,
  prüfbar mit `gh attestation verify`), dazu den Quellcode aller Pakete. Die Tags signiert Zeno selbst, der erste
  signierte ist `v0.1.0-rc4` oder höher (siehe «Signierte Releases»). Die Image-Dateien tragen keine eigene
  Signatur.
- **Image nur aus einem signierten Tag:** `image.yml` prüft vor dem Bau mit `image/tag-pruefen.sh`, ob der Tag mit dem
  Release-Schlüssel des Ankers in seinem Stand gültig signiert ist (gehärtetes `git verify-tag` und unabhängig
  `ssh-keygen -Y verify`, ab Serie 2 mit passendem `vertrauen/NNNN`); `bauen.sh` prüft noch einmal, und im chroot
  prüft `zenos-kanal` ein drittes Mal wie ein Gerät. Sonst entsteht kein Image. Ein Release (`vX.Y.Z` als «Latest»,
  `vX.Y.Z-rcN` als Vorabversion) gibt es nur, wenn auch `scripts/pruefen.sh` im selben Lauf grün ist. Einen lokalen
  Testbau ohne Signatur gibt es nur mit `--testbau-ohne-signatur`; GitHub Actions verweigert ihn. Grenze: Workflow und `bauen.sh` kommen aus dem Stand des
  Tags; wer auf GitHub einen eigenen Tag mit eigenem Workflow pushen kann, kann die Prüfung dort ändern. Dagegen
  helfen die Regeln auf GitHub, und die Geräte prüfen ohnehin selbst. Der Anker im Stand muss ausserdem der sein, den
  ein Gerät über das Netz hätte: Wurzel und Release-Schlüssel von Serie 1 stehen fest in `tag-pruefen.sh`, jede
  spätere Serie braucht die ganze Kette `vertrauen/0002…NNNN`, mit der Wurzel signiert, und alle Widerrufe. So kommt
  ein Release-Schlüssel, der in einem echten Release ungewollt mitkam, nicht ins Image (frisch geflashte Geräte
  übernähmen ihn, solche, die über das Netz aktualisieren, nicht). `--nur-mechanik` (Testbau ohne Signatur) verweigert
  GitHub Actions ebenso.
- Im Image hat der Standardbenutzer (`user`, nur ohne Einstellungen aus dem Imager) **kein sudo ohne Passwort**
  (`/etc/cloud/cloud.cfg.d/90-zenos-benutzer.cfg`, `sudo: null`), sein Startpasswort ist abgelaufen und muss zuerst
  geändert werden, SSH nimmt nur Schlüssel an. Ubuntus Vorgabe wäre `NOPASSWD:ALL`; damit wären Passwortabfragen
  wie beim Ausschalten der Firewall wirkungslos.
- Im Image werden SSH-Hostschlüssel und `machine-id` gelöscht und beim ersten Start neu erzeugt. Sonst hätten alle Kopien dieselben Schlüssel.

## Signierte Releases

Bedrohung: Wer das GitHub-Konto, ein Token mit Schreibrecht oder einen Agenten nach einer Prompt-Injection
kontrolliert, kann heute Code auf jedes Gerät bringen, das `zen update` ausführt. Dort läuft er als root. Ein
signierter Kanal bindet Updates an Schlüssel, die nur in Zenos 1Password liegen. Einzelheiten zu Ablauf und Format
stehen in `docs/image-und-releases.md`, Abschnitt «Signierte Releases».

- **Zwei Schlüssel** (SSH, Ed25519, nur in 1Password, Freigabe mit Touch ID): «zenOS Release» signiert die Tags
  `vX.Y.Z` und `vX.Y.Z-rcN`. «zenOS Wurzel» liegt in einem eigenen Tresor und signiert nur Tags `vertrauen/NNNN`. Mit
  ihnen ändert sich die Liste der Release-Schlüssel oder der Widerrufe. Ein gestohlener Release-Schlüssel kann den Anker
  also nicht übernehmen, und es gibt einen Widerruf über das Netz.
- **Anker im Repo und im Image:** `system/vertrauen/` enthält nur öffentliche Prüfschlüssel mit neutralen Prinzipalen
  (`zenos-release`, `zenos-wurzel`). Das erlaubt Manifest 0 ausdrücklich, und gitleaks lässt sie durch. Private
  Schlüssel liegen nie in einer Datei. Nur beim Image-Bau füllt sich der Anker des Geräts automatisch aus dem Repo
  (`12-vertrauen` mit `--image`, aus dem gültig signierten Tag); auf einem laufenden Gerät nie, dort nur über
  `vertrauen/NNNN` oder von Hand. Dazu bekommt das Image den Zustand ab Werk: guter Stand und `hoechste` aus dem Tag,
  der Tag im Hauptbuch (ein später verschobener Tag ist schon beim ersten Kontakt ALARM).
- **Fail-closed:** Solange der Anker keine Schlüssel enthält, signiert `scripts/release-signieren.sh` nichts, und ein
  Gerät meldet «Anker fehlt»: nichts gilt als gültig, auf `stabil` und `vorschau` installiert `zen update` nichts. Der
  Weg von Hand über `dev` bleibt, aber nur mit einem getippten «ja» für genau den gezeigten Commit.
- **Installieren nur, was geprüft ist:** `zen update` und `zen rollback` stellen `/opt/zenos` nie mehr direkt um. Das
  Prüfen (root, ohne Netz) stellt ein gültig signiertes oder mit «ja» freigegebenes Ziel in einem eigenen Repo
  bereit; das Installieren (root, mit Netz) prüft es vor der Benutzung noch einmal gegen den Anker von dann und
  verlangt einen unveränderten, root-eigenen Baum. Auf dev ohne Frage nur, wenn jeder neue Commit seit dem
  installierten Stand gültig signiert ist (auch ein unsignierter Zwischencommit zählt). Das «ja» ist an die
  Commit- bzw. Tag-Objekt-ID gebunden und gilt nur im Terminal. Einzige Ausnahme: «Zustimmen …» in den Einstellungen
  (mit Passwort) für einen gültig signierten Stand, der Firewall, Netz oder Boot ändert (Abschnitt «Firewall», Updates
  in den Einstellungen).
- **Rückfrage vor Firewall, Netz, Boot:** Trifft ein Update einen der Rückfrage-Pfade (fest im Code von zenos-kanal,
  gleich den Gruppen in `scripts/lib/sensible-pfade`; ein neuer Stand kann keinen streichen), installiert es nur nach
  Zustimmung, auch wenn es signiert ist. Indirekte Änderungen (neue Pakete, gemeinsame Bibliotheken) fängt die Liste
  nicht.
- **Kein Aussperren:** Nach jeder Installation prüft zenos-kanal die Gesundheit (gewertet wird nur, was das Update
  verschlechtert; ein schon ausgefallenes greetd sperrt kein Update). Dazu kommt der Selbsttest des eben installierten
  zenos-kanal: Liest er den Anker, nimmt er den Tag an, und laufen, wenn er sich geändert hat, status, update, rollback,
  installieren und nachstart als Probelauf in einem Wegwerf-Zustand durch? Scheitert etwas, geht es auf den Stand davor
  zurück (dort ohne Probelauf), die Version ist gesperrt. Was der Selbsttest nicht fängt, holt der Notweg: die vorige
  Fassung `zenos-kanal.vorher` zurück, dann `zen rollback`. Erst danach kommt der git-Notweg in `ANLEITUNG.md`,
  Abschnitt F; er prüft den Tag gegen den Anker des Geräts und nimmt `dev` nur, solange der Anker fehlt. Ein Fehler,
  der erst nach einem Neustart auftritt (Login, PAM), fällt der Gesundheitsprüfung nicht auf: Ein automatisch
  installierter Stand gilt deshalb erst als gut, wenn nach einem Neustart der Login kommt (Login-Bildschirm oder eine
  grafische Sitzung; eine Anmeldung auf der Textkonsole zählt nicht); fehlt das bei zwei Starts, geht es auf den guten
  Stand zurück (ohne Rückweg auf den Stand ohne Login), und die Version ist gesperrt (Bestätigung nach dem Start).
  Scheitert der Weg zurück, ist das «kaputt», der gute Stand bleibt ungesperrt, und der nächste Start versucht es
  noch einmal.
- **Automatik** (Entscheid Zeno): Automatisch installiert wird nur auf `stabil` und `vorschau`, nie auf `dev`, nur ein
  gültig signierter Stand ohne Rückfrage-Pfade (sonst «wartet auf Zustimmung» mit Mitteilung) und nur zum Zeitpunkt
  des Geräts: «bei Sperre» (Standard) heisst, jede Sitzung auf seat0 ist seit 5 Minuten gesperrt, und die Oberfläche
  bestätigt die Sperre selbst (ext-session-lock), oder der Login-Bildschirm wartet seit 5 Minuten; nie, solange
  jemand per SSH angemeldet ist oder eine Textkonsole offen ist. Dazu «Zeitfenster», «jederzeit» und «von Hand»
  (nie). Bei jeder Wahl nur am Netzteil oder ab 50 % Akku, nie über einen Stand von Hand («angehalten», bis
  `zen update`), und eine unterbrochene Installation von Hand setzt nur `zen update` fort. Die Wartezeit auf stabil (24 h, gegen einen gestohlenen Release-Schlüssel: Widerruf und Löschen
  kommen so noch rechtzeitig an) beginnt erst mit synchronisierter Uhr und zählt im selben Start nach der Zeit seit dem
  Start; ein Sprung der Uhr durch NTP verkürzt sie nicht (ein dauerhaft lügendes NTP schon, Restrisiko). Nach
  `zen rollback` bringt die Automatik die verlassene Version nicht wieder (`hoechste` sinkt nicht). Das Programm, das die Sperre prüft, läuft als
  root in einer Sandbox ohne Netz und fragt die Oberfläche als der Benutzer der Sitzung (setpriv, Argumentliste); ein
  Benutzer kann so höchstens seine eigene Sitzung als gesperrt ausgeben, und auch dann kommt nur Signiertes. Der
  Notschalter (`sudo zen kanal automatik aus`) schaltet die Automatik ab, nie die Prüfung.
- **Lokale Benutzer:** Sperren und der Vermerk eines `install.sh` von Hand liegen in `/run/zenos-sperre` (nur root,
  0700). Früher lagen sie in `/run/lock`, für alle beschreibbar: Jeder Prozess als Benutzer (etwa ein Agent nach einer
  Prompt-Injection) konnte eine Sperre halten, den Kanal abschneiden und über die Kette Versuch → gesperrt → Rückweg
  an derselben Sperre ein «kaputt» erzwingen (Prüfung, selbst nachgestellt). Scheitert `install.sh` nur an seiner
  Sperre (Exit 75, nichts begonnen), zählt der Versuch nicht. Aus demselben Grund stützt sich die Gesundheitsprüfung
  nicht auf `/var/log/zenos/install.log` (gehört nach einem Lauf von Hand dem Benutzer und liesse sich kürzen oder
  ergänzen), sondern auf das root-eigene `/var/lib/zenos/kanal/install-ergebnis`, das `install.sh` nur im Lauf des
  Kanals schreibt.
- **Prüfung auf dem Gerät** (`scripts/bin/zenos-kanal`): Holen und Prüfen sind getrennt. Ein flüchtiger Systembenutzer
  ohne Rechte holt in einer Sandbox nur über https und gibt ein Bundle weiter; root öffnet dessen Repo nie. root prüft
  ohne Netz in einem Repo, das jedes Mal neu entsteht, mit leerer Umgebung für git (keine fremde config, keine Hooks,
  kein fsmonitor, OpenPGP und X.509 aus). Der Anker liegt root-eigen in `/etc/zenos/vertrauen` und wird nie aus
  `/opt/zenos` gelesen. Ein Hauptbuch erkennt verschobene Tags am Commit, nicht an der Objekt-ID: Die Signatur lässt
  sich ohne Schlüssel neu umbrechen, git nimmt das an, nur die Objekt-ID ändert sich (selbst nachgestellt); früher löste
  das einen ALARM aus und blockierte jedes Gerät. Viele Tags auf origin blockieren nichts (höchstens 2000
  Signaturprüfungen je Lauf), der Holer holt nur `dev` und `v*` und räumt seinen Spiegel auf. In die Bereitstellung
  und nach `/opt/zenos` kommen nur geprüfte Tags. `hoechste` verhindert ein Downgrade. Selbst
  nachgestellt: `git verify-tag` nimmt auch einen Tag mit zwei Signaturen oder unter falschem Namen an, und mit
  OpenPGP prüft git gegen den Schlüsselbund von gpg statt gegen den Anker; der Kanal lehnt alle drei ab.
- **Signieren nur bewusst:** `scripts/release-signieren.sh` läuft in einem eigenen Terminal-Tab ohne Claude Code. Es
  zeigt Commits und sensible Pfade gesondert (Firewall, Netz, Boot, Anmeldung, Vertrauen), signiert erst nach «ja» und
  prüft den Tag danach gegen den Anker. Gepusht wird nach einem zweiten «ja», und zwar nur der Tag. Danach 1Password
  sperren.
- **Fallen, die das Skript und das Gerät abfangen:** `git verify-tag` prüft den Tag-Namen nicht, und eine fehlende
  Widerrufsdatei nimmt git ohne Fehler hin (beides selbst nachgestellt). OpenPGP-Signaturen prüft git mit dem
  Schlüsselbund von gpg statt mit dem Anker (selbst nachgestellt in `test/einheiten/kanal.test.py`); deshalb ist
  OpenPGP beim Prüfen abgeschaltet.
- **Grenzen:** Eine Signatur bestätigt die Herkunft, nicht den Inhalt. Geht der Wurzel-Schlüssel verloren, braucht
  jedes Gerät ein neues Image oder einen neuen Anker von Hand. GitHub-Regeln für Tags (`v*`, `vertrauen/*` nicht
  verschieben oder löschen) und Immutable Releases sind eine zweite Schicht, die Zeno auf GitHub einschaltet
  (ANLEITUNG G).

## Basis-Updates (Pakete von Ubuntu)

Paket-Updates innerhalb von Ubuntu 26.04 LTS bringt `zenos-basis` (Entscheid Zeno, Oktober 2026), so wie
`apt full-upgrade` sie brächte: aus Ubuntu (auch `-updates`) und aus den Herstellerquellen. Bedrohung: Ein Update, das
etwas zerstört (Kernel, Login, Pakete, die wegfallen), oder ein Weg, über den jemand ohne Passwort root-Arbeit
anstösst. Ablauf, Dateien und Exit-Codes: `docs/image-und-releases.md`, «Basis-Updates».

- **Kein eigenes Vertrauen:** zenOS prüft keine Signaturen selbst. apt prüft jede Paketliste gegen die Schlüssel von
  Ubuntu bzw. des Herstellers, genau wie bei `apt full-upgrade` von Hand. zenOS wählt nur aus, wann und mit wessen
  Zustimmung das geschieht, und installiert genau die Liste, die gezeigt wurde (Hash über die Liste; ändert sie sich
  dazwischen, Exit 3). Von der Auswertung bis zum Ende von `apt-get full-upgrade` hält es die Sperre der Paketlisten
  (`/var/lib/apt/lists/lock`): Kein `apt-get update` (apt-daily) tauscht sie dazwischen aus, sonst brächte
  full-upgrade womöglich einen Kernel oder eine Entfernung, die nie angezeigt wurde. Tut apt trotzdem mehr (etwa
  unattended-upgrades genau dazwischen) und ist das ohne Zustimmung ein Kernel, Firmware, Bootloader oder eine
  Entfernung, oder ein geschütztes Paket ginge weg, heisst das Ergebnis «kaputt», nicht «installiert».
- **Nur root arbeitet:** Prüfen und Installieren laufen in Units als root (`zenos-basis-pruefen`,
  `-installieren`), aus der root-eigenen Kopie unter `/usr/local/libexec/zenos`, mit Argumentlisten und festem `PATH`.
  Wege dorthin: `zen update` mit sudo im Terminal, die Knöpfe der Einstellungen über polkit (oben, «Updates in den
  Einstellungen») und die Automatik. Zustand und Log sind root-eigen (`/var/lib/zenos/basis/`, für alle lesbar;
  `/var/log/zenos/basis.log` 0640); die Gesundheitsprüfung liest das root-eigene `install-ergebnis`, nicht das
  install.log.
- **Zustimmung:** Kernel, Firmware, Bootloader (`linux-raspi`, `linux-image-*`, `linux-firmware*`, `flash-kernel`,
  `piboot-try`, `rpi-eeprom`, `u-boot*`, `grub*`, `shim*` …) und jede Entfernung nur mit Zustimmung: ein getipptes
  «ja» (oder `--ja`) in `zen update` oder das Passwort in den Einstellungen, jedes Mal, gebunden an die Liste. Die
  Automatik installiert so etwas nie. Ein geschütztes Paket (die Liste aus `scripts/lib/aufraeumen.sh`, die
  zenOS-Pakete, alles manuell Installierte) entfernt zenOS nie, auch nicht mit Zustimmung (`gesperrt`).
- **`--ja` gilt nur für die Basis:** Das «ja» des Kanals bleibt an die gezeigte ID gebunden und nur im Terminal;
  `zen update --ja --nur-zenos` ist ein Aufruffehler. Claude deployt mit `zen update --nur-zenos`; Paketänderungen
  der Basis bleiben bei Zeno (`CLAUDE.md`).
- **Automatik** (ab Werk an, auch auf dev): nur eine Liste ohne Kernel, Firmware, Bootloader und Entfernungen, nur
  wenn `zenos-kanal automatik darf --ohne-ssh` ja sagt (dieselbe Quelle wie beim Kanal: Notschalter, Zeitpunkt des
  Geräts, Netzteil oder ab 50 % Akku) und bei jedem Zeitpunkt nie, solange jemand per SSH angemeldet ist: apt startet
  Dienste neu, wer per SSH arbeitet, merkte das. Nie ein Neustart. Keine Wartezeit wie auf stabil: Die 24 h schützen
  dort gegen einen gestohlenen Release-Schlüssel von zenOS, die Pakete signiert Ubuntu, und Ubuntu staffelt Updates
  selbst (Phasing, apt hält sich daran).
- **Nie zwei Paketvorgänge:** Die Installation hält dieselbe Sperre wie der Kanal (`/run/zenos-sperre/kanal.lock`,
  nur root) und läuft nicht neben einem `install.sh` von Hand, einer unterbrochenen oder kaputten Installation des
  Kanals; auf apt-daily, unattended-upgrades und die Sperren von dpkg wartet sie höchstens 20 Minuten.
- **Kein Aussperren:** greetd startet beim Update nicht neu (eigene `policy-rc.d` nur für diesen Lauf, die nur greetd
  ablehnt); eine neue greetd-Version heisst «Neustart nötig». Ab der Ausgangslage der Gesundheitsprüfung bis nach
  `install.sh` hält ein Block-Inhibitor Ausschalten und Ruhezustand auf, `zenos-energie` schaltet nicht aus
  (`zenos-argon` wartet bei 3 % Akku bis zu 5 Minuten länger), und ein Abbruch der SSH-Verbindung beendet die Unit
  nicht. Ein Stopp durch root vor apt beginnt apt nicht mehr; ein laufendes dpkg (auch `dpkg --configure -a` beim
  Prüfen) bricht keiner mittendrin ab (`KillMode=mixed` in beiden Units). Danach zählt nur, was schlechter wurde
  (dpkg, install.sh, Quickshell, greetd, ausgefallene Units, Fehler in `zen doctor`); zurückgerollt wird nichts,
  `letzte.json` und `zen doctor` nennen es, und die Oberfläche meldet «Basis-Update kaputt» dringend. Ist es behoben,
  vermerkt Zeno das mit `sudo …/zenos-basis quittieren` (root, prüft vorher nach).
- **Sicherheitsupdates bleiben bei unattended-upgrades:** täglich, unabhängig vom Notschalter und vom Zeitpunkt; daran
  ändert zenos-basis nichts.
- **Kein Wechsel der Hauptversion:** `Prompt=never` (Drop-in in `/etc/update-manager/release-upgrades.d/`, oben unter
  «Unterbau») und die Grenze im Kanal (`system/basis`): Ein Stand für eine andere Ubuntu-Version ist nie ein Ziel,
  auch nicht mit «ja».
- **Neustart nötig** zeigt die Oberfläche still (Symbol in der Leiste, Wert im System-Menü), nie während der Bildschirm
  geteilt wird und nie auf der Sperre (Leitplanke im Code, `shell/dienste/basis.js`); `zen version` und `zen doctor`
  nennen ihn auch.
- **Grenzen:** Kein Schnappschuss und kein Rückweg. Was erst nach dem Neustart bricht (Kernel, initramfs, PAM), sieht
  die Gesundheitsprüfung nicht; dagegen helfen nur die Zustimmung, piboot-try (prüft einen neuen Kernel beim nächsten
  Start) und die zweite Karte. Kernel aus `-security` bringt unattended-upgrades wie bei Ubuntu ohne Zustimmung. Wer
  über `systemd-run` an `allow_active` kommt, kann eine anstehende Liste ohne Kernel und Entfernungen früher
  installieren, sonst nichts. Häufigeres `apt-get update` heisst häufigere Abfragen an die Paketquellen und über
  esm-cache an `contracts.canonical.com` (oben, «Unterbau»). Gegen root schützt nichts.
