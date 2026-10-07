# system

Konfiguration, die `scripts/install.sh` ins System legt. Dateien für das System werden kopiert, Dateien im Home als
Verweis angelegt; was generiert wird, erzeugen die Programme unter `scripts/bin/`.

| Pfad | Ziel | Zweck |
|---|---|---|
| `labwc/rc.xml.in` | Vorlage für `~/.config/labwc/rc.xml` (`zenos-labwc`) | Fenstermanager: Regionen, Tastenkürzel (auch Super+Shift+L für «Bildschirm aus» und die Ein/Aus-Taste, `docs/module/energie.md`; Super+Tab für die Fensterübersicht und Super+H für den Schreibtisch, `docs/module/m9.md`), Titelzeile, Scrollen |
| `labwc/{autostart,environment,shutdown,menu.xml}` | `~/.config/labwc/` (Verweise) | Start und Ende der Sitzung, Umgebung, Rechtsklick-Menüs |
| `greeter/labwc/` | direkt aus `/opt/zenos` (`labwc -C`) | labwc des Logins, ohne Vorgabe-Tasten und mit leerem Menü |
| `greetd/config.toml` | `/etc/greetd/config.toml` | Login auf VT 7, kein Autologin |
| `systemd/user/` | `/etc/systemd/user/` | `zenos-sitzung.target`, `zenos-shell`, `zenos-idle` (Sperre, Bildschirm aus, Hemmer der Ein/Aus-Taste), `zenos-kanshi`, Drop-in für `xdg-desktop-portal-wlr` |
| `systemd/system/zenos-argon.service` | `/etc/systemd/system/` | Argon ONE: Lüfter und Power-Button (V3), Akku, Deckel (GPIO27, nur lesend) und Ausschalten bei 3 % Akku (ONE UP), Mindeststufe für den Lüfter, `/run/zenos/geraet.json` |
| `systemd/system/zenos-gesten.service` | `/etc/systemd/system/` (`82-gesten`, ohne `[Install]`, udev startet ihn mit Touchpad) | Wischen mit drei Fingern: liest reine Touchpads nur lesend über libinput (Benutzer `zenos-gesten`, gehärtet), meldet «oben» und «unten» auf `/run/zenos-gesten/gesten.sock`; Rechte und Rückweg (Notschalter `/etc/xdg/zenos/gesten-aus`) in `docs/sicherheit.md`, «Gesten» |
| `udev/72-zenos-gesten.rules` | `/etc/udev/rules.d/` (`82-gesten`) | Knoten reiner Touchpads (ohne Tasten) `root:zenos-gesten` mit 0640 statt `root:input`, startet `zenos-gesten.service` |
| `sysusers/zenos-gesten.conf` | `/etc/sysusers.d/` (`82-gesten`, `systemd-sysusers`) | gesperrter Dienstbenutzer `zenos-gesten` ohne Home und ohne weitere Gruppen |
| `systemd/system/zenos-wlan-land.service` | `/etc/systemd/system/` (`35-netzwerk`) | WLAN-Land mit `iw` setzen, nach `zen netzwerk umstellen` |
| `systemd/system/zenos-netzwerk-erststart.service` | `/etc/systemd/system/` (aktiviert nur im Image) | erster Start eines Images: auf NetworkManager umstellen |
| `systemd/system/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf` | `/etc/systemd/system/…` | wait-online überspringen, solange NetworkManager das Netz verwaltet |
| `systemd/system/zenos-kanal-holen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: Tags und Branches von origin holen, ohne Rechte (DynamicUser, Sandbox) |
| `systemd/system/zenos-kanal-pruefen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: das Bundle als root ohne Netz prüfen, Stand schreiben, ein Ziel für `zen update` bereitstellen |
| `systemd/system/zenos-kanal-installieren.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: das bereitgestellte Ziel als root installieren (Inhibitor, `KillMode=mixed`), Gesundheit prüfen, sonst Rückweg |
| `systemd/system/zenos-kanal-nachstart.service` | `/etc/systemd/system/` (`14-kanal`, aktiviert) | nach einem Abbruch beim Start vor greetd die Übernahme des Codes vollenden (`install.sh --nur-code`, ohne Netz) |
| `systemd/system/zenos-kanal-jetzt@.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | «Jetzt installieren» in den Einstellungen: wie `zen update` ohne Terminal, ohne Frage und ohne neues Holen, nur für den angezeigten Stand (Instanz: Tag-Objekt bzw. Commit; nur über `zenos-kanal-bedienen`) |
| `systemd/system/zenos-kanal-zustimmen@.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | «Zustimmen …» in den Einstellungen: das «ja» für genau das Tag-Objekt der Instanz, nur gültig signiert (nur über `zenos-kanal-bedienen`) |
| `systemd/system/zenos-kanal.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert, ausser mit Notschalter) | Automatik: 10–20 Min. nach dem Start, dann alle 6 h, `Persistent` |
| `systemd/system/zenos-kanal-automatik.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | ein Lauf der Automatik: auf die Uhr warten, holen, prüfen, installieren, wenn der Zeitpunkt passt (nie dev) |
| `systemd/system/zenos-kanal-gelegenheit.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert, ausser mit Notschalter) | Automatik: alle 15 Min. eine Gelegenheit zum Installieren |
| `systemd/system/zenos-kanal-gelegenheit.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | wie die Automatik ohne Holen, nur wenn ein Stand bereit ist oder eine Installation unterbrochen wurde |
| `systemd/system/zenos-kanal-bestaetigen.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert) | 2 Min. nach jedem Start: Bestätigung eines automatischen Updates |
| `systemd/system/zenos-kanal-bestaetigen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | Login nach dem Neustart da? Dann gilt der Stand als gut; bei zwei Starts ohne Login zurück auf den guten Stand |
| `systemd/system/zenos-basis-pruefen.service` | `/etc/systemd/system/` (`71-basis`, statisch) | Basis-Updates: `apt-get update` und Auswertung von `apt-get -s full-upgrade` als root mit Netz (ohne eigenen Mount-Namensraum, sonst liesse apt die Staffelung aus) |
| `systemd/system/zenos-basis-installieren.service` | `/etc/systemd/system/` (`71-basis`, statisch) | Basis-Updates: genau die geprüfte Liste installieren (Inhibitor, `KillMode=mixed`, Laufzeitordner `/run/zenos-basis`), danach `install.sh` und Gesundheitsprüfung |
| `systemd/system/zenos-basis-automatik.timer` | `/etc/systemd/system/` (`71-basis`, aktiviert, ausser Notschalter) | Basis-Updates automatisch: 30 Min. nach dem Start, dann alle 6 h (03, 09, 15, 21 Uhr, versetzt zum Kanal) |
| `systemd/system/zenos-basis-automatik.service` | `/etc/systemd/system/` (`71-basis`, statisch) | ein Lauf: prüfen, eine Liste ohne Kernel, Firmware, Bootloader und Entfernungen installieren, wenn `zenos-kanal automatik darf --ohne-ssh` ja sagt (Sandbox wie die Automatik des Kanals) |
| `systemd/system/zenos-basis-gelegenheit.timer` | `/etc/systemd/system/` (`71-basis`, aktiviert, ausser Notschalter) | alle 15 Min. (7, 22, 37, 52) |
| `systemd/system/zenos-basis-gelegenheit.service` | `/etc/systemd/system/` (`71-basis`, statisch) | nur mit `/var/lib/zenos/basis/automatik-bereit`: die bereite Liste ohne `apt-get update` installieren, wenn es darf |
| `modprobe/zenos-brcmfmac.conf` | `/etc/modprobe.d/` (von `zen netzwerk umstellen` bzw. im Image) | WPA3 im WLAN-Treiber des Raspberry Pi aus (`docs/module/netzwerk.md`) |
| `cloud/99-zenos-netzwerk.cfg` | `/etc/cloud/cloud.cfg.d/` (von `zen netzwerk umstellen`, nie im Image) | cloud-init schreibt keine Netzwerk-Konfiguration mehr |
| `doc/RECHTLICHES`, `doc/QUELLEN` | `/usr/local/share/doc/zenos/` (Modul `72-kennung`, neben `copyright` aus `LICENSE`) | Lizenzen, Markenhinweise und wo der Quellcode liegt; `/etc/legal` verweist darauf |
| `systemd/system-shutdown/zenos-argon` | `/usr/lib/systemd/system-shutdown/` | Abschaltsignal an die Argon-Platine beim Ausschalten |
| `portal/labwc-portals.conf` | `/etc/xdg/xdg-desktop-portal/` | Portale: `gtk`, Bildschirm über `wlr` |
| `portal/xdpw.conf` | `/etc/xdg/xdg-desktop-portal-wlr/config` | Bildschirmwahl und Erkennung der Freigabe |
| `xdg/labwc-mimeapps.list` | `/etc/xdg/labwc-mimeapps.list` | Standard-Apps der labwc-Sitzung: Ordner öffnet Thunar (`48-ablage`) |
| `thunar/uca.xml` | `~/.config/Thunar/uca.xml` (Kopie, nur mit der zenOS-Marke in der ersten Zeile) | Thunar: «Terminal hier öffnen» mit kitty (`48-ablage`) |
| `applications/thunar-bulk-rename.desktop`, `applications/thunar-settings.desktop` | `/usr/local/share/applications/` | Hilfsstarter von Thunar ausblenden (`Hidden=true`, `48-ablage`) |
| `pam/zenos-sperre` | direkt aus `/opt/zenos` (`configDirectory`) | PAM-Dienst des Sperrbildschirms |
| `polkit/org.zenos.firewall.policy` | `/usr/share/polkit-1/actions/` | polkit-Aktionen für den Schalter «Firewall» (pkexec mit `zenos-firewall`, Ausschalten nur mit Passwort) |
| `polkit/org.zenos.luefter.policy` | `/usr/share/polkit-1/actions/` (`80-argon`) | polkit-Aktion für die Zeile «Lüfter» im System-Menü (pkexec mit `zenos-luefter`, ohne Passwort, nur in der aktiven Sitzung am Gerät) |
| `polkit/org.zenos.kanal.policy` | `/usr/share/polkit-1/actions/` (`14-kanal`) | polkit-Aktionen für Einstellungen › System › Updates (pkexec mit `zenos-kanal-bedienen`): prüfen, jetzt installieren und Zeitpunkt ohne Passwort, zustimmen jedes Mal mit Passwort; für die Ubuntu-Basis `basis-pruefen` und `basis-installieren` ohne Passwort, `basis-installieren-zustimmen` (Kernel, Firmware, Bootloader, Entfernungen) jedes Mal mit Passwort; nur in der aktiven Sitzung am Gerät |
| `kitty/kitty.conf` | `~/.config/kitty/kitty.conf` (Verweis) | Terminal, schlaues Ctrl+C, Super-Kürzel |
| `fish/zenos.fish`, `fish/functions/` | `~/.config/fish/conf.d/zenos.fish` (Verweis) | Shell: Eingabezeile, Statuszeile, `?`, Warnung vor gefährlichen Befehlen |
| `chrome/policies/zenos.json` | `/etc/opt/chrome/policies/managed/` | Chrome-Richtlinien (`docs/sicherheit.md`) |
| `vscode/policy.json` | `/etc/vscode/policy.json` | VS Code ohne Telemetrie |
| `apt/20auto-upgrades`, `apt/52zenos-unattended` | `/etc/apt/apt.conf.d/` | automatische Sicherheitsupdates (unattended-upgrades; die übrigen Paket-Updates bringt `zenos-basis`) |
| `update-manager/zenos.cfg` | `/etc/update-manager/release-upgrades.d/` (`71-basis`) | `Prompt=never`: kein Wechsel der Ubuntu-Hauptversion, keine Abfrage neuer Versionen (die Conffile `release-upgrades` bleibt unberührt; nur ASCII) |
| `basis` | wird nicht installiert, `zenos-kanal` liest es aus dem geprüften Stand | Ubuntu-Version, für die der Stand gebaut ist (`26.04`); ein Stand für eine andere Version kommt nie als Update (`docs/image-und-releases.md`, «Basiswechsel») |
| `apt/zenos-ohne-snapd` | `/etc/apt/preferences.d/` (`22-aufraeumen`, nur solange snapd fehlt) | apt-Pin: snapd nie wieder installieren |
| `plymouth/zenos/` | `/usr/share/plymouth/themes/zenos/` (`42-bootsplash`, nur `*.plymouth`, `*.script`, `bilder/`) | Bootsplash-Theme, abgelegt, nicht eingeschaltet (`docs/module/bootsplash.md`); `erzeugen.py` und `vorschau.sh` bleiben im Repo |
| `vertrauen/release`, `wurzel`, `widerrufen`, `serie` | `/etc/zenos/vertrauen/` (`12-vertrauen`, nur wenn es fehlt oder leer ist; im Image) | Vertrauensanker: öffentliche Prüfschlüssel für signierte Releases, Prinzipale `zenos-release` und `zenos-wurzel`; noch ohne Schlüssel (`docs/image-und-releases.md`, «Signierte Releases») |

Ein Ordner kommt nur mit seinem Modul dazu (Besitz und Einzelheiten in `docs/module/`).
