# Neubau: zenOS 1.0

Entwurf, fünfte Fassung vom 08.11.2026. Sie ersetzt die Fassungen 1 bis 4 vom selben Tag; was sich gegenüber der
vierten geändert hat, steht in Abschnitt 9.

Entscheide und Angaben von Zeno:

- **Neubau statt Ubuntu härten.** zenOS baut das ganze System selbst als unveränderliches, signiertes Image aus
  Debian-Paketen. Die Bausteine werden übernommen, nicht erfunden.
- **Gerät:** Argon ONE UP mit Compute Module 5 Lite und NVMe-SSD, derselbe Chip (BCM2712) wie im Raspberry Pi 5. Auf
  ihm laufen auch E-Banking und Krypto.
- **v0.1:** sofort eingefroren. Kein `v0.1.0` mehr.
- **Kein Tresor, kein Neustart fürs Banking.** Das ganze System ist sicher, nicht nur ein Teil davon. E-Banking und
  Wallets laufen einfach im Browser.
- **Bald auf die SSD:** zenOS 1.0 kommt in Stufen auf die SSD des Argon (Abschnitt 6).

## Die drei Grundideen

1. **Was nicht da ist, kann nicht angegriffen werden.** Auf dem Laptop läuft nur, was im Image ist. Kein Dienst nimmt
   Verbindungen an, kein Paketmanager, kein Admin, keine Entwicklerwerkzeuge, keine KI. Jedes Paket, jeder Dienst und
   jedes setuid-Programm steht auf einer Liste mit Grund; der Bau bricht ab, wenn etwas anderes auftaucht.
2. **Was startet, ist geprüft.** `/usr` ist schreibgeschützt und wird bei jedem Lesen geprüft, `/etc` entsteht bei jedem
   Start neu. Mit dem signierten Start (Stufe 1.0) überlebt auch root keinen Neustart.
3. **Was zählt, wird woanders bestätigt.** Zahlungen in der App der Bank auf dem Handy, Krypto auf dem Display der
   Hardware-Wallet, Releases mit einem Hardware-Schlüssel. Selbst ein übernommener Laptop kann dann kein Geld bewegen.

## 1. Die Hardware

Argon ONE UP: CM5 Lite (ohne eMMC) mit NVMe-SSD. Tastatur und Touchpad am USB-2-Anschluss des CM5 (Host-Modus über
`dtoverlay=dwc2,dr_mode=host`), Akku-Messchip CW2217 an I2C, Deckel an GPIO27, Kamera mit Schalter, WLAN 5 und
Bluetooth 5.0 (CYW43455, geschlossene Firmware). Ein Schalter NORMAL/OTG macht das CM5 über USB-C programmierbar
(`rpiboot`).

Was der CM5 nicht hat und was das heisst:

- **Kein TPM.** Die Festplatte schützt ein langes Passwort (LUKS2 mit Argon2id), keine PIN mit Sperre nach
  Fehlversuchen. Ältere, signierte Stände lassen sich nicht sperren. Einen Echtheitscode beim Start gibt es nicht.
- **Kein UEFI.** Geprüfter Start geht nur über den signierten Start von Raspberry Pi; dafür wird der Hash des Schlüssels
  **unwiderruflich** ins OTP gebrannt.
- **Kein Kernel mit Sicherheitsteam.** Debian kann den BCM2712 nicht vollständig; der Kernel kommt aus dem Quellcode
  von Raspberry Pi.
- **Kein externer PCIe-Anschluss**, also keine DMA-Angriffe über Thunderbolt.

## 2. Wovor zenOS 1.0 schützt

| Wer greift an | Weg | Schutz | Was bleibt |
|---|---|---|---|
| Jemand im selben WLAN | offene Dienste, Netzwerk-Treiber | kein Dienst nimmt Verbindungen an, Firewall ohne Schalter, kein SSH, kein mDNS | Lücke im WLAN-Chip oder seiner Firmware |
| Eine Webseite | Lücke im Browser, Phishing | Chromium-Sandbox, JavaScript ohne JIT als Vorgabe, Safe Browsing, Passkeys, neues Image bei jeder Sicherheitsmeldung | Zero-Day bis zum nächsten signierten Image |
| Schadsoftware (Download, Anhang) | Daten und Bank-Sitzung abgreifen, Zahlung umbiegen | nur Apps aus dem Image, keine fremden Erweiterungen, kein Admin, nichts Ausführbares ausserhalb von `/usr`; Bestätigung in Bank-App und Wallet | eine Lücke im Kernel gibt Zugriff auf alles, auch aufs Banking; die Bestätigung auf dem zweiten Gerät bleibt der Schutz fürs Geld |
| Schadsoftware, die bleiben will | System, `/etc`, Erweiterungen aus `/var`, Bootpartition | `/usr` geprüft, `/etc` flüchtig, keine Erweiterungen aus `/var`; ab 1.0 signierter Start | bis 1.0: root kann die Bootpartition ändern |
| Dieb | SSD ausbauen und lesen | LUKS2 für alles ausser `/usr` (das ist öffentlich) | schwaches Passwort |
| Jemand zwingt dich | dich zwingen, den Laptop zu starten und das Passwort einzutippen | Notfall-Passwort (4.8): Es löscht in Sekunden alle Schlüssel der Daten, zenOS startet danach leer, als wäre nichts | eine Kopie der SSD, die jemand vorher zieht; die Täuschung hält nur bis zum Ausschalten |
| «Evil Maid» | Startcode ändern, Passwort abfangen | ab 1.0 signierter Start: fremder Code startet nicht | Tausch des ganzen CM5-Moduls gegen eine Attrappe |
| Lieferkette (Debian, Raspberry Pi, GitHub, CI, Zenos Mac, Code von Claude) | manipuliertes Paket oder Image | Debian stable, eingefrorener Paketstand, zwei Bauten, Signieren nur in einem frisch gestarteten Live-System, Durchsicht vor dem Signieren | GitHub und der zweite Bau gleichzeitig übernommen; Fehler, die bei der Durchsicht nicht auffallen |
| Manipulierte Wallet-Erweiterung oder Web-App (wie Ledger Connect Kit 2023) | falsche Empfängeradresse | Hardware-Wallet zeigt Empfänger und Betrag auf ihrem eigenen Display | wer dort nicht hinschaut |

Nicht abgedeckt: Lücken in Prozessor und Firmware, Seitenkanäle, wer das Gerät lange in der Hand hat und Hardware umbaut.

## 3. Warum diese Bauweise

- Am sichersten wäre theoretisch ein formal bewiesener Mikrokernel (seL4) und praktisch Qubes OS. Beides läuft nicht
  auf dem CM5 bzw. trägt keinen modernen Browser.
- Gewählt: **unveränderliches System mit geprüftem Start**, das Modell von ChromeOS und GrapheneOS, heute auch von
  GNOME OS, KDE Linux und ParticleOS.
- Pakete aus **Debian 13 «trixie» (stable):** eigenes Sicherheitsteam, keine Firma mit Geschäftsinteressen, keine
  Telemetrie, dieselbe Familie wie Raspberry Pi OS. Nicht testing: dort fehlt die zeitnahe Sicherheitspflege, und die
  Hintertür in xz (2024) kam bis testing, aber nie in stable.
- Gebaut mit **mkosi** (systemd-Projekt). Für die Tests in QEMU baut mkosi aus demselben `/usr` eine Variante mit
  UEFI, weil QEMU den Start des CM5 nicht nachbilden kann.

## 4. Aufbau

### 4.1 Start

- Der Bootloader des CM5 lädt Kernel, initramfs und Befehlszeile mit dem Verity-Hash. **Ab Stufe 1.0** steckt das in
  einem signierten `boot.img`, und das OTP lässt nur noch die Signatur von zenOS zu. Bis dahin kann root die
  Bootpartition ändern; das ist die grösste Lücke der Vorschauen.
- Das OTP ist **unwiderruflich**. Auf Pi 5 und CM5 lässt sich der signierte Bootloader nicht testen, ohne es zu brennen;
  vorher lässt sich nur das `boot.img` prüfen (`boot_ramdisk=1`). Deshalb zuerst auf einen Test-Pi 5, dann auf den
  Laptop. Geht der Schlüssel verloren, wird das Modul getauscht, nicht der Laptop.
- A/B für Updates über `tryboot`: Ein neuer Stand startet einmal zur Probe; nur wenn er sauber läuft, wird er der
  normale.
- Keine Notfall-Shell: root ist gesperrt, ein Fehler im initramfs führt zum Neustart.
- **LUKS2 mit Argon2id** für `/var` und `/home`, mit einem langen Passwort (zum Beispiel sechs zufällige Wörter).
  Wiederherstellungsschlüssel auf Papier.

### 4.2 Kernel

- **Bis Stufe 1.0** das fertige Kernel-Paket von Raspberry Pi (`archive.raspberrypi.com`), per apt-Pinning nur Kernel
  und Firmware aus dieser Quelle.
- **Ab Stufe 1.0 selbst gebaut** aus dem Quellcode von Raspberry Pi: schlanke Konfiguration nur für BCM2712 und das
  Argon ONE UP, io_uring nicht eingebaut, Lockdown, erzwungene Modul-Signaturen. Das ist die eine Stelle, an der
  Selbstbauen sicherer ist als Übernehmen. Der Preis: CI baut jedes Stable-Update des Zweigs nach.
- **Härtung** nach Kicksecure (`security-misc`): `init_on_alloc=1`, `init_on_free=1`, `slab_nomerge`,
  `randomize_kstack_offset=on`, `debugfs=off`, `kptr_restrict`, `dmesg_restrict`, kein unprivilegiertes BPF,
  `bpf_jit_harden`, `ptrace` nur für root, kein `kexec`, kein `userfaultfd` für Benutzer, io_uring aus
  (`kernel.io_uring_disabled=2`; 60 % der Kernel-Exploits in Googles Bug-Bounty nutzten es). Unprivilegierte
  User-Namespaces bleiben, weil die Sandbox von Chromium sie braucht.
- **Argon-Hardware über den Kernel statt über eigene Dienste mit root:** Deckel als `gpio-keys` (logind übernimmt das
  Zuklappen), Lüfter über die Thermal-Regelung des Kernels, Akku über einen Kernel-Treiber für den CW2217, falls es einen
  gibt; sonst ein kleiner Dienst ohne root, der nur den Messchip lesen darf.

### 4.3 System

- **`/usr` schreibgeschützt mit dm-verity**, A und B für Updates. Die Wurzel `/` ist flüchtig, **`/etc` entsteht bei
  jedem Start neu** aus `/usr/share/factory`. Gerätespezifisches (WLAN, Zeitzone, Konto über systemd-homed) liegt als
  Daten unter `/var`, nie als Konfiguration, die Programme ausführt.
- **Keine Erweiterungen aus `/var`** (systemd-sysext und -confext aus), keine Dienste und Bibliotheken ausserhalb von
  `/usr`, `noexec` auf `/home`, `/var` und `/tmp`.
- **Kein Admin:** kein sudo, kein su. WLAN, Updates, Zeit und Ausschalten gehen über NetworkManager, systemd und logind
  mit polkit.
- **Kein Code von zenOS läuft als root** (Ziel). Jede Ausnahme steht mit Grund in `docs/sicherheit.md`.
- **Feste Liste der Systemdienste:** systemd (mit logind, resolved, homed, cryptsetup, sysupdated), NetworkManager mit
  wpa_supplicant, polkit, greetd, chrony. Kein udisks2 (zuletzt CVE-2025-6019, ein Weg zu root), deshalb vorerst keine
  USB-Datenträger.
- setuid nur auf einer kurzen Liste, AppArmor erzwungen, Dienste mit systemd-Sandbox.
- **Nur Pakete mit voller Sicherheitsunterstützung von Debian** (`check-support-status` im Bau). Ausnahmen mit Grund:
  Firmware (ohne sie startet nichts), der Kernel (4.2) und Quickshell. Quickshell ist nicht in trixie, und forky hat
  erst 0.2.1; die Oberfläche von 0.1 braucht 0.3.1. zenOS baut deshalb wie 0.1 genau den Commit von v0.3.1 aus dem
  Quellcode, im Bau des Images (mkosi-Build-Skript), damit kein Compiler aufs Gerät kommt.
- Nicht im Image: apt und die Paketdatenbank, Compiler, SSH-Server, XWayland, avahi, Druckdienst, udisks2.

### 4.4 Netz

- nftables verwirft alles Eingehende ausser Antworten auf eigene Verbindungen, DHCP und die IPv6-Nachbarsuche. Kein
  Schalter.
- **Zeit über NTS** (chrony), damit niemand im Netz die Uhr zurückdrehen und alte Stände frisch aussehen lassen kann.
- systemd-resolved ohne mDNS und LLMNR; NetworkManager ohne Verbindungsprüfung, mit zufälliger MAC-Adresse je WLAN.
- Was von selbst rausgeht, steht vollständig in `docs/sicherheit.md`: Updates, Zeit, Updates der erlaubten
  Erweiterungen, Safe Browsing.

### 4.5 Browser, Banking und Wallets

- **Chromium aus Debian** statt Chrome. Es ist Open Source und wird von Debian laufend mit Sicherheitsupdates versorgt;
  die Synchronisation mit dem Google-Konto fehlt. Es gibt keinen zweiten Browser.
- **Warum Chromium der sicherste Browser ist, der sich hier pflegen lässt** (Wunsch Zeno vom 08.11.2026): Chromium hat
  die stärkste Sandbox und trennt jede Website in einen eigenen Prozess (Site Isolation). Firefox trennt schwächer, und
  Trezor Suite im Web geht dort nicht (kein WebUSB). Brave kommt aus einer fremden Paketquelle und bringt Wallet,
  Werbeprogramm und KI-Assistent mit, also mehr Angriffsfläche ohne Nutzen. ungoogled-chromium liefert Sicherheitsupdates
  oft später. Gehärtete Varianten wie Trivalent (secureblue) gibt es nicht für Debian auf arm64; Chromium selbst zu
  bauen hiesse, jedes Sicherheitsupdate stundenlang nachzubauen. Die Härtung kommt deshalb über Richtlinien.
- **Richtlinien:** HTTPS-only, Drittanbieter-Cookies blockiert, eigener Passwortspeicher und Autofill aus (1Password
  übernimmt), keine Anmeldung bei Google, keine Synchronisation, keine Entwicklerwerkzeuge, kein Hintergrundbetrieb,
  Metriken aus.
- **Nichts bleibt liegen** (Wunsch Zeno vom 11.11.2026): Chromium speichert keinen Verlauf; Cookies gelten nur für
  die Sitzung, und beim Beenden löscht Chromium Cookies, Website-Daten, Cache, Formulardaten, Anmeldedaten und den
  Download-Verlauf. Die letzte Sitzung wird nicht wiederhergestellt. Downloads liegen nur im Arbeitsspeicher
  (`~/Downloads` zeigt nach `$XDG_RUNTIME_DIR/zenos/downloads`) und sind nach dem Abmelden oder Ausschalten weg; den
  Cache räumt zusätzlich jede Anmeldung weg, falls Chromium abstürzte. Es bleiben Lesezeichen (sie sind der sichere Weg
  zu Bank und Anbietern), Einstellungen pro Website (etwa der V8-Optimierer) und die Daten der freigegebenen
  Erweiterungen. Wer sich anmelden will, meldet sich nach jedem Start von Chromium neu an.
- **Erweiterungen nur mit freigegebener ID:** 1Password und die gewählte Wallet (zum Beispiel MetaMask oder Rabby).
  Eine weitere kommt auf Wunsch mit dem nächsten Image.
- **JavaScript ohne JIT als Vorgabe** (empfohlene Richtlinie, nicht erzwungen). Der JIT-Compiler ist der häufigste Weg
  in den Browser. Ist eine Seite zu langsam oder braucht eine Wallet WebAssembly, erlaubst du ihn für diese Seite in den
  Einstellungen von Chromium («V8-Optimierer»). Ob das auf dem CM5 flüssig genug ist, misst Vorschau 1.
- **Safe Browsing an** (Standardmodus: Abfrage über verkürzte Prüfsummen, nicht über die Adressen selbst).
- **Wallets:** Trezor über Trezor Suite im Web (WebUSB; Trezor nennt dafür Chromium-Browser unter Linux), Ledger über
  WebHID, etwa mit MetaMask. zenOS bringt die udev-Regeln dafür mit.
- **E-Banking** auf der Website der Bank, Anmeldung mit Passkey oder der App der Bank, jede Zahlung in der App bestätigt.

### 4.6 Oberfläche

- **labwc 0.8.3 aus Debian.** Die Erlaubnisliste für privilegierte Schnittstellen (`<privilegedInterfaces>`: Bildschirm
  aufnehmen, Zwischenablage mitlesen, Tasten einspeisen) kam erst mit labwc 0.20. Weil auf dem Laptop nur Apps aus dem
  Image laufen, ist das bis Debian 14 vertretbar; dann kommt die Erlaubnisliste.
- **Quickshell** mit der Oberfläche aus 0.1, angepasst: ohne Netz (`RestrictAddressFamilies=AF_UNIX`), Mitteilungen nur
  als reiner Text, nie eine Eingabe an eine Shell, keine root-Helfer mehr.
- **Apps im Image:** Chromium, kitty (Fernsteuerung aus) mit fish, ein Dateimanager ohne Vorschaubilder (Thumbnailer
  lesen fremde Dateien und sind ein bekannter Angriffsweg). Nicht auf dem Laptop: VS Code, Claude Code, Node, die
  1Password-App.

### 4.7 Updates

- `systemd-sysupdate` lädt das neue Image in die freie Hälfte und prüft die Signatur; Kernel und initramfs gehen über
  `tryboot` zur Probe. Startet der neue Stand nicht sauber, startet wieder der alte.
- Neu gebaut wird bei jeder Debian-Sicherheitsmeldung zu einem Paket im Image und bei jedem Kernel-Update, sonst
  wöchentlich; Chromium hat Vorrang.
- Mitteilung nach 14 Tagen ohne neues Image (mit der Zeit aus NTS).

### 4.8 Notfall-Passwort

Wunsch Zeno vom 11.11.2026 (`BAUAUFTRAG.md`, Bauauftrag 2). Schützt gegen jemanden, der den Laptop selbst startet und
Zeno zwingt, das Passwort einzutippen.

- **Was es tut:** Statt des Passworts getippt, löscht es alle Schlüsselplätze der Daten (`luksErase`, auch den
  Wiederherstellungsschlüssel) und nullt seine eigene Partition. Danach startet zenOS bis zum Schreibtisch, angemeldet
  mit einem leeren Konto unter Zenos Namen; `/var` liegt nur im Arbeitsspeicher, die SSD wird nicht mehr beschrieben.
  Kein `zen update`, keine Erinnerung.
- **Aufbau:** Eine eigene Partition `zenos-notfall` (32 MB, kein Dateisystem): Nullen oder ein LUKS2-Container mit nur
  dem Notfall-Passwort, darin nur der Kontoname. Kein Hash, nichts im Klartext. Die Daten öffnet eine eigene
  Passwortabfrage (`/usr/lib/zenos/entsperren`) statt systemd-cryptsetup: zuerst die Daten, nur wenn das scheitert das
  Notfall-Passwort. Ein Tippfehler löst also nie den Notfall aus, und ein Notfall-Passwort, das die Daten öffnet, wird
  nicht angenommen.
- **Passwörter:** Nur in diesen Skripten fasst zenOS ein Passwort selbst an (Ausnahme von «zenOS fasst nie selbst ein
  Passwort an», erteilt im Bauauftrag): nur im Arbeitsspeicher, an cryptsetup über Pipes, nie in einer Befehlszeile,
  Datei oder im Journal; an den Dienst, der die Attrappe anmeldet, nur über den Schlüsselbund des Kernels.
- **Setzen:** beim ersten Start (freiwillig) und später mit `zen notfall` (ein Dienst mit root hinter einem Socket, der
  nur eine aktive Sitzung am Gerät annimmt und für jede Änderung das Passwort der Daten verlangt).
- **Grenzen:** Gegen eine Kopie der SSD, die jemand vorher zieht und ohne den Startcode von zenOS untersucht, hilft es
  nicht. Die Täuschung hält bis zum Ausschalten; danach ist jedes Passwort «falsch», und wer den LUKS-Kopf ansieht,
  sieht, dass die Schlüssel fehlen. Ein LUKS-Kopf auf `zenos-notfall` verrät, dass es ein Notfall-Passwort gibt.
  Zurück geht es nur mit einem neuen Image.

## 5. Lieferkette, Schlüssel und KI

- Eingefrorener Paketstand von `snapshot.debian.org` für jeden Bau.
- Zwei Bauten: arm64-Runner von GitHub und eine Linux-VM auf dem Mac. Signiert wird nur, wenn beide dasselbe ergeben;
  ob mkosi Bit für Bit gleich baut, wird gemessen.
- CI ist nicht vertrauenswürdig: keine Geheimnisse in GitHub, fremde Actions nur mit festem Commit-Hash.
- **Signiert wird in einem frisch gestarteten Live-System vom USB-Stick, nie auf dem Mac, auf dem Claude Code läuft.**
  Es lädt die Images selbst, vergleicht die Prüfsummen mit dem zweiten Bau und zeigt geänderte Pakete und Commits.
  Erst dann signiert Zeno. Der Mac lädt die Signaturen hoch und kann sie zurückhalten, aber nicht fälschen.
- Schlüssel auf einem Hardware-Schlüssel mit PIN und Berührung (zum Beispiel YubiKey 5 oder Nitrokey 3), dazu ein
  zweiter als Ersatz und eine verschlüsselte Sicherung offline. Bis sie da sind, gilt ein vorläufiger Schlüssel; der
  erste Stand mit dem Hardware-Schlüssel wird noch mit dem vorläufigen signiert, danach gilt nur noch der neue. Den
  Schlüssel für den signierten Start verlangen die Werkzeuge von Raspberry Pi als RSA-Datei; ob er auf den
  Hardware-Schlüssel kann (PKCS#11), wird geprüft.
- **KI:** Claude schreibt einen Grossteil des Codes. Deshalb: wenig eigener Code, keiner mit root-Rechten auf dem Gerät;
  Zeno sieht vor dem Signieren jeden Commit; Claude hat nie Zugriff auf die Schlüssel. Kein Release-Image enthält KI.
- **Entwicklung nicht mehr auf dem Laptop:** Claude Code arbeitet auf dem Mac (Container und QEMU) und, für den
  signierten Start, auf einem Test-Pi 5 mit einem Entwicklungs-Image. Das wird nie mit dem Release-Schlüssel signiert.
- Vor v1.0.0 eine Durchsicht von aussen.

## 6. Stufen bis zur SSD

| Stufe | Inhalt | Für Banking und Krypto |
|---|---|---|
| **Vorschau 1** (in den nächsten Tagen) | startet auf dem Argon von USB-Stick oder SSD: `/usr` geprüft, `/etc` flüchtig, LUKS2, kein SSH, kein Admin, kein Paketmanager, Firewall zu, Zeit über NTS, Kernel-Härtung, Chromium mit Richtlinien und Wallet-Regeln, Grundfunktionen der Oberfläche (Login, Leiste, Apps starten, Sperre, WLAN) | **nein:** noch keine Updates, und ein Browser ohne Updates ist nach wenigen Wochen unsicher |
| **Vorschau 2** (rund zwei Wochen danach) | signierte Updates über sysupdate mit `tryboot`, vorläufiger Schlüssel, Signieren im Live-System, Mitteilung nach 14 Tagen, mehr Funktionen aus 0.1 (Befehlsfeld, Mitteilungen, Akku, Bluetooth) | **ja** |
| **1.0** (Wochen danach) | eigener Kernel mit Lockdown, signierter Start mit OTP (zuerst auf dem Test-Pi), Hardware-Schlüssel, zweiter Bau, alle Angriffstests, Durchsicht von aussen | ja, mit vollem Schutz |

Entscheid Zeno (10.11.2026): Die SSD bekommt zenOS 1.0 direkt, ohne Umweg über den Stick, und 0.1 wird dabei
gelöscht. Weil die SSD danach nicht mehr ausgebaut wird, kommen die Updates aus Vorschau 2 schon mit: `zen update`
mit Zenos Signatur, A/B mit Probestart nach dem Schema von Raspberry Pi (autoboot.txt, Startpartitionen 2 und 3).
Technisch heissen die Stände bis 1.0 «0.9.x». Die übrigen Funktionen aus 0.1 kommen danach über Updates.

**Angriffstests** laufen ab Vorschau 1 in QEMU bei jedem Bau. Jede Leitplanke hat einen Test, der versucht, sie zu
brechen: ein Byte in `/usr` ändern, eine Datei unter `/etc` oder eine Erweiterung unter `/var` ablegen, Notfall-Shell
erzwingen, Portscan, Listen für Pakete, Dienste und setuid, fremde Erweiterung, Uhr zurückdrehen. Ab Vorschau 2 kommen
unsignierte, alte und kaputte Updates dazu, ab 1.0 ein unsigniertes `boot.img` auf echter Hardware.

## 7. Was bleibt und was Zeno selbst tun muss

Restrisiken: eine Lücke im Kernel gibt Zugriff auf alles; bis 1.0 kann root die Bootpartition ändern; ohne TPM keine
Sperre alter Stände; Tausch des ganzen CM5-Moduls; Kernel ohne Sicherheitsteam; Firmware von BCM2712 und WLAN-Chip; ein
Mensch mit einer KI als einzige Entwickler.

Was kein Betriebssystem ersetzt:

- **Hardware-Wallet für Krypto.** Seed-Phrase nur auf Papier oder Metall, nie fotografiert, nie in 1Password, nie auf
  einem Gerät. Vor jeder Bestätigung Empfänger und Betrag auf dem Display der Wallet lesen.
- Bank, Börse, E-Mail, GitHub und 1Password mit Passkey oder Hardware-Schlüssel; jede Zahlung in der App der Bank
  prüfen.
- Ein langes Passwort für die Festplatte, nirgends sonst verwendet.
- Gehäuse versiegeln: Glitzernagellack auf die Schrauben des Bodens, fotografieren, ab und zu vergleichen.
- Das Handy aktuell halten. Nie unter Zeitdruck signieren.

## 8. Vorschlag fürs Manifest

Grundsatz 1 neu:

> ## 1. Sicherheit ist Standard.
>
> Sicherheit geht vor Design und Bequemlichkeit. Was nicht gebraucht wird, ist nicht da. Das System ist
> unveränderlich, signiert und startet nur, was zenOS gebaut hat. Die Bausteine dafür werden nicht selbst erfunden,
> sondern von Debian, systemd, Raspberry Pi und erprobten Werkzeugen übernommen.

Neue Leitplanken:

> - Das Release-Image hat keinen Fernzugang, keine Entwicklerwerkzeuge und keine KI.
> - Kein Dienst nimmt Verbindungen von aussen an.
> - Auf dem Gerät läuft nur, was im signierten Image ist.
> - Ein Gerät installiert nur, was zenOS signiert hat. Signiert wird nie auf einem Rechner, auf dem eine KI arbeitet.
> - Jede Leitplanke hat einen Test, der versucht, sie zu brechen.

Architektur und harte Regeln in `CLAUDE.md` (Unterbau Debian, Kernel, Apps, Entwicklung nicht mehr auf dem Laptop)
werden mit dem Start angepasst.

## 9. Was sich gegenüber der vierten Fassung ändert

1. **Kein Tresor und keine getrennten Starts** (Entscheid Zeno). Das ganze System ist so schlank, wie es der Tresor
   gewesen wäre: nur Apps aus dem Image, nur freigegebene Erweiterungen, kein Admin. Der zusätzliche Schutz fürs Geld
   liegt ausserhalb des Laptops (Bank-App, Hardware-Wallet).
2. **JIT** ist jetzt eine Vorgabe, die man pro Seite in Chromium selbst ändern kann, statt eines Zwangs.
3. **Signieren** in einem Live-System vom USB-Stick statt in einem eigenen Start von zenOS.
4. **Stufen** statt Phasen: Vorschau 1 in den nächsten Tagen, Vorschau 2 mit Updates, dann 1.0. Bis 1.0 das fertige
   Kernel-Paket von Raspberry Pi.

## Anhang: x86 (später)

Für einen x86-Rechner kommen dazu: eigene Secure-Boot-Schlüssel (Prüfsummen der Options-ROMs statt Schlüssel von
Microsoft), Firmware-Passwort, UKI, LUKS2 mit TPM2 und PIN an PCR 7 und einer signierten Richtlinie für PCR 11,
Echtheitscode mit tpm2-totp, Sperre alter Stände über die dbx, IOMMU und Thunderbolt aus, der Kernel von Debian.

## Quellen (geprüft am 08.11.2026)

- Argon ONE UP: https://www.cnx-software.com/2025/08/05/argon-one-up-raspberry-pi-cm5-laptop/ · OTG-Schalter:
  https://wiki.argon40.com/en/AssemblyGuides/ONE_UP/OneUP_resource
- Signierter Start CM5/Pi 5: https://github.com/raspberrypi/usbboot/blob/master/secure-boot-recovery5/README.md ·
  https://pip.raspberrypi.com/documents/RP-003466-WP-Boot-Security-Howto.pdf · `tryboot`:
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
- RP1 in Mainline: https://github.com/raspberrypi/linux/issues/7264
- labwc in trixie: https://packages.debian.org/trixie/labwc · `<privilegedInterfaces>`:
  https://labwc.github.io/labwc-config.5.html
- Quickshell in forky: https://packages.debian.org/source/sid/quickshell
- Chromium für trixie: https://security-tracker.debian.org/tracker/DSA-6605-1 · JIT per Richtlinie:
  https://learn.microsoft.com/pl-pl/deployedge/microsoft-edge-browser-policies/defaultjavascriptjitsetting
- Trezor und Browser: https://trezor.io/guides/trezor-suite/trezor-suite-desktop/os-requirements-for-trezor · MetaMask mit
  Ledger: https://consensys.io/blog/metamask-and-ledger-integration-fixed
- io_uring: https://seclists.org/oss-sec/2023/q2/235 · Kicksecure:
  https://git.hackliberty.org/Git-Mirrors/security-misc/src/commit/cdd66ee3762c441843d421a9e6b11a20580ed7ac/etc/default/grub.d/40_kernel_hardening.cfg
- sysupdate in trixie: https://manpages.debian.org/trixie/systemd-container/sysupdate.d.5.en.html · Debian 13:
  https://www.debian.org/releases/trixie/release-notes.en.pdf
