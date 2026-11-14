<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/zeichen/zenos-schriftzug-dunkel.svg">
    <img src="assets/zeichen/zenos-schriftzug-hell.svg" alt="zenOS" height="56">
  </picture>
</h1>

zenOS ist ein unveränderliches Desktop-System aus Debian 13 für den Argon ONE UP mit Compute Module 5, gebaut für eine Person.

> Gebaut von Zeno zusammen mit Claude von Anthropic, mit Claude Code. Website: [zenos-linux.com](https://zenos-linux.com)

*English: zenOS is an immutable desktop system for the Argon ONE UP laptop (Raspberry Pi Compute Module 5), built with mkosi from Debian 13 packages: a read-only system verified by dm-verity, data encrypted with LUKS2 behind a password and a FIDO2 security key, and updates only with Zeno's signature. Version 1.0 is being built on the `neubau` branch; there is no public image yet. Version 0.1 (Ubuntu) is frozen on the `dev` branch. Built by one person for one person, together with Claude. Not affiliated with the Debian project, Raspberry Pi Ltd or the maker of the Argon ONE UP. Documentation is in German.*

## Was zenOS ist

zenOS 1.0 ist ein Image, das mkosi aus Debian-Paketen baut. Auf dem Gerät gibt es keinen Paketmanager: Ein neuer Stand kommt immer als ganzes System, signiert, über `zen update`.

| Teil | Stand 0.9.1 |
|---|---|
| Unterbau | Debian 13 «trixie» arm64, aus einem festen Paketstand des Snapshot-Archivs von Debian (08.11.2026) |
| System | `/` samt `/usr` und `/etc` als erofs, schreibgeschützt und mit dm-verity geprüft; zwei Hälften (A und B) für Updates |
| Daten | `/var` und `/home` auf einer eigenen Partition mit LUKS2 (Argon2id), beim ersten Start angelegt, ohne Ausführrecht |
| Kernel und Firmware | Linux-Kernel 6.18 als fertiges Paket von Raspberry Pi, dazu Gerätebäume und WLAN-Firmware; nur diese Pakete kommen aus deren Paketquelle, alle anderen von Debian |
| Fenstermanager | labwc (Wayland), ohne X-Server. Fenster rasten per Tastendruck in Hälften und Viertel ein, gekachelt wird nicht automatisch |
| Oberfläche | Quickshell 0.3.1 (QML, Qt 6), beim Bau aus dem Quellcode übersetzt: Login, Leiste, Befehlsfeld (`Super + Leertaste`), System-Menü mit WLAN, Sperre |
| Terminal | kitty mit fish (`Ctrl + Alt + T`): `Ctrl + C` kopiert, wenn Text markiert ist, sonst bricht es ab |
| Browser | Chromium aus Debian, gehärtet über Richtlinien |

Farben, Schrift, Radien, Abstände und Bewegung der Oberfläche kommen aus [`shell/theme/tokens.json`](shell/theme/tokens.json). Auch labwc und kitty bekommen die Farben daraus; Schrift, Radien und Abstände stehen dort aber zum Teil als feste Kopie, die Schrift für GTK ebenso. Hell und dunkel sind gleichwertig. Nicht im Image sind unter anderem apt und dpkg, sudo und pkexec, ein SSH-Server, Compiler, XWayland, avahi und udisks2; root ist gesperrt. Proprietäre Programme wie Chrome, VS Code oder die App von 1Password kommen nie aufs Gerät; ausgenommen sind die unfreie Firmware des WLAN-Chips und die freigegebenen Erweiterungen für Chromium, etwa die proprietäre von 1Password. Das Release-Image enthält keine KI.

Selbst gebaut ist, was man sieht und täglich anfasst; der Rest kommt von Debian und Raspberry Pi. Bewusst nicht dabei: ein eigener Browser, Dateimanager oder Netzwerk-Stack und ein Hypervisor (wer Bereiche räumlich trennen will, nimmt Qubes OS). Den Kernel liefert Raspberry Pi; ab 1.0 baut zenOS ihn aus deren Quellcode mit eigener Konfiguration.

Die Grundsätze stehen im [Manifest](MANIFEST.md). Die Reihenfolge ist die Rangordnung, bei einem Konflikt gewinnt der höhere:

0. zenOS hat genau einen Benutzer.
1. Sicherheit ist Standard.
2. Ruhe ist der Normalzustand.
3. Eine Sache steht im Fokus.
4. Alles läuft über eine Stelle.
5. Das Design lebt an einem Ort.
6. Der Pi ist die Messlatte.

## Sicherheit

Sicherheit geht vor Design und Bequemlichkeit. Das Konzept mit dem Bedrohungsmodell steht in [docs/neubau.md](docs/neubau.md). Es beruht auf drei Ideen:

1. **Was nicht da ist, kann nicht angegriffen werden.** Jedes Paket, das zenOS auswählt, steht mit Grund in der Paketliste; Abhängigkeiten kommen von selbst dazu, empfohlene Zusatzpakete nicht. Der Bau bricht ab, wenn ein verbotenes Programm oder ein setuid-Programm ausserhalb einer kurzen Liste auftaucht.
2. **Was startet, ist geprüft.** Das System ist schreibgeschützt und wird bei jedem Lesen geprüft. Mit dem signierten Start (ab 1.0) überlebt auch root keinen Neustart.
3. **Was zählt, wird woanders bestätigt.** Zahlungen in der App der Bank, Krypto auf dem Display der Hardware-Wallet, Releases mit einem Hardware-Schlüssel.

Im Image:

- **Netz:** nftables verwirft alles Eingehende ausser Antworten auf eigene Verbindungen, DHCP und den nötigen ICMPv6-Meldungen; einen Schalter dafür gibt es nicht. Namensauflösung ohne mDNS und LLMNR, NetworkManager ohne Verbindungsprüfung und mit zufälliger MAC-Adresse bei der Suche und einer eigenen je WLAN. Die Zeit kommt über NTS (chrony).
- **Kernel:** Härtung über Befehlszeile und sysctl nach der Vorlage von Kicksecure, unter anderem io_uring aus, kein BPF und kein userfaultfd für Benutzer, kein kexec.
- **Daten:** Beim Start öffnen sie sich nur mit dem Passwort und der Berührung eines von zwei FIDO2-Schlüsseln. Jeder Schlüssel hat einen eigenen LUKS-Platz, dessen Passphrase aus Passwort und Schlüssel entsteht (hmac-secret). Einen Platz mit dem Passwort allein gibt es nicht, an einer Kopie der SSD lässt es sich also nicht durchprobieren. Einziger Weg ohne Schlüssel ist der Wiederherstellungsschlüssel auf Papier. Das Verfahren steht offen in [docs/neubau.md](docs/neubau.md), Abschnitt 4.9.
- **Anmelden und Sperre:** Kontopasswort und Schlüssel (pam_u2f). Gesperrt wird über ext-session-lock und PAM, automatisch nach 5 Minuten ohne Eingabe und sofort beim Zuklappen des Deckels.
- **Ausschalten nach langer Sperre:** Solange zenOS läuft, liegt der Schlüssel der Daten im Arbeitsspeicher. War es 30 Minuten ohne entsperrte Sitzung, schaltet es aus. Kein Programm kann das aufhalten, und abschalten lässt es sich nicht.
- **Browser:** Chromium mit HTTPS-only, ohne Cookies von Drittanbietern, ohne eigenen Passwortspeicher und Autofill, ohne Anmeldung, Synchronisation und Entwicklerwerkzeuge, Metriken aus, Safe Browsing im Standardmodus. Erweiterungen nur mit freigegebener ID. Chromium speichert keinen Verlauf, Cookies gelten nur für die Sitzung, beim Beenden löscht es Cookies, Website-Daten, Cache, Formulardaten und Anmeldedaten, und Downloads liegen nur im Arbeitsspeicher.

Die Leitplanken aus dem [Manifest](MANIFEST.md) kann keine Einstellung aushebeln; sie sind Code, nicht Konfiguration. Unter anderem:

- Der Sperrbildschirm zeigt nie Inhalte, und die automatische Sperre lässt sich nicht abschalten.
- Es liegen keine Geheimnisse im Repo, und es gibt keine Telemetrie. Terminal-Ausgaben und Bildschirminhalte verlassen den Rechner nie automatisch.
- Das Release-Image hat keinen Fernzugang, keine Entwicklerwerkzeuge und keine KI. Kein Dienst nimmt Verbindungen von aussen an.
- Auf dem Gerät läuft nur, was im Image von zenOS ist, und ein Gerät installiert nur, was zenOS signiert hat.
- Jede Leitplanke hat einen Test, der versucht, sie zu brechen.

Wovor zenOS 1.0 schützen soll und was bleibt (nach [docs/neubau.md](docs/neubau.md), Abschnitt 2, gekürzt und dem gebauten Stand angepasst):

| Wer greift an | Schutz | Was bleibt |
|---|---|---|
| Jemand im selben WLAN | kein Dienst nimmt Verbindungen an, Firewall ohne Schalter, kein SSH, kein mDNS | eine Lücke im WLAN-Chip oder seiner Firmware |
| Eine Webseite | Sandbox von Chromium, Richtlinien, Safe Browsing, Passkeys | eine unbekannte Lücke bis zum nächsten signierten Image |
| Schadsoftware aus einem Download | nur Apps aus dem Image, keine fremden Erweiterungen, kein Admin | ein Download, den man selbst ausführbar macht und startet: Downloads liegen im Arbeitsspeicher, und dort ist Ausführen nicht gesperrt; eine Lücke im Kernel gibt Zugriff auf alles |
| Schadsoftware, die bleiben will | System samt `/etc` schreibgeschützt und geprüft, `/var` und `/home` ohne Ausführrecht | ohne root kann sie sich im Konto festsetzen (eigene Funktionen von fish, Einstellungen von kitty, Benutzerdienste unter `~/.config`); bis zum signierten Start (1.0) kann root die Startpartitionen ändern |
| Ein Dieb | Daten nur mit Passwort und Hardware-Schlüssel oder mit dem Wiederherstellungsschlüssel auf Papier, Ausschalten nach 30 Minuten ohne entsperrte Sitzung | Laptop und Schlüssel gestohlen und das Passwort bekannt, oder Laptop und Wiederherstellungsschlüssel zusammen; bis zum Ausschalten liegt der Schlüssel der Daten im Arbeitsspeicher |
| «Evil Maid» (Startcode ändern, Passwort abfangen) | erst mit 1.0: signierter Start, fremder Code startet nicht | bis dahin offen, danach der Tausch des ganzen CM5-Moduls |
| Lieferkette (Debian, Raspberry Pi, GitHub, der Bau am Mac, Code von Claude) | Debian stable mit festem Paketstand, Kernel von Raspberry Pi mit fester Version (die WLAN-Firmware nicht: jeder Bau nimmt die neueste), Durchsicht vor dem Signieren, Signatur nur mit Zenos FIDO2-Schlüsseln; mit 1.0 dazu ein zweiter Bau und eine Durchsicht von aussen | ein manipulierter Stand, den Zeno signiert, weil er bei der Durchsicht nicht auffällt |

Nicht abgedeckt: Lücken in Prozessor und Firmware, Seitenkanäle und wer das Gerät lange in der Hand hat und Hardware umbaut. Dazu bleiben ein Kernel ohne Sicherheitsteam, die Firmware von BCM2712 und WLAN-Chip und ein Mensch mit einer KI als einzige Entwickler.

**Updates nur mit Zenos Signatur.** Jeder von Zenos zwei FIDO2-Schlüsseln trägt einen Signaturschlüssel `ed25519-sk` von OpenSSH, dessen geheimer Teil ihn nie verlässt. Zeno signiert die Prüfsummenliste `SHA256SUMS` eines Stands in seinem Terminal (`ssh-keygen -Y sign`), mit PIN und Berührung, im Namensraum `argon-update`. Eine Signatur für etwas anderes, etwa einen Git-Commit, nimmt das Gerät nicht an. Eine KI löst nie eine Signatur aus, der ein Gerät traut. Die öffentlichen Schlüssel liegen in [`mkosi/schluessel/argon-allowed-signers`](mkosi/schluessel/argon-allowed-signers), ihre Fingerabdrücke im [Manifest](MANIFEST.md); zeigt der Bau andere, ist die Datei ausgetauscht worden. Einrichten, Signieren, Aufbewahrung und Verlust: [docs/signieren.md](docs/signieren.md).

Die Signatur schützt vor einem gestohlenen Schlüssel, vor einer Übernahme von GitHub und vor jedem Update ohne Zenos Zutun. Vor einem manipulierten Bau schützt sie nicht: Was Zeno signiert, ist so gut wie der Stand, den er vorgelegt bekommt.

## Stand

zenOS 1.0 entsteht auf dem Branch `neubau` in drei Stufen ([docs/neubau.md](docs/neubau.md), Abschnitt 6; [ROADMAP.md](ROADMAP.md)). Bis 1.0 heissen die Stände technisch 0.9.x. Fertig ist eine Stufe erst, wenn Zeno sie auf echter Hardware abgenommen hat.

| Stufe | Inhalt | Stand am 14.11.2026 |
|---|---|---|
| Vorschau 1 | geprüftes System, LUKS2, kein SSH, kein Admin, kein Paketmanager, Firewall zu, Zeit über NTS, Kernel-Härtung, Chromium mit Richtlinien, Grundfunktionen der Oberfläche (Login, Leiste, Apps starten, Sperre, WLAN) | gebaut; 0.9.1 läuft auf der SSD des Argon, abgenommen ist es teilweise |
| Vorschau 2 | signierte Updates mit Probestart, Erinnerung nach 14 Tagen, mehr Funktionen aus 0.1 | Updates und Erinnerung gebaut und in QEMU geprüft (ohne Probestart); das erste signierte Update am Argon steht aus. Bluetooth, Akku-Anzeige, Einstellungen, Modi und Zustände aus 0.1 kommen später mit Updates |
| 1.0 | Kernel aus dem Quellcode von Raspberry Pi mit Lockdown, signierter Start mit OTP (zuerst auf einem Test-Pi 5), Hardware-Schlüssel, zweiter Bau, alle Angriffstests, Durchsicht von aussen | Hardware-Schlüssel gebaut; Kernel, signierter Start, zweiter Bau, die Angriffstests von 1.0 (etwa ein unsigniertes `boot.img` auf echter Hardware) und Durchsicht offen |

**Am Argon:** Seit dem 14.11.2026 läuft das Image 0.9.1 (Stand `638a881`) auf der SSD. Erster Start, Einrichtung und Login sind gelungen. In QEMU waren am selben Tag 92 von 92 Angriffs- und Starttests grün.

**Noch am Gerät zu prüfen** (Abnahmeliste in [docs/baufortschritt.md](docs/baufortschritt.md)): WLAN; dass ohne Schlüssel weder die Daten beim Start noch Login und Sperre aufgehen; ein Passkey in Chromium; der Deckel; das Ausschalten nach 30 Minuten; `zen schluessel status`. Danach das erste signierte Update (`zenos-0.9.2`) mit dem Probestart über tryboot.

**Bekannte offene Punkte:**

- Kein signierter Start: Wer root hat, könnte die Startpartitionen ändern. Das schliesst erst 1.0.
- Der Kernel von Raspberry Pi hat kein Yama, und AppArmor ist dort ohne `lsm=apparmor` aus. In QEMU (Kernel von Debian) ist beides aktiv; am Argon ist zenOS in diesem Punkt schwächer als getestet.
- Downloads liegen im Arbeitsspeicher, und dort ist Ausführen nicht gesperrt: Was man herunterlädt, ausführbar macht und startet, läuft. Die Leitplanke «Auf dem Gerät läuft nur, was im Image ist» gilt damit noch nicht ganz.
- Die machine-id ist bei jedem Start neu, weil `/etc` schreibgeschützt ist. systemd-homed meldet dazu Fehler, die Anmeldung geht. Vor Vorschau 2 muss sie dauerhaft werden.
- Ein abgebrochener erster Start kann das Gerät unbrauchbar machen, bis ein neues Image auf der SSD ist; die 30 Minuten bis zum Ausschalten zählen schon, während Konto und Anmeldung eingerichtet werden (siehe «Auf die SSD schreiben»).
- Fehlt der Schlüssel beim Login oder in der Sperre, meldet zenOS «Das Passwort stimmt nicht» statt «Schlüssel einstecken».
- Zeichen über AltGr (etwa €) kommen auf der Konsole und am grafischen Login verschieden an. Im Konto-Passwort deshalb nur Zeichen nehmen, die direkt auf einer Taste liegen.
- Vorerst keine USB-Datenträger (kein udisks2).

Alle Befunde und offenen Punkte: [docs/baufortschritt.md](docs/baufortschritt.md).

**Kein öffentliches Image:** Ein Image von 1.0 zum Herunterladen gibt es noch nicht. Releases von 1.0 heissen `zenos-<version>` und enthalten das ganze Image für eine leere SSD, die Dateien für Updates, `SHA256SUMS` und Zenos Signatur `SHA256SUMS.sig`. Bis dahin bleibt nur, selbst zu bauen ([mkosi/README.md](mkosi/README.md)).

**zenOS 0.1** (Ubuntu) ist seit dem 08.11.2026 eingefroren und liegt mit eigener README auf dem Branch `dev`; ein `v0.1.0` kommt nicht mehr. Nichts auf `neubau` darf `zen update` eines Geräts mit 0.1 erreichen.

## Selbst bauen und testen

Gebaut wird auf einem Mac, nicht auf dem Laptop: Docker über Colima, darin ein Debian-Container mit mkosi und QEMU ([`mkosi/umgebung/`](mkosi/umgebung/)).

```
mkosi/bauen.sh argon     # Image für den Argon ONE UP
mkosi/bauen.sh qemu      # Image für die Tests
mkosi/test/starten.sh    # Angriffs- und Starttests in QEMU
```

Für die Tests baut mkosi dasselbe System mit dem Kernel von Debian und Start über UEFI, weil QEMU den Start des CM5 nicht nachbilden kann; den Probestart über tryboot gibt es nur auf echter Hardware. Die Tests prüfen unter anderem, dass das System schreibgeschützt und geprüft ist, kein Dienst Verbindungen von aussen annimmt, nichts Verbotenes im Image liegt, Login, Oberfläche und Sperre laufen und `zen update` veränderte oder unsignierte Stände ablehnt.

Das Argon-Image lädt Updates von den Releases dieses Repos und traut nur den Schlüsseln in `mkosi/schluessel/argon-allowed-signers`; ohne die Datei bricht der Bau ab. Das Test-Image traut nur einem Wegwerf-Schlüssel, der nicht ins Repo kommt. Vor jedem Commit läuft gitleaks; das ist eine Arbeitsregel in [CLAUDE.md](CLAUDE.md), auf `neubau` erzwingt es bisher weder ein Hook noch ein Workflow. Alles Weitere, auch der Update-Test: [mkosi/README.md](mkosi/README.md).

## Auf die SSD schreiben

Das Image kommt als Ganzes auf die NVMe-SSD des Argon; was darauf war, geht verloren. Das macht Zeno selbst am Mac, mit der SSD in einem USB-Gehäuse, einen Befehl nach dem anderen; Claude schreibt nie auf einen Datenträger. Vorher muss `mkosi/test/startpartitionen.sh` «Alle Prüfungen bestanden» melden, und der Bau muss die zwei Fingerabdrücke aus dem Manifest gezeigt haben. Die Schritte und den ersten Start beschreibt [mkosi/README.md](mkosi/README.md).

Beim ersten Start legt zenOS die verschlüsselte Datenpartition an und verwirft dabei die alten Daten auf der SSD; nur in den rund 4,8 GiB, um die System A dabei wächst, bleiben Reste davon. Das dauert einige Minuten. Danach führt es durch die Einrichtung: Tastaturbelegung, Passwort für die Daten, Hardware-Schlüssel, Wiederherstellungsschlüssel zum Abschreiben, Konto und Schlüssel für die Anmeldung. Ohne einen Hardware-Schlüssel geht es nicht weiter.

Den ersten Start in einem Zug durchgehen, bis der Login von zenOS erscheint, und vorher nicht ausschalten. Bricht er ab, kann es sein, dass man nicht mehr an die Daten oder nicht mehr ins Konto kommt; dann muss die SSD neu geschrieben werden. Schon ab dem Öffnen der Daten zählen die 30 Minuten bis zum Ausschalten, Konto und Schlüssel für die Anmeldung müssen also in dieser Zeit eingerichtet sein.

## Updates

Neue Stände kommen nur auf `zen update` im Terminal; von selbst lädt zenOS keine. Einen Admin braucht es dafür nicht: polkit erlaubt einer Sitzung am Gerät genau den Start des Update-Dienstes, von anderswo nicht.

```
zen update       neuen Stand laden, prüfen und in die freie Hälfte schreiben
zen neustart     neu starten, mit Probestart, wenn ein Update bereitliegt
zen status       laufende Version, Alter der Pakete, Stand der Updates
zen schluessel   Hardware-Schlüssel: status, hinzufuegen, entfernen <nummer>
```

`zen update` lädt `SHA256SUMS` und `SHA256SUMS.sig` des neuesten Release dieses Repos, nur über https. Bevor etwas geschrieben wird, prüft das Gerät Zenos Signatur samt Berührung und PIN, dann die Liste (ein Stand, neuer als der laufende) und jede Datei gegen ihre Prüfsumme; nur diese geprüfte Kopie schreibt systemd-sysupdate in die freie Hälfte. Einzelheiten: [docs/signieren.md](docs/signieren.md), Abschnitt «Was der Argon prüft».

Nach `zen neustart` startet der neue Stand einmal zur Probe (tryboot). Läuft der Login, wird er fest. Hängt er, die Ein/Aus-Taste lange drücken und wieder einschalten: Dann startet der alte Stand, und `zen status` sagt, wie es weitergeht. Hing der neue Stand schon vor dem Login, kommt er beim nächsten Neustart (`zen neustart`) noch einmal zur Probe; scheitert er dann wieder, oder hing er erst beim Login selbst, wird er nicht nochmals angeboten.

Weil es auf dem Gerät keinen Paketmanager gibt, kommen auch die Sicherheitsupdates von Debian nur mit einem neuen Image. Vorgesehen ist ein neues Image bei jeder Sicherheitsmeldung von Debian zu einem Paket im Image und bei jedem Kernel-Update, sonst wöchentlich. Sind die Pakete des laufenden Stands 14 Tage alt, erinnert zenOS einmal am Tag daran. Gezählt wird nur mit einer Uhr, die über NTS gestellt ist, und ins Netz geht dafür nichts.

Veröffentlicht wird nur nach Zenos Ja: Claude baut und bereitet den Stand vor (`mkosi/veroeffentlichen.sh`), Zeno signiert, Claude prüft die Signatur wie das Gerät (`mkosi/signatur-pruefen.sh`) und legt das Release `zenos-<version>` an. Nie ein Tag `v…`: Darauf reagieren `zen update` von 0.1 und dessen Image-Workflow. Geht einer der zwei Schlüssel verloren, entfernt ihn ein Update, das mit dem anderen signiert ist. Sind beide weg, nimmt das Gerät kein Update mehr an, und die SSD muss neu beschrieben werden.

## Hardware

- **Argon ONE UP** mit Compute Module 5 Lite (ohne eMMC) und NVMe-SSD, Chip BCM2712. Für ihn ist zenOS 1.0 gebaut, und bisher läuft es nur auf ihm. Der CM5 hat kein TPM und kein UEFI: Die Daten schützen Passwort und Hardware-Schlüssel, und geprüft starten lässt er sich nur über den signierten Start von Raspberry Pi, für den der Hash eines Schlüssels unwiderruflich ins OTP gebrannt wird.
- **Raspberry Pi 5** (gleicher Chip): Das Profil `argon` ist für ihn mitgebaut, getestet ist zenOS 1.0 darauf nicht. Für den signierten Start ist zuerst ein Test-Pi 5 vorgesehen, dann der Laptop.
- **Zwei FIDO2-Schlüssel**, mindestens einer für den ersten Start. Sie brauchen die Erweiterung hmac-secret; hat ein Schlüssel eine PIN, muss er neue Einträge ohne PIN erlauben (`makeCredUvNotRqd`). Der Schlüssel gehört an den Schlüsselbund, nicht in den Laptop.
- **x86-Rechner:** später. Was dafür dazukäme, skizziert der Anhang von [docs/neubau.md](docs/neubau.md).

## Dokumentation

| Datei | Inhalt |
|---|---|
| [MANIFEST.md](MANIFEST.md) | Grundsätze, Leitplanken, Fingerabdrücke der Update-Schlüssel |
| [docs/neubau.md](docs/neubau.md) | Konzept von 1.0: Bedrohungsmodell, Aufbau, Stufen |
| [docs/baufortschritt.md](docs/baufortschritt.md) | Stand, Befunde, offene Punkte, Abnahme am Argon |
| [mkosi/README.md](mkosi/README.md) | Bauen, Testen, Aufteilung der SSD, erster Start, Updates, was noch fehlt |
| [docs/signieren.md](docs/signieren.md) | Updates signieren und prüfen, Verlust eines Schlüssels |
| [docs/sicherheit.md](docs/sicherheit.md) | im ersten Abschnitt der Code von zenOS, der in 1.0 als root läuft, mit Grund; der Rest meist 0.1 |
| [docs/design.md](docs/design.md) | Design-Tokens und Komponenten; die Komponenten teils noch aus 0.1 |
| [docs/bildmarke.md](docs/bildmarke.md) | die Bildmarke «Zwei Steine» |
| [ROADMAP.md](ROADMAP.md), [BAUAUFTRAG.md](BAUAUFTRAG.md) | Stufen und laufende Bauaufträge |
| [CLAUDE.md](CLAUDE.md) | Arbeitsanweisungen für Claude |

Das Image von 1.0 entsteht aus `mkosi/`, `shell/` und `assets/`. Den Stand von 0.1 (Ubuntu) beschreiben [ANLEITUNG.md](ANLEITUNG.md), [CHANGELOG.md](CHANGELOG.md), [docs/architektur.md](docs/architektur.md), [docs/konfiguration.md](docs/konfiguration.md), [docs/funktionen.md](docs/funktionen.md), [docs/image-und-releases.md](docs/image-und-releases.md) und [docs/module/](docs/module/); zu 0.1 gehören auch `scripts/`, `image/`, `system/`, `config/`, `test/` und die Workflows in `.github/workflows/`.

## Gebaut mit Claude

zenOS entsteht offen im Dialog mit Claude von Anthropic. Zeno gestaltet, entscheidet und testet auf echter Hardware. Claude Code schreibt einen Grossteil des Codes, für 1.0 auf dem Mac in Container und QEMU, nicht mehr auf dem Laptop.

- Commits von Claude Code tragen die Zeile `Co-Authored-By: Claude …`.
- Die Arbeitsanweisungen für Claude liegen offen in [CLAUDE.md](CLAUDE.md).
- Claude hat keinen Zugriff auf Zenos Schlüssel und löst nie eine Signatur aus, der ein Gerät traut; Claude prüft Signaturen nur. Einzige Ausnahme ist der Wegwerf-Schlüssel des QEMU-Tests: Mit ihm signiert der Update-Test Stände, denen nur das Test-Image traut.
- Ziel ist kein Code von zenOS mit root auf dem Gerät. Die Ausnahmen stehen mit Grund in [docs/sicherheit.md](docs/sicherheit.md); dort fehlen noch `greetd-starten` und `tastatur-waehlen`.

## Mitmachen

zenOS ist für eine Person gebaut. Issues und Pull Requests werden nicht angenommen.

Passt's dir, nimm's. Passt's dir nicht, bau dein eigenes.

## Rechtliches

zenOS ist ein unabhängiges Projekt und nicht mit dem Debian-Projekt, mit Raspberry Pi Ltd oder dem Hersteller des Argon ONE UP verbunden.

Der Code von zenOS steht unter der [MIT-Lizenz](LICENSE). Das Image enthält Pakete aus Debian und von Raspberry Pi unter ihren eigenen Lizenzen, darunter unfreie Firmware von Raspberry Pi (WLAN), dazu Quickshell (LGPL 3) und die Schriften Geist, Geist Mono und Instrument Serif (SIL Open Font License 1.1); deren Lizenztexte liegen im Image unter `/usr/share/licenses/`. Die Dokumentation der Pakete, und mit ihr deren Lizenztexte unter `/usr/share/doc`, lässt das Image heute weg. Wie Lizenztexte und Quellcode der Pakete zu den Releases von 1.0 kommen, ist noch nicht geregelt. Das gilt schon für das erste Release (`zenos-0.9.2`), denn jedes Release enthält das ganze Image. Für 0.1 gilt, was auf dem Branch `dev` steht.

Debian ist eine eingetragene Marke von Software in the Public Interest, Inc. Linux® ist die eingetragene Marke von Linus Torvalds in den USA und anderen Ländern. Raspberry Pi ist eine Marke von Raspberry Pi Ltd. Ubuntu und Canonical sind eingetragene Marken von Canonical Ltd.
