# Sicherheit

Grundsatz 1: Sicherheit ist Standard und geht vor Design und Bequemlichkeit. Sie wird übernommen, nicht selbst erfunden.

## Unterbau

- Nur LTS-Versionen von Ubuntu. Sicherheitsupdates laufen automatisch (`unattended-upgrades`).
- Ubuntu Server holt ab Werk Nachrichten, ohne dass jemand etwas tut. zenOS schaltet beide ab, auf dem Weg, den
  Ubuntu dafür vorsieht (`scripts/module/70-sicherheit.sh`, `zen doctor` prüft es):
  - **motd-news** (Paket `motd-news-config`): Ein Timer ruft zweimal täglich `motd.ubuntu.com` auf und schickt im
    User-Agent Ubuntu-Version, Kernel, Architektur und `cloud_id` mit. zenOS setzt `ENABLED=0` in
    `/etc/default/motd-news`, nur wenn die Datei da ist. Der Timer bleibt, das Skript endet dann sofort.
  - **apt-news** (`ubuntu-pro-client`): holt bei `apt update` höchstens einmal täglich
    `motd.ubuntu.com/aptnews.json`. zenOS setzt `pro config set apt_news=false`, nur wenn der Client installiert ist.
  - Rückgängig: `ENABLED=1` in `/etc/default/motd-news` bzw. `sudo pro config set apt_news=true`. `install.sh`
    schaltet beides beim nächsten Lauf wieder ab; dauerhaft nur, wenn `_sicherheit_nachrichten` aus
    `modul_system` in `scripts/module/70-sicherheit.sh` entfernt wird.
  - Es bleiben die Verbindungen, die Updates holen: apt und `unattended-upgrades`, snapd (falls installiert) und
    `esm-cache` von `ubuntu-pro-client`. Dieser fragt bei `apt update` `contracts.canonical.com` nach verfügbaren
    Diensten (mit Architektur, Serie, Kernel und Virtualisierung, das Ergebnis wird zwischengespeichert) und lädt
    Paketlisten von `esm.ubuntu.com`. Ob er auch abgeschaltet werden soll, ist offen (`docs/module/m11.md`).
  - `apport` sammelt Absturzberichte nur lokal; gesendet wird erst mit `ubuntu-bug` (whoopsie gehört nicht zu
    Ubuntu Server).
- Die Firewall (`ufw`) ist standardmässig an. Ausschalten geht nur bewusst und nur mit Passwort (siehe
  «Firewall» unten). SSH nur mit Schlüssel ist das Ziel; zenOS ändert die SSH-Konfiguration nicht.
- Festplattenverschlüsselung: auf dem Bürorechner Pflicht. Auf dem Pi ist sie das Ziel; in 0.1 noch nicht umgesetzt (offen).
- Secure Boot: auf dem Bürorechner aktiv. Auf dem Pi bewusst nicht, weil dort Schlüssel dauerhaft in den Chip geschrieben werden.
- Backups sollen automatisch und verschlüsselt auf einen eigenen Server oder ein NAS laufen (Ziel, in 0.1 noch nicht umgesetzt).

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

## Oberfläche

- Der Sperrbildschirm nutzt `ext-session-lock`. Stürzt die Oberfläche ab, bleibt der Bildschirm gesperrt.
- Die Anmeldung läuft über PAM. zenOS verarbeitet nie selbst Passwörter. Auch der polkit-Dialog reicht das
  Passwort nur an polkit weiter (siehe «polkit-Agent»).
- Automatische Sperre bei Inaktivität und Standby. Sie ist nicht abschaltbar.
- Bei Bildschirmfreigabe werden Mitteilungsinhalte immer verborgen.
- Das Befehlsfeld startet Prozesse mit Argument-Listen, nie über `sh -c`.
- Die Nutzungsstatistik des Befehlsfelds speichert nur Desktop-IDs, Zähler und die Reihenfolge der zuletzt genutzten
  Apps, keine Zeiten und keine Fenstertitel (`~/.local/share/zenos/`, nur für den Benutzer lesbar).
- Eine Zwischenablage-Historie, falls sie kommt, ignoriert 1Password und löscht sich selbst.

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
`/run/zenos`. Firmware-Einstellungen (`/boot/firmware/config.txt`, EEPROM) fasst zenOS nie an.

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
  ergäbe höchstens falsche Prozentwerte; ein erneutes Laden behebt es. Den Lüfter am Compute Module 5 regelt der
  Kernel, zenOS liest ihn nur.

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
- GitHub nur mit 2FA. Das Repo ist das System: Wer das Konto übernimmt, bringt Code auf die Rechner.
- Releases enthalten `SHA256SUMS`, optional mit Signatur.
- Im Image werden SSH-Hostschlüssel und `machine-id` gelöscht und beim ersten Start neu erzeugt. Sonst hätten alle Kopien dieselben Schlüssel.
