# system

Konfiguration, die `scripts/install.sh` ins System legt. Dateien für das System werden kopiert, Dateien im Home als
Verweis angelegt; was generiert wird, erzeugen die Programme unter `scripts/bin/`.

| Pfad | Ziel | Zweck |
|---|---|---|
| `labwc/rc.xml.in` | Vorlage für `~/.config/labwc/rc.xml` (`zenos-labwc`) | Fenstermanager: Regionen, Tastenkürzel (auch Super+Shift+L für «Bildschirm aus» und die Ein/Aus-Taste, `docs/module/energie.md`), Titelzeile, Scrollen |
| `labwc/{autostart,environment,shutdown,menu.xml}` | `~/.config/labwc/` (Verweise) | Start und Ende der Sitzung, Umgebung, Rechtsklick-Menüs |
| `greeter/labwc/` | direkt aus `/opt/zenos` (`labwc -C`) | labwc des Logins, ohne Vorgabe-Tasten und mit leerem Menü |
| `greetd/config.toml` | `/etc/greetd/config.toml` | Login auf VT 7, kein Autologin |
| `systemd/user/` | `/etc/systemd/user/` | `zenos-sitzung.target`, `zenos-shell`, `zenos-idle` (Sperre, Bildschirm aus, Hemmer der Ein/Aus-Taste), `zenos-kanshi`, Drop-in für `xdg-desktop-portal-wlr` |
| `systemd/system/zenos-argon.service` | `/etc/systemd/system/` | Argon ONE: Lüfter und Power-Button (V3), Akku, Deckel (GPIO27, nur lesend) und Ausschalten bei 3 % Akku (ONE UP), Mindeststufe für den Lüfter, `/run/zenos/geraet.json` |
| `systemd/system/zenos-wlan-land.service` | `/etc/systemd/system/` (`35-netzwerk`) | WLAN-Land mit `iw` setzen, nach `zen netzwerk umstellen` |
| `systemd/system/zenos-netzwerk-erststart.service` | `/etc/systemd/system/` (aktiviert nur im Image) | erster Start eines Images: auf NetworkManager umstellen |
| `systemd/system/systemd-networkd-wait-online.service.d/zenos-netzwerk.conf` | `/etc/systemd/system/…` | wait-online überspringen, solange NetworkManager das Netz verwaltet |
| `systemd/system/zenos-kanal-holen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: Tags und Branches von origin holen, ohne Rechte (DynamicUser, Sandbox) |
| `systemd/system/zenos-kanal-pruefen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: das Bundle als root ohne Netz prüfen, Stand schreiben, ein Ziel für `zen update` bereitstellen |
| `systemd/system/zenos-kanal-installieren.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | signierter Kanal: das bereitgestellte Ziel als root installieren (Inhibitor, `KillMode=mixed`), Gesundheit prüfen, sonst Rückweg |
| `systemd/system/zenos-kanal-nachstart.service` | `/etc/systemd/system/` (`14-kanal`, aktiviert) | nach einem Abbruch beim Start vor greetd die Übernahme des Codes vollenden (`install.sh --nur-code`, ohne Netz) |
| `systemd/system/zenos-kanal-jetzt.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | «Jetzt installieren» in den Einstellungen: wie `zen update` ohne Terminal und ohne Frage (nur über `zenos-kanal-bedienen`) |
| `systemd/system/zenos-kanal-zustimmen@.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | «Zustimmen …» in den Einstellungen: das «ja» für genau das Tag-Objekt der Instanz, nur gültig signiert (nur über `zenos-kanal-bedienen`) |
| `systemd/system/zenos-kanal.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert, ausser mit Notschalter) | Automatik: 10–20 Min. nach dem Start, dann alle 6 h, `Persistent` |
| `systemd/system/zenos-kanal-automatik.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | ein Lauf der Automatik: auf die Uhr warten, holen, prüfen, installieren, wenn der Zeitpunkt passt (nie dev) |
| `systemd/system/zenos-kanal-gelegenheit.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert, ausser mit Notschalter) | Automatik: alle 15 Min. eine Gelegenheit zum Installieren |
| `systemd/system/zenos-kanal-gelegenheit.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | wie die Automatik ohne Holen, nur wenn ein Stand bereit ist oder eine Installation unterbrochen wurde |
| `systemd/system/zenos-kanal-bestaetigen.timer` | `/etc/systemd/system/` (`14-kanal`, aktiviert) | 2 Min. nach jedem Start: Bestätigung eines automatischen Updates |
| `systemd/system/zenos-kanal-bestaetigen.service` | `/etc/systemd/system/` (`14-kanal`, statisch) | Login nach dem Neustart da? Dann gilt der Stand als gut; bei zwei Starts ohne Login zurück auf den guten Stand |
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
| `polkit/org.zenos.kanal.policy` | `/usr/share/polkit-1/actions/` (`14-kanal`) | polkit-Aktionen für Einstellungen › System › Updates (pkexec mit `zenos-kanal-bedienen`): prüfen, jetzt installieren und Zeitpunkt ohne Passwort, zustimmen jedes Mal mit Passwort; nur in der aktiven Sitzung am Gerät |
| `kitty/kitty.conf` | `~/.config/kitty/kitty.conf` (Verweis) | Terminal, schlaues Ctrl+C, Super-Kürzel |
| `fish/zenos.fish`, `fish/functions/` | `~/.config/fish/conf.d/zenos.fish` (Verweis) | Shell: Eingabezeile, Statuszeile, `?`, Warnung vor gefährlichen Befehlen |
| `chrome/policies/zenos.json` | `/etc/opt/chrome/policies/managed/` | Chrome-Richtlinien (`docs/sicherheit.md`) |
| `vscode/policy.json` | `/etc/vscode/policy.json` | VS Code ohne Telemetrie |
| `apt/20auto-upgrades`, `apt/52zenos-unattended` | `/etc/apt/apt.conf.d/` | automatische Sicherheitsupdates |
| `apt/zenos-ohne-snapd` | `/etc/apt/preferences.d/` (`22-aufraeumen`, nur solange snapd fehlt) | apt-Pin: snapd nie wieder installieren |
| `plymouth/zenos/` | `/usr/share/plymouth/themes/zenos/` (`42-bootsplash`, nur `*.plymouth`, `*.script`, `bilder/`) | Bootsplash-Theme, abgelegt, nicht eingeschaltet (`docs/module/bootsplash.md`); `erzeugen.py` und `vorschau.sh` bleiben im Repo |
| `vertrauen/release`, `wurzel`, `widerrufen`, `serie` | `/etc/zenos/vertrauen/` (`12-vertrauen`, nur wenn es fehlt oder leer ist; im Image) | Vertrauensanker: öffentliche Prüfschlüssel für signierte Releases, Prinzipale `zenos-release` und `zenos-wurzel`; noch ohne Schlüssel (`docs/image-und-releases.md`, «Signierte Releases») |

Ein Ordner kommt nur mit seinem Modul dazu (Besitz und Einzelheiten in `docs/module/`).
